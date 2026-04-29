# Flutter TV Browser App — Cursor Project Prompt

## Project Overview

Build a **Flutter APK for Android TV / Fire TV Stick** that:
- Fetches a list of URLs from a **Google Sheets CSV** (published publicly)
- Displays them on a landing page as a **4-column grid of cards** (title + thumbnail + category)
- Opens each URL in an **in-app WebView** with ad blocking enabled
- Supports full navigation via **Android TV remote / Fire TV Stick D-pad**

---

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter (Dart) — target Android TV + Fire TV |
| WebView | `flutter_inappwebview: ^6.1.5` |
| Data source | Google Sheets (published as CSV) |
| Image loading | `cached_network_image: ^3.3.1` |
| HTTP | `http: ^1.2.1` |
| Build target | Android APK (Leanback launcher for TV) |

---

## Project File Structure

```
lib/
├── main.dart                        # Entry point — landscape lock + immersive mode
├── models/
│   └── url_item.dart                # Data model: title, url, thumbnailUrl, category, description
├── screens/
│   ├── home_screen.dart             # Landing page — grid of URL cards
│   └── webview_screen.dart          # WebView player with ad blocker + TV nav
├── services/
│   ├── sheets_service.dart          # Fetches & parses Google Sheets CSV
│   └── ad_blocker_service.dart      # Domain blocklist + JS ad injection
└── widgets/
    └── url_card.dart                # Focusable TV card widget (glow on D-pad focus)

assets/
└── blocklist.txt                    # Extendable domain blocklist (one domain per line)

android/app/src/main/
└── AndroidManifest.xml              # TV + Fire TV leanback launcher config
```

---

## 1. Google Sheets Integration (`sheets_service.dart`)

### Sheet Setup
The Google Sheet must have these columns in Row 1 (headers):
```
A: title  |  B: url  |  C: thumbnailUrl  |  D: category  |  E: description
```

### CSV URL Pattern
```
https://docs.google.com/spreadsheets/d/{SHEET_ID}/gviz/tq?tqx=out:csv&sheet=Sheet1
```

### Key Logic
- Fetch via `http.get()` with 15s timeout
- Skip row 0 (headers), parse each subsequent row as a `UrlItem`
- Handle quoted CSV fields (commas inside quotes)
- If `thumbnailUrl` is empty, fallback to: `https://www.google.com/s2/favicons?domain={host}&sz=128`
- Skip rows where `url` field is empty

### Configuration (user must fill in)
```dart
static const String _sheetId = 'SHEET_ID_HERE'; // Replace with actual ID
static const String _sheetName = 'Sheet1';
```

---

## 2. Ad Blocker (`ad_blocker_service.dart`)

### Two-Layer Blocking

**Layer 1 — Network interception** (blocks requests before they load):
- Implement `shouldOverrideUrlLoading` → return `CANCEL` if domain is blocked
- Implement `shouldInterceptRequest` → return empty `WebResourceResponse` if domain is blocked

**Layer 2 — DOM injection** (hides remaining ad containers):
Inject this JS after every page load:
```javascript
// Target selectors to hide:
// iframe[src*="doubleclick"], ins.adsbygoogle, [data-ad-slot],
// div[class*="advertisement"], div[id*="google_ads"], div[id*="taboola"],
// .ad-banner, .ad-container, .sponsored-content
// Use MutationObserver to catch dynamically injected ads
```

### Built-in Blocked Domains (minimum required)
```
googleadservices.com, googlesyndication.com, doubleclick.net,
adnxs.com, taboola.com, outbrain.com, criteo.com, criteo.net,
hotjar.com, mixpanel.com, segment.com, scoreboardresearch.com,
amazon-adsystem.com, pubmatic.com, rubiconproject.com,
coinhive.com, propellerads.com, popcash.net, popads.net
```
Plus domains in `assets/blocklist.txt` (loaded at startup via `rootBundle`).

