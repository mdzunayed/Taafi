# Medi-Treat Flutter Build Guide

## System Requirements

- **Flutter**: 3.11+ (Check: `flutter --version`)
- **Dart**: 3.0+ (Included with Flutter)
- **Android SDK**: API 21+ (for APK build)
- **Java**: 11+ (Required by Gradle)

## Installation Steps

### 1. Get Dependencies

```bash
cd medi_treat
flutter clean                    # Clear previous builds
flutter pub get                  # Download dependencies
```

### 2. Configure Google Maps (Required)

Get your API key from [Google Cloud Console](https://console.cloud.google.com/):

1. Create new project or select existing
2. Enable "Maps SDK for Android"
3. Go to Credentials → Create API Key
4. Copy the key

Update `android/app/src/main/AndroidManifest.xml`:

```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="YOUR_API_KEY_HERE" />
```

### 3. Build Commands

#### Run in Debug Mode (Connected Device/Emulator Required)

```bash
flutter run
```

The app will:
- Start on login screen
- Show quick-access demo buttons for Patient/Doctor/Admin
- Navigate to role-specific dashboard on login

#### Build APK (Debug)

```bash
flutter build apk --debug
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`

#### Build APK (Release)

```bash
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

(Note: Sign the APK before distribution — see Android docs)

### 4. Verify Build

```bash
# Check for lint issues
flutter analyze

# Run tests (if added)
flutter test

# Check build files
ls -la build/app/outputs/flutter-apk/
```

## Troubleshooting

### Build Fails: "Target of URI doesn't exist"

**Cause**: Missing screen files or wrong imports

**Fix**:
```bash
flutter pub get
flutter clean
flutter pub get
```

### Google Maps Not Showing

**Cause**: API key missing or not enabled

**Fix**:
1. Verify API key in AndroidManifest.xml
2. Check "Maps SDK for Android" is enabled in Google Cloud
3. Ensure app has location permissions (handled in AndroidManifest)

### Permission Denied Errors

**Cause**: Missing write permissions or file locked

**Fix**:
```bash
sudo chown -R $USER:$USER .
flutter clean
flutter pub get
```

### Gradle Build Fails

**Cause**: Java version mismatch or SDK not found

**Fix**:
```bash
# Check Java version (needs 11+)
java -version

# Update Gradle wrapper
cd android
./gradlew wrapper --gradle-version 8.0
cd ..

# Then retry
flutter build apk
```

### APK Installation Fails on Device

**Cause**: APK signature mismatch or Android version incompatible

**Fix**:
```bash
# Uninstall first
adb uninstall com.meditreat.medi_treat

# Rebuild and reinstall
flutter run  # Automatic reinstall
```

## Firebase Integration (Optional)

For future push notifications and analytics:

1. Create Firebase project on [Firebase Console](https://console.firebase.google.com/)
2. Add Android app with package `com.meditreat.medi_treat`
3. Download `google-services.json` and place in `android/app/`
4. Add dependency: `firebase_core`, `firebase_messaging`

## CI/CD Setup (GitHub Actions)

Create `.github/workflows/build.yml`:

```yaml
name: Build APK
on: [push, pull_request]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.11.0'
      - run: flutter pub get
      - run: flutter build apk --debug
```

## Performance Tips

1. **Use `--split-per-abi`** for smaller APKs:
   ```bash
   flutter build apk --release --split-per-abi
   ```

2. **Enable Proguard** in `android/app/build.gradle.kts`:
   ```kotlin
   buildTypes {
       release {
           minifyEnabled true
           shrinkResources true
       }
   }
   ```

3. **Check APK size**:
   ```bash
   flutter build apk --analyze-size
   ```

## Next Steps

1. ✅ Build successful APK
2. Install on Android device
3. Test all role flows (Patient → Doctor → Admin)
4. Complete remaining screens (tracking, maps, etc.)
5. Add localization strings
6. Set up CI/CD pipeline
7. Deploy to Play Store

---

**Questions?** Check flutter.dev/docs or file an issue
