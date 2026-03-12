# EduSys Project Structure

This document describes the organization and structure of the EduSys codebase.

## Overview

EduSys is a role-based attendance management system with:
- **Backend**: FastAPI (Python) with PostgreSQL
- **Mobile**: Flutter (Dart) for Android

## Directory Structure

```
edusys/
├── backend/                 # FastAPI backend application
│   ├── app/
│   │   ├── core/           # Core application configuration
│   │   │   ├── config.py   # Settings and environment variables
│   │   │   ├── database.py # Database connection and session management
│   │   │   ├── deps.py     # Dependency injection (auth, DB sessions)
│   │   │   └── security.py # Security utilities (JWT, password hashing)
│   │   ├── models/         # SQLAlchemy database models
│   │   │   ├── base.py     # Base model class
│   │   │   ├── user.py     # User model
│   │   │   ├── classroom.py
│   │   │   ├── lecture.py
│   │   │   ├── attendance_record.py
│   │   │   ├── attendance_checkpoint.py
│   │   │   ├── audit_log.py
│   │   │   ├── department.py
│   │   │   ├── notification.py
│   │   │   └── complaint.py
│   │   ├── routers/        # API route handlers
│   │   │   ├── auth.py     # Authentication endpoints
│   │   │   ├── users.py    # User management
│   │   │   ├── admin.py    # Admin operations
│   │   │   ├── classroom.py
│   │   │   ├── lecture.py
│   │   │   ├── attendance.py
│   │   │   ├── audit.py
│   │   │   ├── geo.py      # Geofencing endpoints
│   │   │   ├── department.py
│   │   │   ├── notification.py
│   │   │   ├── complaint.py
│   │   │   └── resources.py
│   │   ├── schemas/        # Pydantic request/response models
│   │   │   ├── auth.py
│   │   │   ├── user.py
│   │   │   ├── classroom.py
│   │   │   ├── lecture.py
│   │   │   ├── attendance.py
│   │   │   ├── audit.py
│   │   │   ├── admin.py
│   │   │   ├── department.py
│   │   │   ├── notification.py
│   │   │   ├── complaint.py
│   │   │   ├── geo.py
│   │   │   └── resource.py
│   │   ├── services/       # Business logic services
│   │   │   ├── email_service.py      # Email sending (OTP)
│   │   │   ├── google_auth_service.py # Google OAuth verification
│   │   │   └── audit_service.py      # Audit logging
│   │   ├── utils/          # Utility functions
│   │   │   └── geo.py      # Geofencing calculations
│   │   ├── main.py         # FastAPI application entry point
│   │   └── __init__.py
│   ├── alembic/            # Database migrations
│   │   ├── versions/       # Migration files
│   │   └── env.py
│   ├── alembic.ini         # Alembic configuration
│   ├── Dockerfile
│   └── requirements.txt
│
├── mobile/                 # Flutter mobile application
│   ├── lib/
│   │   ├── main.dart       # Application entry point
│   │   ├── app_entry.dart  # App initialization and routing logic
│   │   │
│   │   ├── config/         # Configuration files
│   │   │   ├── api_config.dart
│   │   │   ├── api_config_dev.dart
│   │   │   └── api_config_prod.dart
│   │   │
│   │   ├── core/           # Core application code
│   │   │   ├── animations/ # Animation definitions
│   │   │   │   └── app_transitions.dart
│   │   │   ├── constants/  # App-wide constants
│   │   │   │   ├── app_colors.dart
│   │   │   │   └── app_strings.dart
│   │   │   ├── theme/      # Theme configuration
│   │   │   │   └── app_theme.dart
│   │   │   └── utils/      # Utility functions
│   │   │       ├── app_navigator.dart
│   │   │       ├── network_guard.dart
│   │   │       ├── session_guard.dart
│   │   │       └── validators.dart
│   │   │
│   │   ├── features/       # Feature-based organization
│   │   │   ├── auth/       # Authentication screens
│   │   │   │   ├── login_screen.dart
│   │   │   │   ├── register_screen.dart
│   │   │   │   └── otp_verify_screen.dart
│   │   │   ├── common/     # Common/shared screens
│   │   │   │   ├── splash_screen.dart
│   │   │   │   ├── device_locked_screen.dart
│   │   │   │   └── permission_denied_screen.dart
│   │   │   ├── student/    # Student-specific features
│   │   │   │   ├── dashboard/
│   │   │   │   │   ├── student_home_screen.dart
│   │   │   │   │   └── app_shell_screen.dart
│   │   │   │   ├── attendance/
│   │   │   │   │   ├── active_lecture_screen.dart
│   │   │   │   │   └── attendance_history_screen.dart
│   │   │   │   ├── complaint/
│   │   │   │   │   └── complaint_screen.dart
│   │   │   │   └── profile/
│   │   │   │       └── profile_screen.dart
│   │   │   ├── professor/  # Professor-specific features
│   │   │   │   ├── dashboard/
│   │   │   │   │   └── professor_home_screen.dart
│   │   │   │   └── lectures/
│   │   │   │       └── start_lecture_screen.dart
│   │   │   └── admin/      # Admin-specific features
│   │   │       ├── dashboard/
│   │   │       │   └── admin_dashboard_screen.dart
│   │   │       ├── classrooms/
│   │   │       │   └── manage_classrooms_screen.dart
│   │   │       └── users/
│   │   │           └── manage_users_screen.dart
│   │   │
│   │   ├── providers/      # State management (Provider pattern)
│   │   │   ├── auth_provider.dart
│   │   │   ├── lecture_provider.dart
│   │   │   └── theme_provider.dart
│   │   │
│   │   └── shared/         # Shared code across features
│   │       ├── models/     # Data models
│   │       │   ├── user_model.dart
│   │       │   ├── lecture_model.dart
│   │       │   └── attendance_model.dart
│   │       ├── services/   # API and business logic services
│   │       │   ├── api_service.dart
│   │       │   ├── auth_service.dart
│   │       │   ├── attendance_service.dart
│   │       │   ├── geo_service.dart
│   │       │   ├── location_service.dart
│   │       │   └── device_binding_service.dart
│   │       └── widgets/    # Reusable widgets
│   │           ├── app_button.dart
│   │           ├── app_card.dart
│   │           ├── custom_button.dart
│   │           ├── empty_state_widget.dart
│   │           ├── error_snackbar.dart
│   │           ├── info_card.dart
│   │           ├── loading_skeleton.dart
│   │           ├── no_connection_screen.dart
│   │           ├── percentage_ring.dart
│   │           ├── primary_button.dart
│   │           ├── section_title.dart
│   │           └── status_badge.dart
│   │
│   ├── test/               # Unit and widget tests
│   ├── pubspec.yaml        # Flutter dependencies
│   └── README.md
│
├── docker-compose.yml      # Docker services configuration
└── README.md              # Main project documentation
```

