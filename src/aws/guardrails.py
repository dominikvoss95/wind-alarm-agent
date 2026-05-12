"""
Bedrock Guardrails for input validation and safety.
"""
import re


def validate_state(state: dict) -> tuple[bool, str]:
    dangerous_patterns = ["<script", "javascript:", "onerror=", "${", "{{", "DROP ", "DELETE ", "../"]
    for field in ["source_identifier", "location_id"]:
        val = state.get(field, "")
        for pattern in dangerous_patterns:
            if pattern.lower() in val.lower():
                return False, f"Dangerous pattern: {pattern}"

    for field, (min_v, max_v) in {"threshold_knots": (0, 100), "freshness_limit_minutes": (1, 1440)}.items():
        val = state.get(field)
        if val is not None:
            try:
                if not min_v <= float(val) <= max_v:
                    return False, f"{field} out of range"
            except (ValueError, TypeError):
                return False, f"{field} must be numeric"
    return True, ""


def sanitize_location_id(loc_id: str) -> str:
    return "".join(c for c in loc_id if c.isalnum() or c in "-_")[:50]