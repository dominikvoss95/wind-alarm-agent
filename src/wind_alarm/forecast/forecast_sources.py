"""
Configuration of forecast sources for Gardasee and Kochelsee.
"""

FORECAST_SOURCES = {
    "gardasee": [
        {
            "id": "foehn_diagram",
            "name": "Föhndiagramm",
            "url": "https://www.wwwind.com/de/wind-und-wetter/",
            "type": "diagram",
        },
        {
            "id": "windfinder_forecast",
            "name": "Windfinder 7-Tage",
            "url": "https://de.windfinder.com/forecast/lake_garda_malcesine",
            "type": "table",
        },
        {
            "id": "windfinder_superforecast",
            "name": "Windfinder Superforecast",
            "url": "https://de.windfinder.com/weatherforecast/lake_garda_malcesine",
            "type": "table",
        },
        {
            "id": "windguru_arome",
            "name": "Windguru AROME 1.3km",
            "url": "https://www.windguru.cz/501238",
            "type": "table",
        },
    ],
    "kochelsee": [
        {
            "id": "windfinder_forecast",
            "name": "Windfinder 7-Tage",
            "url": "https://de.windfinder.com/forecast/kochelsee_trimini",
            "type": "table",
        },
        {
            "id": "windfinder_superforecast",
            "name": "Windfinder Superforecast",
            "url": "https://de.windfinder.com/weatherforecast/kochelsee_trimini",
            "type": "table",
        },
        {
            "id": "patscherkofel",
            "name": "Patscherkofel (Föhn-Indikator)",
            "url": "https://de.windfinder.com/weatherforecast/patscherkofel",
            "type": "table",
        },
    ],
}
