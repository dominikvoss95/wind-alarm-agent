"""
Forecast analyzer module using Amazon Bedrock to extract and evaluate meteorological sources.
"""
import json
import logging
import os
import re
from typing import Dict, Any

from wind_alarm.config import config
from wind_alarm.forecast.forecast_sources import FORECAST_SOURCES

logger = logging.getLogger("wind_alarm.forecast_analyzer")

def analyze_forecasts(location_id: str, screenshots: Dict[str, str]) -> Dict[str, Any]:
    """
    Analyzes screenshots of various forecast sources using Amazon Bedrock.
    Returns a structured dictionary with the forecast evaluation.
    """
    if not screenshots:
        logger.warning("No screenshots provided for forecast analysis of %s", location_id)
        return _get_error_fallback(location_id, "No screenshots captured from sources.")

    if not config.USE_AWS:
        logger.info("Local mode: Returning mock forecast data for %s", location_id)
        return _get_mock_forecast(location_id)

    try:
        import boto3

        bedrock_region = os.environ.get("BEDROCK_REGION", "us-east-1")
        client = boto3.client("bedrock-runtime", region_name=bedrock_region)

        prompt = (
            "You are an expert local meteorologist specialized in predicting wind conditions for water sports (windsurfing, kitesurfing, wingfoiling) "
            f"at {location_id.upper()}. Analyze the provided screenshots of various forecast sources and graphs, and construct "
            "an uncertainty-based wind forecast.\n\n"
            "Here are the screenshots provided in order:\n"
        )
        for idx, (source_id, _) in enumerate(screenshots.items()):
            prompt += f"Image {idx + 1}: Screenshot of the source '{source_id}'\n"

        prompt += (
            "\nAnalyze all images carefully. Pay special attention to:\n"
        )
        if location_id == "kochelsee":
            prompt += (
                "- Patscherkofel wind station: High wind speeds (> 30 kts / 50-60 km/h) and strong gusts there indicate a strong south Föhn, which might break through at Kochelsee.\n"
                "- Windfinder Forecast / Superforecast: Check wind speed, gust speed, and direction at Kochelsee (Trimini).\n"
            )
        elif location_id == "gardasee":
            prompt += (
                "- Föhndiagramm: Look at the pressure difference curve Innsbruck-Bozen. A high positive pressure difference (> 4-6 hPa) indicates South Föhn, which can blow strongly at North Lake Garda.\n"
                "- Windfinder / Superforecast / Windguru Arome: Look at the wind speed, gusts, and direction (North/Pelér in the morning, South/Ora in the afternoon) to see if there is a consensus.\n"
            )

        prompt += (
            "\nProvide your analysis. You MUST return ONLY a JSON object of this structure. Do not output markdown code blocks (like ```json), just raw JSON.\n"
            "{\n"
            '  "summary": "Short 1-2 sentence German summary of the forecast.",\n'
            '  "wind_probability_percent": 85,\n'
            '  "confidence": "high", // must be "high", "medium", or "low"\n'
            '  "expected_wind_knots": {"min": 12, "max": 20},\n'
            '  "expected_direction": "N",\n'
            '  "best_time_window": "10:00 - 15:00",\n'
            '  "model_consensus": "German explanation of consensus/discrepancies between sources.",\n'
            '  "sources_analyzed": [\n'
            '    {"name": "SourceName", "summary": "Short German summary of this source\'s indication"}\n'
            '  ]\n'
            "}"
        )

        content_list = [{"text": prompt}]

        # Append screenshots in order
        for source_id, img_path in screenshots.items():
            if not os.path.exists(img_path):
                continue
            with open(img_path, "rb") as f:
                image_bytes = f.read()
            
            content_list.append({"text": f"--- Screenshot of source: {source_id} ---"})
            content_list.append({
                "image": {
                    "format": "png",
                    "source": {"bytes": image_bytes}
                }
            })

        messages = [
            {
                "role": "user",
                "content": content_list
            }
        ]

        model_id = os.environ.get("BEDROCK_OCR_MODEL_ID", "amazon.nova-lite-v1:0")
        logger.info("Invoking Bedrock model %s for forecast analysis of %s", model_id, location_id)
        
        response = client.converse(
            modelId=model_id,
            messages=messages,
            inferenceConfig={"maxTokens": 1000, "temperature": 0.0}
        )

        response_text = response['output']['message']['content'][0]['text']
        logger.info("Bedrock raw response received. Parsing JSON...")

        # Extract JSON block
        start_idx = response_text.find("{")
        end_idx = response_text.rfind("}")
        if start_idx != -1 and end_idx != -1 and end_idx > start_idx:
            json_str = response_text[start_idx:end_idx + 1]
            parsed_data = json.loads(json_str)
            return parsed_data
        else:
            raise ValueError(f"Could not extract valid JSON block from model response: {response_text}")

    except Exception as exc:
        logger.error("Failed to analyze forecasts via Bedrock: %s", exc)
        return _get_error_fallback(location_id, f"Analysis failed: {str(exc)}")


def _get_error_fallback(location_id: str, error_msg: str) -> Dict[str, Any]:
    """Fallback dict in case of errors."""
    return {
        "summary": "Vorhersage konnte nicht generiert werden.",
        "wind_probability_percent": 0,
        "confidence": "low",
        "expected_wind_knots": {"min": 0, "max": 0},
        "expected_direction": "-",
        "best_time_window": "-",
        "model_consensus": f"Fehler bei der Analyse: {error_msg}",
        "sources_analyzed": []
    }


def _get_mock_forecast(location_id: str) -> Dict[str, Any]:
    """Generates mock forecast for local development/testing."""
    if location_id == "kochelsee":
        return {
            "summary": "Mäßiger Föhnwind am Nachmittag wahrscheinlich, da Patscherkofel anzieht.",
            "wind_probability_percent": 65,
            "confidence": "medium",
            "expected_wind_knots": {"min": 10, "max": 18},
            "expected_direction": "S",
            "best_time_window": "14:00 - 18:00",
            "model_consensus": "Superforecast zeigt leichten Südwind, Föhnindikatoren deuten auf stärkere Böen hin.",
            "sources_analyzed": [
                {"name": "Windfinder 7-Tage", "summary": "Leichter Südwind (6-8 kts) angesagt."},
                {"name": "Windfinder Superforecast", "summary": "10 kts Südwind ab Mittag prognostiziert."},
                {"name": "Patscherkofel (Föhn-Indikator)", "summary": "Föhnstation zeigt ansteigenden Südwind mit Böen bis 32 kts."}
            ]
        }
    else:
        return {
            "summary": "Starker Pelér am Vormittag. Ora am Nachmittag flaut ab.",
            "wind_probability_percent": 85,
            "confidence": "high",
            "expected_wind_knots": {"min": 14, "max": 22},
            "expected_direction": "N",
            "best_time_window": "07:00 - 11:00",
            "model_consensus": "Sehr hohe Übereinstimmung zwischen Windfinder Superforecast und Windguru Arome.",
            "sources_analyzed": [
                {"name": "Föhndiagramm", "summary": "Keine Föhnlage vorhanden (Druckdifferenz +1 hPa)."},
                {"name": "Windfinder Superforecast", "summary": "Zeigt 16 kts Nordwind ab 08:00 Uhr."},
                {"name": "Windguru AROME 1.3km", "summary": "Bestätigt Pelér mit bis zu 22 kts Böen in Malcesine Nord."}
            ]
        }
