"""
Logging utility for the Wind Alarm project.
"""
import logging
import sys

def configure_logging() -> None:
    """Attach one stdout handler to the root logger so library logs are visible."""
    root = logging.getLogger()
    if root.handlers:
        return
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
        stream=sys.stdout,
    )


def get_logger(name: str) -> logging.Logger:
    """Provides a configured logger instance."""
    configure_logging()
    logger = logging.getLogger(name)
    logger.setLevel(logging.INFO)
    return logger
