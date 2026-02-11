# Lumie Activity App

A health activity tracking app for teens (13-21) with chronic health conditions. Built with Flutter frontend and Python FastAPI backend.

## Features

- User authentication (Teen/Parent accounts)
- Activity tracking with adaptive goals
- 6-Minute Walk Test
- Ring device integration
- Privacy-focused design (no calorie tracking, no rankings)
- Lemon yellow theme with gradients

## Tech Stack

### Frontend
- **Framework:** Flutter 3.x
- **State Management:** Provider
- **Local Storage:** shared_preferences
- **HTTP Client:** http package

### Backend
- **Framework:** FastAPI 0.109.0
- **Database:** MongoDB 8.0 (via Motor async driver)
- **Authentication:** JWT (python-jose) + bcrypt
- **Python:** 3.12+

## Project Structure

### Flutter (Frontend)
```
lib/
├── core/
│   ├── constants/
│   │   └── api_constants.dart    # API base URL & endpoints
│   ├── services/
│   │   ├── auth_service.dart     # Auth state & API calls
│   │   └── profile_service.dart  # Profile API calls
│   ├── theme/
│   │   ├── app_colors.dart       # Color palette (lemon yellow)
│   │   └── app_theme.dart        # Material theme
│   └── utils/
│       └── api_service.dart      # Activity API calls
├── features/
│   ├── auth/
│   │   ├── providers/
│   │   │   └── auth_provider.dart    # Auth state (ChangeNotifier)
│   │   ├── screens/
│   │   │   ├── welcome_screen.dart
│   │   │   ├── login_screen.dart
│   │   │   ├── signup_screen.dart
│   │   │   ├── account_type_screen.dart
│   │   │   ├── teen_profile_setup_screen.dart
│   │   │   └── parent_profile_setup_screen.dart
│   │   └── widgets/
│   │       ├── auth_text_field.dart
│   │       ├── unit_selector.dart
│   │       └── icd10_search_field.dart
│   ├── dashboard/
│   │   └── screens/dashboard_screen.dart
│   ├── activity/
│   │   └── screens/activity_history_screen.dart
│   ├── manual_entry/
│   │   └── screens/manual_entry_screen.dart
│   └── walk_test/
│       └── screens/walk_test_screen.dart
├── shared/
│   ├── models/
│   │   ├── user_models.dart      # User/Profile models
│   │   └── activity_models.dart  # Activity models
│   └── widgets/
│       └── gradient_card.dart
└── main.dart                     # App entry with AuthWrapper
```

### Backend (Python)
```
lumie_backend/
├── app/
│   ├── api/
│   │   ├── auth_routes.py      # Auth endpoints
│   │   ├── profile_routes.py   # Profile & ICD-10 endpoints
│   │   └── routes.py           # Activity endpoints
│   ├── core/
│   │   ├── config.py           # Settings (env vars)
│   │   ├── database.py         # MongoDB connection
│   │   └── security.py         # Password hashing & JWT
│   ├── models/
│   │   ├── user.py             # User/Profile Pydantic models
│   │   └── activity.py         # Activity models
│   ├── services/
│   │   ├── auth_service.py     # Auth business logic
│   │   ├── profile_service.py  # Profile CRUD
│   │   └── icd10_service.py    # ICD-10 code search
│   └── main.py                 # FastAPI app entry
├── requirements.txt
└── run.py
```

## Auth Flow

```
App Start
    ↓
AuthWrapper (checks auth state)
    ↓
┌─────────────────────────────────────────┐
│ unauthenticated → WelcomeScreen         │
│ needsAccountType → AccountTypeScreen    │
│ needsProfile → TeenProfile/ParentProfile│
│ authenticated → MainNavigationScreen    │
└─────────────────────────────────────────┘
```

## API Endpoints

### Authentication (`/api/v1/auth`)
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/signup` | Register new user |
| POST | `/login` | Login, returns JWT |
| POST | `/account-type` | Set teen/parent role |
| GET | `/me` | Get current user info |

### Profile (`/api/v1/profile`)
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/teen` | Create teen profile |
| POST | `/parent` | Create parent profile |
| GET | `/` | Get user profile |
| PUT | `/` | Update profile |
| DELETE | `/` | Delete profile |
| GET | `/icd10/search?query=` | Search ICD-10 codes |
| GET | `/icd10/categories` | Get ICD-10 categories |

### Activity (`/api/v1`)
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/activity-types` | Get activity types |
| GET | `/activity/daily` | Daily summary |
| GET | `/activity/weekly` | Weekly summaries |
| GET | `/activity/goal` | Adaptive goal |
| POST | `/activity` | Create activity |
| GET | `/ring/status` | Ring status |
| GET | `/walk-test/history` | Walk test history |
| POST | `/walk-test` | Save walk test |

## Getting Started

### Prerequisites
- Flutter SDK 3.x
- Python 3.12+
- MongoDB 8.0+

### Run Flutter App
```bash
cd lumie_activity_app
flutter pub get
flutter run
```

### Run Backend Locally
```bash
cd lumie_backend
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
python run.py
# API available at http://localhost:8000
# Docs at http://localhost:8000/docs
```

### Backend Environment Variables
Create `.env` file in `lumie_backend/`:
```env
MONGODB_URL=mongodb://localhost:27017
MONGODB_DB_NAME=lumie_db
SECRET_KEY=<random-hex-string>
ACCESS_TOKEN_EXPIRE_MINUTES=10080
```

## AWS Deployment

### Server Details
- **IP:** 54.193.153.37
- **SSH:** `ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37`

### Services
| Service | Port | Status Command |
|---------|------|----------------|
| MongoDB | 27017 | `sudo systemctl status mongod` |
| Lumie Backend | 8000 | `sudo systemctl status lumie-api` |

### Useful Commands
```bash
# View backend logs
sudo journalctl -u lumie-api -f

# Restart backend
sudo systemctl restart lumie-api

# Deploy new code
scp -i ~/.ssh/Lumie_Key.pem -r lumie_backend/* ubuntu@54.193.153.37:~/lumie_backend/
ssh -i ~/.ssh/Lumie_Key.pem ubuntu@54.193.153.37 "sudo systemctl restart lumie-api"
```

### API Configuration
Edit `lib/core/constants/api_constants.dart`:
```dart
// For local development
static const String baseUrl = 'http://localhost:8000/api/v1';

// For production
static const String baseUrl = 'https://yumo.org/api/v1';
```

## Theme Colors

Main theme: **Lemon Yellow** with gradients

```dart
primaryLemon: Color(0xFFFFF59D)
primaryLemonLight: Color(0xFFFFFDE7)
primaryLemonDark: Color(0xFFFFEB3B)
textPrimary: Color(0xFF424242)
textOnYellow: Color(0xFF5D4037)
```

## Database Collections (MongoDB)

| Collection | Description |
|------------|-------------|
| `users` | User accounts (email, hashed_password, role) |
| `profiles` | User profiles (name, age, height, weight, icd10) |

## Privacy & Safety (Teen-First Design)

- No calorie burn tracking
- No MET values or performance ranking
- All comparisons are self-referenced only
- Teen-safe intensity categories (Low, Moderate, High)
- ICD-10 codes never displayed publicly
- No social comparison or leaderboards
