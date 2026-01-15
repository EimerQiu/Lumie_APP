# Lumie Activity App Demo

A Flutter + Python demo application for the Lumie Activity feature, designed for teens aged 13-21 with chronic health conditions.

## Features

### Activity Tracking
- **Activity Time**: Daily aggregate of physical movement duration
- **Activity Intensity**: Teen-safe categorical scale (Low, Moderate, High)
- **Adaptive Goals**: Personalized daily targets based on sleep and recovery
- **Manual Entry**: Fallback activity logging with ring detection support
- **Six-Minute Walk Test**: Self-referenced functional fitness check-in

### Design
- Light/Lemon Yellow theme with gradient accents
- Modern, accessible UI designed for teens
- Ring status indicators and connection management

## Project Structure

```
Lumie_APP/
├── lumie_activity_app/          # Flutter Frontend
│   └── lib/
│       ├── core/
│       │   ├── theme/           # Color palette & theme
│       │   ├── constants/       # API constants
│       │   └── utils/           # API service
│       ├── features/
│       │   ├── dashboard/       # Home screen
│       │   ├── activity/        # Activity history
│       │   ├── manual_entry/    # Manual activity logging
│       │   └── walk_test/       # 6-Minute Walk Test
│       └── shared/
│           ├── models/          # Data models
│           └── widgets/         # Reusable components
│
└── lumie_backend/               # Python Backend
    └── app/
        ├── api/                 # FastAPI routes
        ├── models/              # Pydantic models
        └── services/            # Business logic
```

## Running the App

### Backend (Python)

```bash
cd lumie_backend

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Run the server
python run.py
```

The API will be available at `http://localhost:8000`
- API docs: `http://localhost:8000/docs`
- ReDoc: `http://localhost:8000/redoc`

### Frontend (Flutter)

```bash
cd lumie_activity_app

# Get dependencies
flutter pub get

# Run on iOS Simulator
flutter run -d ios

# Run on Android Emulator
flutter run -d android

# Run on Chrome (Web)
flutter run -d chrome
```

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v1/activity-types` | GET | Get predefined activity types |
| `/api/v1/activity/daily` | GET | Get daily activity summary |
| `/api/v1/activity/weekly` | GET | Get 7-day activity summaries |
| `/api/v1/activity/goal` | GET | Get adaptive goal for a day |
| `/api/v1/activity` | POST | Create manual activity entry |
| `/api/v1/ring/status` | GET | Get Lumie Ring status |
| `/api/v1/ring/detected` | GET | Get ring-detected activities |
| `/api/v1/walk-test/history` | GET | Get walk test history |
| `/api/v1/walk-test` | POST | Save walk test result |
| `/api/v1/walk-test/best` | GET | Get best walk test result |

## Privacy & Safety (Teen-Focused)

- ✅ No calorie burn tracking
- ✅ No MET values or performance ranking
- ✅ All comparisons are self-referenced only
- ✅ Manual entries clearly labeled as "Estimated"
- ✅ 6MWT results are informational, not diagnostic
- ✅ No public leaderboards

## Screenshots

The app features:
1. **Dashboard**: Activity ring, daily summary, adaptive goals
2. **History**: Week view with day-by-day breakdown
3. **Manual Entry**: Activity type selection, time picker, intensity
4. **6MWT**: Instructions, live timer, heart rate, results

## Tech Stack

### Frontend
- Flutter 3.x
- Dart 3.x
- Material Design 3

### Backend
- Python 3.11+
- FastAPI
- Pydantic v2
- Uvicorn

## License

Demo project for educational purposes.
