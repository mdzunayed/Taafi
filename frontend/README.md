# Medi-Treat Flutter App

A professional Flutter mobile application for post-surgery home care service platform based in Dhaka, Bangladesh.

## Overview

Medi-Treat is a multi-role healthcare platform connecting patients with qualified doctors and helpers for post-surgical home care. The app supports three user roles:

- **Patient**: Request care services, track doctor arrival, rate services
- **Doctor**: Accept assignments, manage active services, record vitals
- **Admin**: Oversee requests, assign care teams, monitor live services

## Quick Start

```bash
cd medi_treat
flutter pub get
flutter run
```

### Demo Credentials

| Role | Email | Password |
|------|-------|----------|
| Patient | patient@meditreat.app | password |
| Doctor | doctor@meditreat.app | password |
| Admin | admin@meditreat.app | password |

## Architecture

### State Management
- **Framework**: flutter_riverpod (functional reactive)
- **Pattern**: Providers with Notifiers

### Navigation
- **Router**: go_router (push-based with role guards)
- **Shell**: Single app shell with role-based routing

### API Integration
- **Client**: Dio + Interceptors
- **Auth**: JWT Bearer tokens with auto-refresh
- **Mock Mode**: Toggle-able for demo

## Project Structure

```
lib/
├── core/
│   ├── api/              # Dio HTTP client
│   ├── models/           # Data models
│   ├── router/           # GoRouter config
│   ├── theme/            # Design tokens & ThemeData
│   └── widgets/          # Shared UI components
├── features/
│   ├── auth/             # Login & token management
│   ├── patient/          # Patient app (5 screens)
│   ├── doctor/           # Doctor app (2 screens)
│   └── admin/            # Admin web (4 screens)
├── l10n/                 # i18n (EN + BN)
└── main.dart             # Entry point
```

## Design System

### Colors (6 Swappable Brands)
- **Default**: Clinical Teal (#0B8F87)
- Also: Sapphire, Violet, Emerald, Rose, Orange

### Typography
- **Font**: Inter + Kalpurush (Bangla)
- **Scale**: Display 48px → Labels 10px
- **Weights**: w400 (body) → w800 (display)

### Status States
- 🟠 Pending Review (Orange)
- 🔵 On The Way / Arrived (Teal)
- 🟢 In Service / Completed (Emerald)
- 🔴 Rejected (Rose)

## Features

### ✅ Implemented
- Design system with tokens
- Authentication flow
- Patient home screen
- Doctor dashboard
- Admin overview
- Role-based routing

### 🔜 Next (Stubs Ready)
- Patient request form & tracking
- Doctor active service with maps
- Admin queue & assignment
- Google Maps integration
- Real-time location updates
- Localization

## Building

```bash
# Debug APK
flutter build apk --debug

# Release APK
flutter build apk --release

# Analyze code
flutter analyze
```

## Configuration

1. **Google Maps API Key**: Update `android/app/src/main/AndroidManifest.xml`
2. **API Endpoint**: Update `lib/core/api/dio_client.dart` (_baseUrl)
3. **Bangla Fonts**: Already configured in pubspec.yaml

## Tech Stack

- **Framework**: Flutter 3.11+
- **State**: Riverpod 2.6.1
- **Router**: GoRouter 14.6.1
- **HTTP**: Dio 5.7.0
- **Maps**: google_maps_flutter 2.10.0
- **Storage**: SharedPreferences 2.3.3

## Contact

Built with 🩺 by the Medi-Treat engineering team
