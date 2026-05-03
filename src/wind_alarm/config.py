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
    
    # Project Paths
    ROOT_DIR = Path(__file__).parent.parent.parent
    DEBUG_DIR = ROOT_DIR / "debug"
    RAW_IMAGE_DIR = ROOT_DIR / "data" / "raw" / "webcam"
    
    # Firebase
    # Default to serviceAccountKey.json in root if not specified otherwise
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

# Create singleton instance
config = Config()

# Ensure directories exist
config.DEBUG_DIR.mkdir(parents=True, exist_ok=True)
config.RAW_IMAGE_DIR.mkdir(parents=True, exist_ok=True)
