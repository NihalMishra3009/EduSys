# EduSys Mobile Attendance App

Flutter mobile app + FastAPI backend + PostgreSQL for:
- JWT login
- Device binding
- SIM binding
- Rectangular GPS geofence attendance
- Lecture start/end and 75% presence evaluation

## Scope

Included:
- Attendance
- Geo validation (rectangle)
- Device/SIM security

Not included:
- LMS
- Google Meet / Zoom
- File uploads
- Face/biometric/QR attendance
- Continuous tracking
- iOS/Web frontend

## Tech Stack

- Mobile: Flutter, Dart, Provider, `http`, `flutter_secure_storage`, `geolocator`, `device_info_plus`, `telephony`
- Backend: FastAPI, SQLAlchemy, Alembic, PostgreSQL, JWT (`python-jose`)
- Infra: Docker, Docker Compose

## Project Structure

```text
edusys/
├── backend/
│   ├── app/
│   │   ├── main.py
│   │   ├── core/
│   │   ├── models/
│   │   ├── routers/
│   │   ├── schemas/
│   │   ├── services/
│   │   └── utils/
│   ├── alembic/
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── alembic.ini
│   └── .env.example
├── mobile/
│   ├── lib/
│   ├── android/
│   └── pubspec.yaml
├── docker-compose.yml
└── README.md
```

## Prerequisites (Windows)

- Docker Desktop running
- Android phone with USB debugging enabled
- Android SDK installed
- Flutter SDK available in PATH

If Flutter is not in PATH:

```powershell
$env:Path = "C:\Users\nihal\tools\flutter\bin;$env:Path"
flutter --version
```

## Quick Start (Recommended)

### 1. Start backend

From project root:

```powershell
Copy-Item backend/.env.example backend/.env -ErrorAction SilentlyContinue
docker-compose up -d --build
```

Check backend:

```powershell
Invoke-WebRequest http://localhost:8000/health
```

API docs:
- `http://localhost:8000/docs`

### 2. Prepare Flutter app

```powershell
cd mobile
flutter create .
flutter pub get
```

### 3. Confirm phone is connected

```powershell
adb devices -l
flutter devices
```

### 4. Find your laptop IP (same Wi-Fi as phone)

```powershell
ipconfig
```

Use active adapter IPv4, example: `192.168.31.206`

### 5. Run app on connected phone

```powershell
cd mobile
flutter run -d 62cd2ac2 --dart-define=API_BASE_URL=http://192.168.31.206:8000
```

If your device ID changes, replace `62cd2ac2` with your current one from `flutter devices`.

## Build Release APK

```powershell
cd mobile
flutter build apk --release --dart-define=API_BASE_URL=http://192.168.31.206:8000
```

APK output:
- `mobile/build/app/outputs/flutter-apk/app-release.apk`

## Required Android Permissions

Defined in `mobile/android/app/src/main/AndroidManifest.xml`:
- `INTERNET`
- `ACCESS_FINE_LOCATION`
- `READ_PHONE_STATE`

## Main Backend Endpoints

Auth:
- `POST /auth/register`
- `POST /auth/login`
- `GET /auth/me`
- `POST /auth/reset-binding/{user_id}` (ADMIN)

Classroom:
- `POST /classroom` (ADMIN)

Lecture:
- `POST /lecture/start` (PROFESSOR)
- `GET /lecture/active`
- `POST /lecture/end` (PROFESSOR owner)

Attendance:
- `POST /attendance/checkpoint` (STUDENT, inside rectangle only)
- `GET /attendance/history`

## Attendance Rule

At lecture end:
- Lecture duration = `end_time - start_time`
- Threshold = `75%` of lecture duration
- Presence duration = `last_checkpoint - first_checkpoint`
- If presence duration >= threshold: `PRESENT`, else `ABSENT`

## Troubleshooting

- Backend not reachable on phone:
  - Ensure phone and laptop are on same Wi-Fi
  - Allow Windows Firewall inbound port `8000`
  - Verify API URL uses laptop IPv4, not `localhost`

- `flutter` not found:
  - Add Flutter `bin` to PATH for current terminal session

- Device not detected:
  - Reconnect USB
  - Accept USB debugging prompt on phone
  - Run `adb kill-server` then `adb start-server`
