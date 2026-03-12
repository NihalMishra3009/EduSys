# EduSys Mobile Attendance

EduSys is a role-based attendance system built with Flutter (Android), FastAPI, and PostgreSQL.

## Tech Stack
- Mobile: Flutter, Provider, `http`, `flutter_secure_storage`, `geolocator`, `device_info_plus`, `telephony`
- Backend: FastAPI, SQLAlchemy, Alembic, PostgreSQL, JWT (`python-jose`)
- Infra: Docker Compose (`api`, `postgres`)

## Roles
- `ADMIN`
- `PROFESSOR`
- `STUDENT`

## Core Features
- JWT auth with secure token storage
- Device + SIM binding
- Registration OTP (email-based)
- Google sign-in
- Rectangular geofencing (bounds normalization + GPS tolerance handling)
- Lecture start/end
- Attendance checkpoints + 75% attendance evaluation
- Admin logs and overrides

## Project Structure
```text
edusys/
├── backend/
│   ├── app/
│   ├── alembic/
│   ├── Dockerfile
│   └── requirements.txt
├── mobile/
│   ├── lib/
│   └── pubspec.yaml
├── docker-compose.yml
└── README.md
```

## Backend Setup
1. Create `backend/.env` (required for SMTP OTP):
```env
DATABASE_URL=postgresql+psycopg2://postgres:postgres@postgres:5432/edusys
SECRET_KEY=change_me_to_a_long_random_secret
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=1440

SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=your_email@gmail.com
SMTP_PASSWORD=your_16_char_gmail_app_password
SMTP_SENDER_EMAIL=your_email@gmail.com
SMTP_USE_TLS=true
DEV_SHOW_OTP_IN_RESPONSE=false
```
2. Start services:
```powershell
Copy-Item backend/.env.example backend/.env -ErrorAction SilentlyContinue
docker compose up -d --build
```
3. Verify API:
```powershell
Invoke-WebRequest http://127.0.0.1:8000/health -UseBasicParsing
```

## Mobile Run (Physical Android)
```powershell
cd mobile
flutter pub get
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb reverse tcp:8000 tcp:8000
flutter run -d <DEVICE_ID> --dart-define=API_BASE_URL=http://127.0.0.1:8000 --dart-define=GOOGLE_WEB_CLIENT_ID=<WEB_CLIENT_ID>
```

## Mobile Run (Android Emulator)
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run-mobile-emulator.ps1 -AvdName Pixel_6a -GoogleWebClientId <WEB_CLIENT_ID>
```

## OTP Workflow
1. User registers
2. Backend sends OTP email via Gmail SMTP
3. User verifies OTP on OTP screen
4. User can use `Resend OTP` (cooldown enabled)

## Geofencing Workflow (Rectangle)
1. Student sends checkpoint (`lat`, `lon`, optional `gps_accuracy_m`)
2. Backend normalizes classroom bounds
3. Backend validates coordinate ranges
4. Backend checks inside rectangle with GPS jitter tolerance
5. Outside rectangle checkpoints are rejected

## Key API Endpoints
- Auth: `/auth/register`, `/auth/verify-otp`, `/auth/resend-otp`, `/auth/login`, `/auth/google-login`
- Lecture: `/lecture/start`, `/lecture/end`, `/lecture/active`, `/lecture/history`
- Attendance: `/attendance/checkpoint`, `/attendance/history`, `/attendance/my-records`
- Admin: `/admin/create-user`, `/admin/reset-device`, `/admin/reset-sim`, `/admin/create-classroom`, `/admin/update-boundary/{classroom_id}`, `/admin/logs`

## Build Release APK
```powershell
cd mobile
flutter build apk --release --dart-define=API_BASE_URL=http://127.0.0.1:8000 --dart-define=GOOGLE_WEB_CLIENT_ID=<WEB_CLIENT_ID>
```

Output:
- `mobile/build/app/outputs/flutter-apk/app-release.apk`
