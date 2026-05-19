# I Am Rich — Setup & Testing Guide

> **Flutter version used:** 3.41.9  
> **Flutter SDK location:** `/opt/homebrew/share/flutter/bin/flutter`  
> **Project root:** `/Users/rajat/Desktop/AI Learn/mobile app/i_am_rich/`

Add Flutter to your terminal PATH once so every command below works:

```bash
export PATH="/opt/homebrew/share/flutter/bin:$PATH"
```

To make it permanent, add the line above to your `~/.zshrc` and run `source ~/.zshrc`.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Run on Android Physical Device (no developer account needed)](#2-run-on-android-physical-device)
3. [Run on Android Emulator](#3-run-on-android-emulator)
4. [Run on iOS Simulator](#4-run-on-ios-simulator)
5. [Useful Flutter Commands](#5-useful-flutter-commands)
6. [Troubleshooting](#6-troubleshooting)

---

## 1. Prerequisites

### Check your Flutter setup

```bash
flutter doctor -v
```

Go through each item in the output and fix anything marked with ✗ before proceeding.

### Java (required for Android builds)

```bash
java -version
```

If not installed:

```bash
brew install --cask temurin   # OpenJDK — free, no account needed
```

---

## 2. Run on Android Physical Device

> **No Google Play developer account is required.**  
> You only need to enable USB Debugging on the phone — this is a built-in Android feature available on every Android device.

### Step 1 — Enable Developer Options on your Android phone

1. Open **Settings** on your Android phone.
2. Scroll down and tap **About phone** (on some phones it's inside **General Management**).
3. Find **Build number** and tap it **7 times in a row**.
4. You will see a toast: *"You are now a developer!"*
5. Go back to **Settings** → you will now see **Developer Options** (sometimes inside **System** or **Additional Settings** depending on the phone brand).

> **Brand-specific paths:**
> | Brand | Path to Build Number |
> |-------|----------------------|
> | Samsung | Settings → About phone → Software information → Build number |
> | OnePlus | Settings → About device → Build number |
> | Xiaomi/MIUI | Settings → About phone → MIUI version |
> | Pixel / Stock Android | Settings → About phone → Build number |

### Step 2 — Enable USB Debugging

1. Open **Settings → Developer Options**.
2. Toggle **Developer Options** ON (the master switch at the top).
3. Scroll down and enable **USB Debugging**.
4. A dialog will appear — tap **OK**.

### Step 3 — Connect phone to Mac via USB

1. Use a USB cable (make sure it supports data transfer, not charge-only).
2. Unlock your phone screen.
3. A dialog will appear on your phone: **"Allow USB debugging?"** — tap **Allow** (check "Always allow from this computer" to avoid the prompt next time).

### Step 4 — Verify Flutter sees the device

```bash
flutter devices
```

You should see your phone listed, e.g.:

```
SM-G991B (mobile) • R5CW31XXXXX • android-arm64 • Android 13 (API 33)
```

If the device does not appear, try:
- A different USB cable
- A different USB port on your Mac
- Run `adb devices` — if it shows `unauthorized`, re-check the phone for the allow dialog

### Step 5 — Run the app

Navigate to the project folder and run:

```bash
cd "/Users/rajat/Desktop/AI Learn/mobile app/i_am_rich"
flutter run
```

Flutter will compile the app and install it directly onto your phone. The first build takes 2–4 minutes; subsequent builds are much faster.

Once running, you get **hot reload** — press `r` in the terminal to apply code changes instantly, or `R` for a full restart.

---

### Wireless Debugging (Android 11 and above — no USB after pairing)

Once you have connected via USB at least once, you can switch to Wi-Fi debugging.

#### One-time pairing

1. On your phone: **Settings → Developer Options → Wireless debugging** → toggle ON.
2. Tap **Pair device with pairing code** — note the **IP address:port** and **pairing code** shown on screen.
3. On your Mac:

```bash
adb pair <IP>:<pairing-port>
# Enter the 6-digit pairing code when prompted
```

#### Connect wirelessly

1. On your phone: **Settings → Developer Options → Wireless debugging** — note the **IP address:port** shown at the top (different from the pairing port).
2. On your Mac:

```bash
adb connect <IP>:<port>
flutter devices   # your phone should now appear
flutter run
```

---

## 3. Run on Android Emulator

### Step 1 — Install Android Studio

Download from: **https://developer.android.com/studio**

Install it to `/Applications` and open it once to complete the first-run setup (it downloads the Android SDK automatically).

### Step 2 — Install command-line tools via Android Studio

1. Open **Android Studio → Settings (⌘,) → Languages & Frameworks → Android SDK**.
2. Under **SDK Tools** tab, check:
   - **Android SDK Command-line Tools (latest)**
   - **Android Emulator**
   - **Android SDK Platform-Tools**
3. Click **Apply** and let it download.

### Step 3 — Create a Virtual Device (AVD)

1. In Android Studio, open **Device Manager** (right sidebar or **View → Tool Windows → Device Manager**).
2. Click **+** → **Create Virtual Device**.
3. Choose a device profile, e.g., **Pixel 8** → click **Next**.
4. Select a system image (e.g., **API 34, Android 14, arm64**) — click **Download** next to it if not already downloaded → **Next**.
5. Name the AVD and click **Finish**.

### Step 4 — Start the emulator

Either click the ▶ play button next to your AVD in Device Manager, or from the terminal:

```bash
# List available emulators
emulator -list-avds

# Start one (replace Pixel_8_API_34 with your AVD name)
emulator -avd Pixel_8_API_34 &
```

Wait for the emulator to fully boot to the home screen.

### Step 5 — Run the app

```bash
cd "/Users/rajat/Desktop/AI Learn/mobile app/i_am_rich"
flutter run
```

Flutter auto-detects the running emulator. If multiple devices are connected, choose one:

```bash
flutter run -d emulator-5554
```

---

## 4. Run on iOS Simulator

> **No Apple Developer account needed** for the iOS Simulator.  
> The Simulator runs entirely on your Mac — no real device, no signing required.

### Step 1 — Install Xcode

1. Open the **Mac App Store** and search for **Xcode**.
2. Install it (it is large — ~15 GB).
3. After installation, open Xcode once and accept the license agreement.
4. Install additional components when prompted.

Or via terminal (accepts license non-interactively):

```bash
sudo xcodebuild -license accept
sudo xcode-select --install
```

### Step 2 — Install Xcode command-line tools

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

### Step 3 — Install CocoaPods (iOS dependency manager)

```bash
sudo gem install cocoapods
```

Or with Homebrew:

```bash
brew install cocoapods
```

### Step 4 — Install iOS pods for the project

```bash
cd "/Users/rajat/Desktop/AI Learn/mobile app/i_am_rich/ios"
pod install
```

This sets up the native iOS dependencies for `confetti` and `audioplayers`.

### Step 5 — Open the iOS Simulator

Option A — from terminal:

```bash
open -a Simulator
```

Option B — from Xcode:

1. Open Xcode → **Xcode menu → Open Developer Tool → Simulator**.

### Step 6 — Choose the simulated device

In the Simulator app: **File → Open Simulator → iOS XX → iPhone 15** (or any device you like).

Or list and boot from terminal:

```bash
# List all available simulators
xcrun simctl list devices available

# Boot a specific one (copy the UUID from the list above)
xcrun simctl boot "iPhone 15"
```

### Step 7 — Run the app

```bash
cd "/Users/rajat/Desktop/AI Learn/mobile app/i_am_rich"
flutter run -d ios
```

Flutter will compile, sign with a local development certificate automatically, and launch the app inside the Simulator.

---

## 5. Useful Flutter Commands

| Command | What it does |
|---------|-------------|
| `flutter devices` | List all connected devices and emulators |
| `flutter run` | Build and run on the first available device |
| `flutter run -d <device-id>` | Run on a specific device |
| `flutter run --release` | Build release (optimised, no debug overhead) |
| `flutter build apk` | Build a standalone `.apk` for Android |
| `flutter build apk --release` | Build a release `.apk` |
| `flutter build ios --simulator` | Build for iOS Simulator only |
| `flutter pub get` | Fetch/update Dart dependencies |
| `flutter clean` | Delete build cache (fixes most weird build errors) |
| `flutter doctor` | Check Flutter environment health |
| `flutter analyze` | Run static analysis on your Dart code |
| `flutter logs` | Stream device logs to terminal |

### Hot reload vs hot restart (while `flutter run` is active)

| Key | Action |
|-----|--------|
| `r` | Hot reload — applies UI changes in < 1 second, preserves state |
| `R` | Hot restart — full restart, clears state |
| `q` | Quit |
| `d` | Detach (leaves app running on device) |
| `h` | Print full help |

---

## 6. Troubleshooting

### `flutter doctor` shows Android SDK missing

Set the Android SDK path:

```bash
flutter config --android-sdk ~/Library/Android/sdk
```

### `adb: command not found`

Add Android platform-tools to PATH:

```bash
export PATH="$PATH:$HOME/Library/Android/sdk/platform-tools"
```

Add to `~/.zshrc` to make permanent.

### Android build fails with Gradle error

```bash
cd "/Users/rajat/Desktop/AI Learn/mobile app/i_am_rich"
flutter clean
flutter pub get
flutter run
```

If it still fails, delete the Gradle cache:

```bash
rm -rf ~/.gradle/caches/
```

### iOS `pod install` fails

```bash
cd "/Users/rajat/Desktop/AI Learn/mobile app/i_am_rich/ios"
pod repo update
pod install --repo-update
```

### iOS Simulator shows blank/black screen

```bash
flutter clean
flutter run -d ios
```

Or in Simulator: **Device → Erase All Content and Settings**, then re-run.

### No devices found (`flutter devices` returns nothing)

- **Android:** Check USB cable, re-plug, confirm "Allow USB debugging" dialog appeared on phone.
- **iOS Simulator:** Make sure a simulator is booted — run `open -a Simulator`.
- **Both:** Run `flutter doctor -v` and fix any ✗ items.

### `audioplayers` has no sound on iOS Simulator

Sound APIs are limited on the iOS Simulator — this is an Apple limitation. The party horn sound will work correctly on a real iOS device and on Android (physical or emulator).

---

*Last updated: May 2026 · Flutter 3.41.9*
