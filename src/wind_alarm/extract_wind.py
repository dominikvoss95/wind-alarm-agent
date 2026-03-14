"""Extract wind speed and gust labels from webcam screenshots via OCR."""

import csv
import re
from datetime import datetime
from pathlib import Path

import cv2
import easyocr

# Region of the weather overlay in 1280×960 frames (y1:y2, x1:x2).
_OVERLAY_CROP = (slice(450, 850), slice(50, 450))

IMG_DIR = Path("data/raw/webcam")
OUTPUT_CSV = Path("data/processed_wind.csv")


def _init_reader() -> easyocr.Reader:
    return easyocr.Reader(["en", "de"])


def parse_ocr_text(raw_text: str) -> tuple[int | None, int | None]:
    """Return (wind_kts, gust_kts) parsed from concatenated OCR output."""
    wind = re.search(r"Wind:?\s*(\d+)\s*kts?", raw_text, re.IGNORECASE)
    gust = re.search(r"B[öo]en:?\s*(\d+)\s*kts?", raw_text, re.IGNORECASE)
    return (
        int(wind.group(1)) if wind else None,
        int(gust.group(1)) if gust else None,
    )


def extract_from_image(img_path: Path, reader: easyocr.Reader):
    """Crop the overlay region, run OCR, return (wind, gust)."""
    img = cv2.imread(str(img_path))
    if img is None:
        return None, None

    crop = img[_OVERLAY_CROP]
    results = reader.readtext(crop)
    full_text = " ".join(text for _, text, _ in results)
    return parse_ocr_text(full_text)


def main():
    reader = _init_reader()
    records: list[dict] = []

    for img_path in sorted(IMG_DIR.glob("*.png")):
        m = re.search(r"full_page_(\d{4}-\d{2}-\d{2}_\d{2}-\d{2})", img_path.name)
        if not m:
            continue
        try:
            ts = datetime.strptime(m.group(1), "%Y-%m-%d_%H-%M")
        except ValueError:
            continue

        wind, gust = extract_from_image(img_path, reader)
        print(f"[{ts}] Wind: {wind} | Gust: {gust}")

        records.append({
            "timestamp": ts.isoformat(),
            "wind_kts": wind if wind is not None else "",
            "gust_kts": gust if gust is not None else "",
            "image": img_path.name,
        })

    if records:
        OUTPUT_CSV.parent.mkdir(parents=True, exist_ok=True)
        with open(OUTPUT_CSV, "w", newline="", encoding="utf-8") as fh:
            w = csv.DictWriter(fh, fieldnames=["timestamp", "wind_kts", "gust_kts", "image"])
            w.writeheader()
            w.writerows(records)
        print(f"\nDone — {len(records)} rows → {OUTPUT_CSV}")


if __name__ == "__main__":
    main()