## Architecture Principles

### Backend (FastAPI)

1. **Separation of Concerns**:
   - `models/`: Database models (SQLAlchemy ORM)
   - `schemas/`: Request/response validation (Pydantic)
   - `routers/`: API endpoints (FastAPI routes)
   - `services/`: Business logic (reusable across routers)
   - `core/`: Application configuration and dependencies

2. **Dependency Injection**:
   - Database sessions via `get_db()` dependency
   - Current user authentication via `get_current_user()` dependency
   - All dependencies defined in `app/core/deps.py`

3. **Database Migrations**:
   - Managed with Alembic
   - Migration files in `alembic/versions/`
   - Sequential naming: `0001_init.py`, `0002_*.py`, etc.

### Mobile (Flutter)

1. **Feature-Based Organization**:
   - Features grouped by user role (student, professor, admin)
   - Each feature contains its screens and related logic
   - Common screens in `features/common/`

2. **State Management**:
   - Provider pattern for state management
   - Providers in `providers/` directory
   - Shared state accessible across features

3. **Shared Resources**:
   - Reusable widgets in `shared/widgets/`
   - API services in `shared/services/`
   - Data models in `shared/models/`
   - Core utilities in `core/utils/`

4. **Configuration**:
   - Environment-specific configs in `config/`
   - API endpoints and environment variables
   - Dev/Prod configurations separated

## Key Files

### Backend
- `backend/app/main.py`: FastAPI app initialization and route registration
- `backend/app/core/config.py`: Application settings from environment
- `backend/app/core/database.py`: Database connection setup
- `backend/app/core/security.py`: JWT and password utilities

### Mobile
- `mobile/lib/main.dart`: Flutter app entry point
- `mobile/lib/app_entry.dart`: App initialization and routing logic
- `mobile/lib/config/api_config.dart`: API configuration
- `mobile/lib/shared/services/api_service.dart`: Base API client

## Naming Conventions

### Backend
- **Models**: Singular nouns (e.g., `User`, `Lecture`)
- **Routers**: Plural nouns matching endpoints (e.g., `users.py` for `/users`)
- **Schemas**: Descriptive names (e.g., `UserOut`, `RegisterRequest`)
- **Services**: `*_service.py` suffix

### Mobile
- **Screens**: `*_screen.dart` suffix
- **Widgets**: Descriptive names (e.g., `app_button.dart`)
- **Services**: `*_service.dart` suffix
- **Models**: `*_model.dart` suffix
- **Providers**: `*_provider.dart` suffix

## Adding New Features

### Backend
1. Create model in `app/models/`
2. Create schemas in `app/schemas/`
3. Create router in `app/routers/`
4. Add business logic to `app/services/` if needed
5. Register router in `app/main.py`
6. Create migration if model changes

### Mobile
1. Create feature folder in `lib/features/`
2. Add screens in feature folder
3. Create/update models in `lib/shared/models/`
4. Create/update services in `lib/shared/services/`
5. Create provider if state management needed
6. Add navigation routes in `app_entry.dart` or feature router

## Best Practices

1. **Keep features modular**: Each feature should be self-contained
2. **Reuse shared code**: Use `shared/` for common functionality
3. **Follow naming conventions**: Consistent naming makes code easier to navigate
4. **Document complex logic**: Add comments for business rules
5. **Separate concerns**: Keep UI, business logic, and data access separate