### WebView Settings
```dart
InAppWebViewSettings(
  javaScriptEnabled: true,
  mediaPlaybackRequiresUserGesture: false,
  allowsInlineMediaPlayback: true,
  useHybridComposition: true,
  supportZoom: false,
  builtInZoomControls: false,
  mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
  domStorageEnabled: true,
  userAgent: 'Mozilla/5.0 (Linux; Android 9; AFT) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
)
```

---

## 3. TV Remote / D-pad Navigation

### Home Screen (Grid Navigation)
- Use `Focus` widget wrapping each `UrlCard`
- First card gets `autofocus: true`
- On focus: scale card up (1.08x) + show cyan glow border
- On D-pad SELECT/ENTER → navigate to WebView screen
- Use `AnimationController` for smooth scale transition

### WebView Screen (Inside WebView)
- Use `KeyboardListener` wrapping the `InAppWebView`
- Handle these `LogicalKeyboardKey` values:
  - `arrowUp` → `window.scrollBy(0, -200)` via `evaluateJavascript`
  - `arrowDown` → `window.scrollBy(0, 200)`
  - `arrowLeft` → `window.scrollBy(-200, 0)`
  - `arrowRight` → `window.scrollBy(200, 0)`
  - `goBack` / `escape` → check `canGoBack()`, either go back in webview or `Navigator.pop()`
- Also inject JS `tvNavigationJs` that adds a `keydown` event listener to handle scroll inside the page

### Back Button Handling
```dart
PopScope(
  canPop: false,
  onPopInvoked: (didPop) async {
    if (_canGoBack) {
      await _webViewController.goBack();
    } else {
      Navigator.of(context).pop();
    }
  },
)
```

### TV-Focusable Button Pattern
Every interactive element must:
1. Be wrapped in a `Focus` widget
2. Use `onFocusChange` to track focus state
3. Visually change on focus: border color → cyan (`#00E5FF`), background tint
4. Handle `GestureDetector.onTap` for click

---

## 4. UI Design & Theme

### Color Palette
```dart
backgroundColor: Color(0xFF080E1A)   // Near-black background
surface:         Color(0xFF0D1B2E)   // Card/surface
accent:          Color(0xFF00E5FF)   // Cyan — focus glow, category badge, progress
cardGradient:    [Color(0xFF141E30), Color(0xFF0A1020)]
focusGradient:   [Color(0xFF1A2744), Color(0xFF0D1B2E)]
```

### Home Screen Layout
- `Column` → Header → `GridView.builder`
- Grid: `crossAxisCount: 4`, `crossAxisSpacing: 20`, `mainAxisSpacing: 20`, `childAspectRatio: 16/11`
- Padding: `horizontal: 48`

### URL Card Layout (per card)
```
┌─────────────────────────────┐
│                             │  ← Thumbnail (flex: 3)
│      CachedNetworkImage     │
│                             │
├─────────────────────────────│
│  Title (15px bold)          │  ← Info section (flex: 2)
│  Description (11px muted)   │
│  [CATEGORY BADGE]           │
└─────────────────────────────┘
```

- Focused state: scale 1.08x + cyan border (3px) + box shadow glow
- Unfocused state: dim border (1px, 10% white opacity)

### WebView Top Bar
- Height: 56px, background: `#0D1B2E`
- Elements: `[Back] [Reload]  Page Title...  [🛡 AD BLOCKED]`
- All buttons are TV-focusable with same focus pattern

### App Entry (`main.dart`)
```dart
SystemChrome.setPreferredOrientations([
  DeviceOrientation.landscapeLeft,
  DeviceOrientation.landscapeRight,
]);
SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
```

---

## 5. AndroidManifest.xml Requirements

```xml
<!-- Required permissions -->
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>

<!-- TV feature declarations -->
<uses-feature android:name="android.software.leanback" android:required="false"/>
<uses-feature android:name="android.hardware.touchscreen" android:required="false"/>

<!-- App-level -->
android:hardwareAccelerated="true"
android:usesCleartextTraffic="true"

<!-- Activity must have BOTH intent filters -->
<!-- 1. Standard launcher -->
<action android:name="android.intent.action.MAIN"/>
<category android:name="android.intent.category.LAUNCHER"/>

<!-- 2. TV / Leanback launcher -->
<action android:name="android.intent.action.MAIN"/>
<category android:name="android.intent.category.LEANBACK_LAUNCHER"/>
```

