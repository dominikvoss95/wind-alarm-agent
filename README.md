# 🌬️ Wind Alarm Agent

**Enterprise-Ready Multi-Location Wind Monitoring & Notification System.**

An AI-driven automation project for windsurfers and sailors that monitors un-API'd webcams at **Kochelsee** and **Gardasee**, extracts wind data using computer vision (OCR), and triggers loud alerts via Firebase Cloud Messaging.

---

## 🏗️ Architecture

The system follows an **Agentic / Graph-based Architecture** using LangGraph for orchestration. It now supports multiple monitoring locations.

```mermaid
graph TD
    %% Komponentendefinitionen
    subgraph "External Sources"
        W1[Webcam Kochelsee]
        W2[Webcam Gardasee Nord]
        W3[Webcam Gardasee Central]
        W4[Webcam Gardasee South]
    end

    subgraph "Backend (Python / LangGraph)"
        direction TB
        P[Vision Node]
        O[Extraction Node]
        L[Threshold Node]
        F[Notification Node]
    end

    subgraph "Infrastructure (Topics)"
        FCM1((Topic: kochelsee))
        FCM2((Topic: gardasee))
    end

    subgraph "Mobile Client (Flutter)"
        App[Multi-Tab App]
        S[Local Audio Alarm]
    end

    %% Datenfluss
    W1 -- "Process" --> P
    W2 -- "Process" --> P
    W3 -- "Process" --> P
    W4 -- "Process" --> P
    
    P --> O --> L --> F
    
    F -- "If wind" --> FCM1
    F -- "If wind" --> FCM2
    
    FCM1 -. "Subscribe Tab 1" .-> App
    FCM2 -. "Subscribe Tab 2" .-> App
    
    App -- "Wake up!" --> S

    %% Styling
    style Backend fill:#fdf,stroke:#333
    style App fill:#ddf,stroke:#333
```

1.  **Vision Node**: Uses **Playwright** to capture screenshots from specific locations.
2.  **Extraction Node**: Employs **EasyOCR** to parse wind values.
3.  **Threshold Node**: Checks if wind exceeds location-specific thresholds.
4.  **Notification Node**: Sends push messages to specific FCM topics (`wind_alarms_kochelsee`, `wind_alarms_gardasee`).
5.  **Mobile App**: Modern Flutter UI with bottom navigation to switch between monitoring zones.

---

## 🚀 Recent Update: Gardasee Integration

-   **Multi-Webcam Logic**: Monitoring 3 points at Lake Garda (Malcesine Nord, Malcesine, Campione).
-   **Dynamic Topics**: Automatic FCM topic switching based on the active tab in the app.
-   **New Design System**: Teal & Sand color palette for the Gardasee monitoring view.
-   **Modular Backend**: CLI flag `--location` to switch monitoring context.

---

## 📋 Prerequisites

-   **Python 3.10+**
-   **Flutter SDK**
-   **Firebase Project**: `serviceAccountKey.json` from the Firebase Console (placed in root).

---

## 🛠️ Setup & Run

### Backend (Python)
```bash
# Run for Kochelsee
python app.py --location kochelsee

# Run for Gardasee (monitoring 3 webcams)
python app.py --location gardasee
```

### Frontend (Flutter)
```bash
cd app
flutter run
```
