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

    # iOS app and the native GoogleService-Info.plist both belong to this project.
    # wind-alarm-agent-eb65f is a different Firebase project and will not deliver pushes.
    EXPECTED_FIREBASE_PROJECT_ID = "wind-alarm-agent"
    IOS_BUNDLE_ID = "de.dominikvoss.wind-alarm"

    # wc is the station id (webcam.name), which is not always the URL slug.
    # Malcesine's page is /gardasee/malcesine/ but the station id is "gardasee".
    WEBCAMS = {
        "trimini": {
            "slug": "trimini",
            "wc": "kochelsee",
            "timezone": "Europe/Berlin",
            "page_url": "https://www.addicted-sports.com/webcam/kochelsee/trimini/",
            "image_url": "https://www.addicted-sports.com/fileadmin/webcam/kochelsee/current/640.jpg",
        },
        "malcesinenord": {
            "slug": "malcesinenord",
            "wc": "malcesinenord",
            "timezone": "Europe/Rome",
            "page_url": "https://www.addicted-sports.com/webcam/gardasee/malcesinenord/",
            "image_url": "https://www.addicted-sports.com/fileadmin/webcam/malcesinenord/current/640.jpg",
        },
        "malcesine": {
            "slug": "malcesine",
            "wc": "gardasee",
            "timezone": "Europe/Rome",
            "page_url": "https://www.addicted-sports.com/webcam/gardasee/malcesine/",
            "image_url": "https://www.addicted-sports.com/fileadmin/webcam/gardasee/current/640.jpg",
        },
        "campione": {
            "slug": "campione",
            "wc": "campione",
            "timezone": "Europe/Rome",
            "page_url": "https://www.addicted-sports.com/webcam/gardasee/campione/",
            "image_url": "https://www.addicted-sports.com/fileadmin/webcam/campione/current/640.jpg",
        },
    }

    # Local windows are Europe/Berlin clock times, inclusive. UTC crons are the
    # union of CET (UTC+1) and CEST (UTC+2) so both seasons are covered.
    # GitHub fires every 15 minutes and is only a backup. EventBridge is primary
    # and fires every 5 minutes once Terraform is applied.
    LOCATIONS = {
        "kochelsee": {
            "name": "Kochelsee",
            "fcm_topic": "wind_alarms_kochelsee",
            "threshold_knots": 10.0,
            "freshness_minutes": 60,
            "local_start": "05:00",
            "local_end": "08:00",
            "github_cron": "*/15 3-7 * * *",
            "eventbridge_cron": "cron(*/5 3-7 * * ? *)",
            "urls": [
                "https://www.addicted-sports.com/webcam/kochelsee/trimini/"
            ],
        },
        "gardasee": {
            "name": "Gardasee",
            "fcm_topic": "wind_alarms_gardasee",
            "threshold_knots": 12.0,
            "freshness_minutes": 60,
            "local_start": "05:00",
            "local_end": "10:00",
            "github_cron": "*/15 3-9 * * *",
            "eventbridge_cron": "cron(*/5 3-9 * * ? *)",
            "urls": [
                "https://www.addicted-sports.com/webcam/gardasee/malcesinenord/",
                "https://www.addicted-sports.com/webcam/gardasee/malcesine/",
                "https://www.addicted-sports.com/webcam/gardasee/campione/",
            ],
        },
    }

    # OCR settings
    OCR_LANGUAGES = ["en", "de"]

    def webcam_for_url(self, url: str) -> dict:
        """Registry entry for a webcam page. Unknown pages fall back to the URL slug."""
        slug = (url or "").split("#", 1)[0].rstrip("/").split("/")[-1].lower()
        if slug in self.WEBCAMS:
            return self.WEBCAMS[slug]
        return {
            "slug": slug or "webcam",
            "wc": slug or "webcam",
            "timezone": "Europe/Berlin",
            "page_url": url,
            "image_url": "",
        }

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
                    parsed = json.loads(raw_json)
                    cred = credentials.Certificate(parsed)
                except (json.JSONDecodeError, ValueError) as exc:
                    logging.error("FIREBASE_SERVICE_ACCOUNT_JSON is not valid service account JSON: %s", exc)
                    raise
                project_id = parsed.get("project_id")
                if project_id and project_id != self.EXPECTED_FIREBASE_PROJECT_ID:
                    logging.error(
                        "Firebase service account project_id %s does not match the iOS app project %s "
                        "(bundle %s). Pushes will not reach the phone.",
                        project_id,
                        self.EXPECTED_FIREBASE_PROJECT_ID,
                        self.IOS_BUNDLE_ID,
                    )
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
