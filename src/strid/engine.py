"""PII detection and redaction engine powered by Microsoft Presidio.

This module glues together two Presidio components behind one small class:

* ``presidio_analyzer.AnalyzerEngine`` finds PII spans in text. It ships with
  built-in recognizers (PERSON, EMAIL_ADDRESS, CREDIT_CARD, ...) backed by a
  spaCy NLP model plus regexes, and we register our own Indian banking
  recognizers from :mod:`strid.recognizers_in` on top of it.
* ``presidio_anonymizer.AnonymizerEngine`` takes those spans and rewrites the
  text, in our case replacing each span with a ``<ENTITY_TYPE>`` placeholder.

The CLI in :mod:`strid.cli` is the only consumer, but the class is designed to
be usable as a library as well (construct once, call ``redact``/``highlight``
many times, since building the analyzer loads the spaCy model and is slow).
"""

from presidio_analyzer import AnalyzerEngine, RecognizerResult
from presidio_anonymizer import AnonymizerEngine
from presidio_anonymizer.entities import OperatorConfig

from strid.recognizers_in import ALL_IN_RECOGNIZERS


# Entity types that are scanned for when the caller does not pass an explicit
# list. Presidio only runs recognizers whose supported entity is in this list,
# so adding a recognizer in recognizers_in.py is not enough on its own: its
# entity name must also appear here (or be passed via ``-e`` on the CLI).
#
# The first block are Presidio's built-in, mostly US-centric recognizers. They
# are kept because bank statements and KYC documents routinely contain names,
# emails, phone numbers, IPs and URLs regardless of country.
DEFAULT_ENTITIES = [
    "PERSON",
    "EMAIL_ADDRESS",
    "PHONE_NUMBER",
    "US_SSN",
    "CREDIT_CARD",
    "IP_ADDRESS",
    "IBAN_CODE",
    "US_DRIVER_LICENSE",
    "US_PASSPORT",
    "LOCATION",
    "URL",
    "IN_DOB",
    # Indian banking PII
    "IN_BANK_ACCOUNT",
    "IN_IFSC",
    "IN_PAN",
    "IN_AADHAAR",
    "IN_UPI_ID",
    "IN_MICR",
    "IN_PHONE",
    "IN_PIN_CODE",
    "IN_CUSTOMER_ID",
    "IN_BRANCH_CODE",
    "IN_TXN_REF",
    "IN_UPI_NARRATION",
]


