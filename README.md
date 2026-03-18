# EduSys

EduSys is a role-based attendance system built with Flutter for Android and FastAPI for the backend.

## Stack

- Mobile: Flutter, Provider, HTTP, Secure Storage, Geolocator, Google Sign-In
- Backend: FastAPI, SQLAlchemy, Alembic, PostgreSQL, JWT
- Deployment: Railway for the backend, GitHub Releases for the APK

## Local Development

### Backend

1. Copy `backend/.env.example` to `backend/.env`.
2. Update the values for your local database and email provider.
3. Start the stack:

```powershell
docker compose up -d --build
```

4. Verify the API:

```powershell
Invoke-WebRequest http://127.0.0.1:8000/health -UseBasicParsing
```

### Mobile

```powershell
cd mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000 --dart-define=GOOGLE_WEB_CLIENT_ID=<WEB_CLIENT_ID>
```

## Railway Backend Deployment

This repo is now set up so Railway can deploy the backend directly from the repository root:

- The root `Dockerfile` builds the backend from `backend/`.
- The backend Docker command now listens on Railway's `PORT` environment variable in `backend/Dockerfile`.
- The health endpoint is already available at `/health`.

### Railway setup

1. Create a new Railway project.
2. Add a PostgreSQL service.
3. Add a GitHub repo service pointing to this repository.
4. In the backend service, set these variables:

```env
DATABASE_URL=<Railway PostgreSQL connection string>
SECRET_KEY=<long random secret>
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=1440
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=<your email>
SMTP_PASSWORD=<your app password>
SMTP_SENDER_EMAIL=<your email>
SMTP_USE_TLS=true
DEV_SHOW_OTP_IN_RESPONSE=false
DEVICE_BINDING_ENABLED=true
```

5. In Railway service settings, set the healthcheck path to `/health`.
6. Deploy the service.

After deploy, your backend URL will look similar to:

```text
https://your-backend-name.up.railway.app
```

## Android Release Signing

Local release builds still work without a real keystore, but production releases can now use a proper upload key.

Files added for signing:

- `mobile/android/key.properties.example`
- `mobile/android/app/build.gradle.kts`

To configure a local signed release:

1. Create `mobile/android/upload-keystore.jks`
2. Copy `mobile/android/key.properties.example` to `mobile/android/key.properties`
3. Fill in your real keystore values

## GitHub APK Release Workflow

This repo now includes `.github/workflows/release-apk.yml`, which:

- builds a signed Android APK
- creates or updates a GitHub Release
- uploads a stable asset named `EduSys.apk`

### Required GitHub repository secrets

Add these in GitHub at `Settings -> Secrets and variables -> Actions`:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
- `PROD_API_BASE_URL`
- `GOOGLE_WEB_CLIENT_ID` (optional if Google login is not used in production)

### How to publish

Push a version tag:

```powershell
git tag v1.0.0
git push origin v1.0.0
```

The workflow will build the APK and publish it to the GitHub Release for that tag.

## Direct APK Download Link

Because every release uploads the APK with the same asset name, you can share a stable direct-download URL:

```text
https://github.com/<owner>/<repo>/releases/latest/download/EduSys.apk
```

Replace `<owner>` and `<repo>` with your GitHub account and repository name.

## Notes

- Production Android builds now block cleartext traffic by default, while debug and profile builds still allow local HTTP development.
- The mobile production API URL should be passed during release builds with `--dart-define=API_BASE_URL=...`.
- Railway and GitHub still need to be configured in their dashboards; this repo now contains the code and workflow support for that setup.
