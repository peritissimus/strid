"""PII detection and redaction engine powered by Microsoft Presidio."""

from presidio_analyzer import AnalyzerEngine, RecognizerResult
from presidio_anonymizer import AnonymizerEngine
from presidio_anonymizer.entities import OperatorConfig

from strid.recognizers_in import ALL_IN_RECOGNIZERS


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
    "DATE_TIME",
    "URL",
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
    """Wraps Presidio analyzer + anonymizer into a single interface."""

    def __init__(self, entities: list[str] | None = None, threshold: float = 0.5):
        self.analyzer = AnalyzerEngine()
        for recognizer in ALL_IN_RECOGNIZERS:
            self.analyzer.registry.add_recognizer(recognizer)
        self.anonymizer = AnonymizerEngine()
        self.entities = entities or DEFAULT_ENTITIES
        self.threshold = threshold

    def analyze(self, text: str, language: str = "en") -> list[RecognizerResult]:
        """Detect PII entities in text."""
        results = self.analyzer.analyze(
            text=text,
            entities=self.entities,
            language=language,
            score_threshold=self.threshold,
        )
        return results

    def redact(self, text: str, language: str = "en") -> str:
        """Detect and replace PII with type placeholders like <PERSON>."""
        results = self.analyze(text, language)
        operators = {
            entity: OperatorConfig("replace", {"new_value": f"<{entity}>"})
            for entity in self.entities
        }
        anonymized = self.anonymizer.anonymize(
            text=text,
            analyzer_results=results,
            operators=operators,
        )
        return anonymized.text

    def highlight(self, text: str, language: str = "en") -> list[dict]:
        """Return detected entities with their positions and scores (for dry-run)."""
        results = self.analyze(text, language)
        return [
            {
                "entity_type": r.entity_type,
                "start": r.start,
                "end": r.end,
                "score": round(r.score, 2),
                "text": text[r.start : r.end],
            }
            for r in sorted(results, key=lambda x: x.start)
        ]
