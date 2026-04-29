# Flutter TV Browser App

A Flutter Android TV / Fire TV Stick app that displays a curated grid of URLs fetched from Google Sheets, with built-in ad blocking and full D-pad/remote navigation support.

---

## 🚀 Quick Setup (5 Steps)

### Step 1 — Set Up Your Google Sheet

Create a Google Sheet with these exact column headers in Row 1:

| A: title | B: url | C: thumbnailUrl | D: category | E: description |
|---|---|---|---|---|
| YouTube | https://youtube.com | https://i.imgur.com/abc.png | Video | Watch videos |
| BBC News | https://bbc.com/news | | News | Latest news |

> 💡 `thumbnailUrl` and `description` are optional — the app auto-generates a favicon if thumbnailUrl is blank.

---

### Step 2 — Publish the Sheet

1. Open your Google Sheet
2. Go to **File → Share → Publish to web**
3. Select **Sheet1** and **CSV** format
4. Click **Publish**
5. Copy your **Sheet ID** from the URL:
   ```
   https://docs.google.com/spreadsheets/d/YOUR_SHEET_ID_HERE/edit
   ```

---

### Step 3 — Add Your Sheet ID to the App

Open `lib/services/sheets_service.dart` and replace:
```dart
static const String _sheetId = 'SHEET_ID_HERE'; // 👈 Replace this
```
with your actual Sheet ID.

---

### Step 4 — Install Dependencies

```bash
flutter pub get
```

---

### Step 5 — Build the APK

```bash
# Debug APK (for testing / sideloading)
flutter build apk --debug

# Release APK (for production)
flutter build apk --release
```

APK location: `build/app/outputs/flutter-apk/app-release.apk`

---

## 📺 Installing on Fire TV Stick

### Method A — ADB (Recommended for developers)
```bash
# Enable ADB on your Fire TV: Settings → My Fire TV → Developer Options → ADB Debugging ON

# Connect (find Fire TV IP in Settings → My Fire TV → About → Network)
adb connect YOUR_FIRETV_IP:5555

# Install
adb install build/app/outputs/flutter-apk/app-release.apk
```

### Method B — Downloader App (Easiest for non-developers)
1. Install **Downloader** app from Fire TV App Store
2. Host your APK somewhere (Google Drive, Dropbox, etc.)
3. Open the direct download link in Downloader

---

## 📺 Installing on Android TV

```bash
adb connect YOUR_TV_IP:5555
adb install build/app/outputs/flutter-apk/app-release.apk
```

Or sideload via a USB drive if your TV supports it.

---

## 🎮 Remote Navigation

| Button | Action |
|---|---|
| **D-pad Up/Down/Left/Right** | Navigate between cards on home, scroll inside WebView |
| **Select / OK / Enter** | Open selected URL |
| **Back** | Go back in WebView history, or return to home |
| **Menu** | (Not used — extendable) |

---

## 🛡️ Ad Blocking

The app blocks ads at two levels:

1. **Network Level** — All requests to domains in the blocklist are intercepted and cancelled before they load
2. **DOM Level** — JavaScript is injected to hide any remaining ad containers on the page

To add more domains to block, edit `assets/blocklist.txt` — one domain per line.

---

## 📁 Project Structure

```
lib/
├── main.dart                    # App entry point, landscape lock
├── models/
│   └── url_item.dart            # URL data model
├── screens/
│   ├── home_screen.dart         # Landing grid page
│   └── webview_screen.dart      # WebView with ad blocker + TV nav
├── services/
│   ├── sheets_service.dart      # Google Sheets CSV fetcher
│   └── ad_blocker_service.dart  # Block list + JS injection
└── widgets/
    └── url_card.dart            # Focusable TV card widget

assets/
└── blocklist.txt                # Extended domain blocklist

android/app/src/main/
└── AndroidManifest.xml          # TV + leanback launcher config
```

---

## ⚙️ Customization

### Change Grid Columns
In `home_screen.dart`, update:
```dart
crossAxisCount: 4,  // Change to 3 for fewer, larger cards
```

### Change App Name
In `AndroidManifest.xml`:
```xml
android:label="TV Browser"  // Change this
```

### Update App Icon / Banner
Replace files in `android/app/src/main/res/mipmap-*/`

### Add More Blocked Domains
Edit `assets/blocklist.txt` and add one domain per line.

---

## 🔧 Troubleshooting

**"Could not load URLs"**
- Make sure the Google Sheet is published publicly (CSV format)
- Double-check the Sheet ID in `sheets_service.dart`
- Ensure your TV/stick has internet access

**App not showing in TV launcher**
- Ensure `LEANBACK_LAUNCHER` intent filter is in `AndroidManifest.xml` ✓
- Uninstall and reinstall the APK

**D-pad not working**
- The WebView captures focus — use Back to exit WebView
- Scroll works via D-pad up/down inside WebView

**Videos not playing**
- Some sites require specific user agents — the app uses a Chrome Android UA
- `mediaPlaybackRequiresUserGesture: false` is already set in WebView settings