class StridEngine:
    """Wraps Presidio analyzer + anonymizer into a single interface.

    One instance holds a fully initialised ``AnalyzerEngine`` (including the
    spaCy model and all custom recognizers) and an ``AnonymizerEngine``.
    Construction is expensive (seconds), so callers should create the engine
    once and reuse it across documents.

    Attributes:
        analyzer: The Presidio ``AnalyzerEngine`` with Indian recognizers
            registered on its recognizer registry.
        anonymizer: The Presidio ``AnonymizerEngine`` used by :meth:`redact`.
        entities: Entity type names that will be searched for on every call.
        threshold: Minimum confidence score (0.0-1.0) a detection must reach
            to be reported. Lower values catch more but produce more false
            positives, which matters for the low-scored (0.2-0.4) Indian
            numeric recognizers that rely on context words to be boosted.
    """

    def __init__(self, entities: list[str] | None = None, threshold: float = 0.5):
        """Build the analyzer/anonymizer pair and register custom recognizers.

        Args:
            entities: Entity types to detect. ``None`` (or an empty list) falls
                back to :data:`DEFAULT_ENTITIES`. Names must match the
                ``supported_entity`` of some registered recognizer or they are
                silently ignored by Presidio.
            threshold: Score threshold passed to Presidio on every
                ``analyze`` call. Defaults to 0.5.
        """
        # AnalyzerEngine() with no arguments loads Presidio's default NLP
        # configuration (spaCy ``en_core_web_lg``) and the predefined
        # recognizer set. This is the slow step.
        self.analyzer = AnalyzerEngine()
        # Append each Indian banking recognizer to the registry. They coexist
        # with the built-ins; Presidio runs every recognizer whose entity is
        # requested and later resolves overlaps itself (see ``analyze``).
        for recognizer in ALL_IN_RECOGNIZERS:
            self.analyzer.registry.add_recognizer(recognizer)
        self.anonymizer = AnonymizerEngine()
        # ``or`` deliberately treats an empty list the same as None so that
        # ``strid redact file`` with no ``-e`` flags uses the defaults.
        self.entities = entities or DEFAULT_ENTITIES
        self.threshold = threshold

    def analyze(self, text: str, language: str = "en") -> list[RecognizerResult]:
        """Detect PII entities in text.

        This is the raw Presidio call. Presidio handles scoring internally:
        each recognizer emits a base score for a regex/NER hit, the context
        enhancer boosts that score when one of the recognizer's context words
        (e.g. "ifsc", "aadhaar") appears nearby, and finally overlapping
        results are deduplicated so the highest-scoring span wins. Anything
        below ``self.threshold`` is dropped before being returned.

        Args:
            text: The document text to scan.
            language: ISO language code understood by the loaded NLP model.
                Only ``"en"`` is supported by the default configuration.

        Returns:
            A list of ``RecognizerResult`` objects, each with ``entity_type``,
            ``start``/``end`` character offsets into ``text`` and ``score``.
            Order is whatever Presidio returns (not guaranteed sorted).
        """
        results = self.analyzer.analyze(
            text=text,
            entities=self.entities,
            language=language,
            score_threshold=self.threshold,
        )
        return results

    def redact(self, text: str, language: str = "en") -> str:
        """Detect and replace PII with type placeholders like <PERSON>.

        Runs :meth:`analyze` and then asks the anonymizer to rewrite every
        detected span. The ``replace`` operator is configured per entity type
        so that the replacement text names the type that was removed, e.g.
        ``"Paid to ABCDE1234F"`` becomes ``"Paid to <IN_PAN>"``. This keeps
        the redacted document readable and lets reviewers see *what kind* of
        data was removed without seeing the value.

        Args:
            text: The document text to redact.
            language: Language code forwarded to :meth:`analyze`.

        Returns:
            The redacted text. Length will generally differ from the input
            because placeholders are not the same width as the original
            values. If nothing was detected the text is returned unchanged.
        """
        results = self.analyze(text, language)
        # One OperatorConfig per entity type. Presidio also accepts a single
        # "DEFAULT" key, but mapping each type explicitly lets the placeholder
        # carry the type name.
        operators = {
            entity: OperatorConfig("replace", {"new_value": f"<{entity}>"})
            for entity in self.entities
        }
        # The anonymizer applies operators from the end of the text backwards
        # so earlier offsets stay valid while later spans are rewritten.
        anonymized = self.anonymizer.anonymize(
            text=text,
            analyzer_results=results,
            operators=operators,
        )
        return anonymized.text

    def highlight(self, text: str, language: str = "en") -> list[dict]:
        """Return detected entities with their positions and scores (for dry-run).

        A JSON-friendly view of :meth:`analyze` used by ``strid detect`` and
        ``strid redact --dry-run``. Unlike ``analyze`` the output is sorted by
        start offset so tables read top-to-bottom in document order, and the
        matched substring is included so callers do not have to slice the
        text themselves.

        Args:
            text: The document text to scan.
            language: Language code forwarded to :meth:`analyze`.

        Returns:
            A list of dicts, one per detection, sorted by ``start``. Keys:
            ``entity_type`` (str), ``start`` (int), ``end`` (int, exclusive),
            ``score`` (float rounded to 2 decimals) and ``text`` (the exact
            matched substring).
        """
        results = self.analyze(text, language)
        return [
            {
                "entity_type": r.entity_type,
                "start": r.start,
                "end": r.end,
                # Rounded for display; the raw Presidio score has many
                # decimal places that add noise in tables/JSON.
                "score": round(r.score, 2),
                # Slice the original text rather than trusting any value on
                # the result object, so the output always reflects the input.
                "text": text[r.start : r.end],
            }
            for r in sorted(results, key=lambda x: x.start)
        ]
