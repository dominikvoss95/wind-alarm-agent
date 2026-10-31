"""
Configuration management for the Wind Alarm project.
Uses environment variables with .env support.
"""
import os
from pathlib import Path
from dotenv import load_dotenv

# Load .env file if present
load_dotenv()

class Config:
    """Central configuration class."""
    
    USE_AWS = os.environ.get("USE_AWS", "false").lower() == "true"
    USE_AZURE = os.environ.get("USE_AZURE", "false").lower() == "true"
    
    # Azure Configuration
    AZURE_OPENAI_ENDPOINT = os.environ.get("AZURE_OPENAI_ENDPOINT")
    AZURE_OPENAI_KEY = os.environ.get("AZURE_OPENAI_KEY")
    AZURE_OPENAI_DEPLOYMENT_NAME = os.environ.get("AZURE_OPENAI_DEPLOYMENT_NAME", "gpt-4o-mini")
    AZURE_COSMOS_ENDPOINT = os.environ.get("AZURE_COSMOS_ENDPOINT")
    AZURE_COSMOS_KEY = os.environ.get("AZURE_COSMOS_KEY")
    AZURE_COSMOS_DB = os.environ.get("AZURE_COSMOS_DB", "wind-alarm-db")
    AZURE_COSMOS_CONTAINER = os.environ.get("AZURE_COSMOS_CONTAINER", "measurements")
    AZURE_STORAGE_CONNECTION_STRING = os.environ.get("AZURE_STORAGE_CONNECTION_STRING")
    AZURE_STORAGE_CONTAINER_NAME = os.environ.get("AZURE_STORAGE_CONTAINER_NAME", "wind-alarm-assets")
    
    # Filesystem Paths
    IS_LAMBDA = bool(os.environ.get("AWS_LAMBDA_FUNCTION_NAME") or os.environ.get("LAMBDA_TASK_ROOT"))
    if IS_LAMBDA:
        ROOT_DIR = Path(os.environ.get("LAMBDA_TASK_ROOT", "/var/task"))
        WRITE_ROOT = Path("/tmp")
    else:
        ROOT_DIR = Path(__file__).parent.parent.parent
        WRITE_ROOT = ROOT_DIR

    DEBUG_DIR = WRITE_ROOT / "debug"
    RAW_IMAGE_DIR = WRITE_ROOT / "data" / "raw" / "webcam"
    
    # Firebase settings
    FIREBASE_CREDENTIALS_PATH = os.environ.get(
        "FIREBASE_CREDENTIALS_PATH", 
        str(ROOT_DIR / "serviceAccountKey.json")
    )
    FCM_TOPIC = os.environ.get("FCM_TOPIC", "wind_alarms")
    
    # Web Monitoring
    CAM_ID = "kochelsee/trimini"
    PAGE_URL_TEMPLATE = "https://www.addicted-sports.com/webcam/{cam_id}/#/{y}/{m}/{d}/{hm}"
    DEFAULT_WEBCAM_URL = "https://www.addicted-sports.com/webcam/kochelsee/trimini/"

    LOCATIONS = {
        "kochelsee": {
            "name": "Kochelsee",
            "fcm_topic": "wind_alarms_kochelsee",
            "urls": [
                "https://www.addicted-sports.com/webcam/kochelsee/trimini/"
            ],
        },
        "gardasee": {
            "name": "Gardasee",
            "fcm_topic": "wind_alarms_gardasee",
            "urls": [
                "https://www.addicted-sports.com/webcam/gardasee/malcesinenord/",
                "https://www.addicted-sports.com/webcam/gardasee/malcesine/",
                "https://www.addicted-sports.com/webcam/gardasee/campione/",
            ],
        },
    }

    # OCR settings
    OCR_LANGUAGES = ["en", "de"]

    def get(self, key: str, default=None):
        """Legacy dictionary-like access."""
        mapping = {
            "webcam.cam_id": self.CAM_ID,
            "webcam.page_url_template": self.PAGE_URL_TEMPLATE,
            "paths.raw_image_dir": str(self.RAW_IMAGE_DIR),
            "webcam.years_back": 5,
            "webcam.daily_at": "12:00",
            "webcam.interval_minutes": 30
        }
        return mapping.get(key, default)

    def initialize_firebase(self):
        """Lazily initialize Firebase Admin SDK."""
        import json
        import logging
        import firebase_admin
        from firebase_admin import credentials
        try:
            firebase_admin.get_app()
        except ValueError:
            raw_json = os.environ.get("FIREBASE_SERVICE_ACCOUNT_JSON")
            if raw_json:
                logging.info("Initializing Firebase Admin SDK from FIREBASE_SERVICE_ACCOUNT_JSON")
                try:
                    cred = credentials.Certificate(json.loads(raw_json))
                except (json.JSONDecodeError, ValueError) as exc:
                    logging.error("FIREBASE_SERVICE_ACCOUNT_JSON is not valid service account JSON: %s", exc)
                    raise
                firebase_admin.initialize_app(cred)
            elif os.path.exists(self.FIREBASE_CREDENTIALS_PATH):
                logging.info("Initializing Firebase Admin SDK from %s", self.FIREBASE_CREDENTIALS_PATH)
                cred = credentials.Certificate(self.FIREBASE_CREDENTIALS_PATH)
                firebase_admin.initialize_app(cred)
            else:
                logging.warning(
                    "Firebase credentials not found at %s and FIREBASE_SERVICE_ACCOUNT_JSON is unset",
                    self.FIREBASE_CREDENTIALS_PATH,
                )
                firebase_admin.initialize_app()


# Create singleton instance
config = Config()

# Ensure directories exist
config.DEBUG_DIR.mkdir(parents=True, exist_ok=True)
config.RAW_IMAGE_DIR.mkdir(parents=True, exist_ok=True)