---

## 6. pubspec.yaml Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_inappwebview: ^6.1.5
  http: ^1.2.1
  cached_network_image: ^3.3.1
  url_launcher: ^6.3.0

flutter:
  uses-material-design: true
  assets:
    - assets/blocklist.txt
```

---

## 7. Error & Loading States

### Home Screen States
| State | Display |
|---|---|
| Loading | `CircularProgressIndicator` (cyan) + "Loading from Google Sheets..." |
| Error | Cloud-off icon + error message + autofocused "Try Again" button |
| Empty | Inbox icon + "No URLs found in your sheet." |
| Loaded | 4-column grid of `UrlCard` widgets |

### WebView States
- Loading: `LinearProgressIndicator` at top (cyan, `minHeight: 3`)
- `indeterminate` when progress = 0, `determinate` when progress > 0

---

## 8. Data Flow

```
Google Sheets (published CSV)
        ↓  HTTP GET (SheetsService)
List<UrlItem> 
        ↓  setState
GridView → UrlCard × N
        ↓  onTap / D-pad SELECT
WebViewScreen(item)
        ↓  InAppWebView loads item.url
shouldInterceptRequest → AdBlockerService.shouldBlock(url)
        ↓  if blocked → empty WebResourceResponse
        ↓  if allowed → load normally
onLoadStop → inject adHidingJs + tvNavigationJs
```

---

## 9. Known Constraints & Solutions

| Constraint | Solution |
|---|---|
| WebView captures all key events | Wrap with `KeyboardListener`, pass D-pad events as JS |
| Fire TV has no touch | All interactions via `Focus` + `GestureDetector` |
| Ad blocker ~80-90% effective | Network block + DOM JS injection for remaining |
| WebView focus steals back button | `PopScope` with `canPop: false` + manual goBack check |
| TV requires leanback launcher | Both `LAUNCHER` and `LEANBACK_LAUNCHER` in manifest |
| Blank thumbnails | Fallback to Google Favicon Service (`sz=128`) |

---

## 10. How to Build & Sideload

```bash
# Install deps
flutter pub get

# Build release APK
flutter build apk --release

# APK location
build/app/outputs/flutter-apk/app-release.apk

# Sideload to Fire TV / Android TV via ADB
adb connect <TV_IP>:5555
adb install build/app/outputs/flutter-apk/app-release.apk
```

---

## Implementation Checklist

- [ ] `pubspec.yaml` — all dependencies + assets declared
- [ ] `AndroidManifest.xml` — INTERNET permission + both launcher intent filters + leanback feature
- [ ] `url_item.dart` — model with `fromCsvRow` + `resolvedThumbnail` fallback
- [ ] `sheets_service.dart` — CSV fetch + quoted-field parser + header row skip
- [ ] `ad_blocker_service.dart` — domain set + `shouldBlock()` + `adHidingJs` + `tvNavigationJs` + `webViewSettings`
- [ ] `url_card.dart` — `Focus` + `AnimationController` scale + glow border + thumbnail + info
- [ ] `home_screen.dart` — GridView 4-col + all 3 states (loading/error/loaded) + refresh button
- [ ] `webview_screen.dart` — `shouldInterceptRequest` + `shouldOverrideUrlLoading` + JS injection + D-pad handler + `PopScope` back nav + top bar
- [ ] `main.dart` — landscape lock + immersive mode + dark theme
- [ ] `assets/blocklist.txt` — at least 20 ad/tracker domains

---

## User Configuration Required

After scaffolding, the user must:
1. Open `lib/services/sheets_service.dart` and set `_sheetId` to their Google Sheet ID
2. Publish their Google Sheet as CSV: **File → Share → Publish to web → Sheet1 → CSV**
3. Populate sheet with: `title | url | thumbnailUrl | category | description`
4. Run `flutter pub get && flutter build apk --release`
