"""strid - CLI tool to detect and redact PII from text documents.

This is the top-level package for the Python reference implementation of
strid. It is intentionally tiny: the real work lives in the submodules.

Package layout:
    strid.engine          -- ``StridEngine``, a thin wrapper around Microsoft
                             Presidio's analyzer and anonymizer, plus the
                             ``DEFAULT_ENTITIES`` list.
    strid.recognizers_in  -- custom regex-based Presidio recognizers for
                             Indian banking PII (PAN, Aadhaar, IFSC, UPI...).
    strid.cli             -- the Typer command-line interface (``strid redact``,
                             ``strid detect``, ``strid entities``).

Only the version string is defined here so that ``import strid`` stays cheap
and does not pull in Presidio (which is slow to import) unless the engine is
actually needed.
"""

# Semantic version of the Python package. Bump this alongside pyproject.toml
# when cutting a release; nothing else in the package reads it at runtime.
__version__ = "0.1.0"
