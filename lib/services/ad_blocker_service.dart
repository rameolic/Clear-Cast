import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'device_profile_service.dart';
import 'logger_service.dart';

class AdBlockerService {
  /// Chrome / Safari user agents that match real browsers (not embedded-TV WebViews).
  /// Reduces false positives from bot overlays when protection is on.
  static String defaultProtectionUserAgent() {
    if (kIsWeb) {
      return _chromeDesktopUa;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        if (DeviceProfileService.instance.isAndroidTv) {
          // Fire TV WebView handles native HLS better than desktop-Chrome MSE.
          return 'Mozilla/5.0 (Linux; Android 13; SHIELD Android TV) '
              'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 '
              'Safari/537.36';
        }
        return 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
      case TargetPlatform.iOS:
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 '
            'Safari/604.1';
      case TargetPlatform.macOS:
        return 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15';
      case TargetPlatform.windows:
        return _chromeDesktopUa;
      case TargetPlatform.linux:
        return 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
      default:
        return _chromeDesktopUa;
    }
  }

  static const String _chromeDesktopUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  static final AdBlockerService _instance = AdBlockerService._internal();
  factory AdBlockerService() => _instance;
  AdBlockerService._internal();

  final Set<String> _blockedDomains = {};
  bool _initialized = false;

  /// Built-in list of common ad/tracker domains
  static const List<String> _builtInBlocklist = [
    // Google Ads
    'googleadservices.com', 'googlesyndication.com', 'doubleclick.net',
    'adservice.google.com', 'pagead2.googlesyndication.com',
    // Social trackers
    'connect.facebook.net', 'platform.twitter.com', 'ads.twitter.com',
    'analytics.twitter.com',
    // Ad networks
    'adnxs.com', 'adsrvr.org', 'advertising.com', 'adroll.com',
    'outbrain.com', 'taboola.com', 'revcontent.com', 'mgid.com',
    'propellerads.com', 'popcash.net', 'popads.net', 'trafficjunky.com',
    'exoclick.com', 'juicyads.com', 'traffichaus.com',
    // Trackers / analytics
    'hotjar.com', 'fullstory.com', 'mixpanel.com', 'segment.com',
    'chartbeat.com', 'scorecardresearch.com', 'quantserve.com',
    'comscore.com', 'krxd.net', 'bluekai.com', 'rubiconproject.com',
    'pubmatic.com', 'openx.net', 'appnexus.com', 'casalemedia.com',
    'adsafeprotected.com', 'moatads.com', 'amazon-adsystem.com',
    // Popups / redirect ads
    'clksite.com', 'adclick.g.doubleclick.net', 'ad.doubleclick.net',
    'ads.pubmatic.com', 'secure.adnxs.com',
    // Crypto miners
    'coinhive.com', 'coin-hive.com', 'minero.cc', 'cryptoloot.pro',
    // General trackers
    'mc.yandex.ru', 'counter.yadro.ru', 'tr.snapchat.com',
    'bat.bing.com', 'ads.linkedin.com', 'px.ads.linkedin.com',
  ];

  Future<void> initialize() async {
    if (_initialized) return;

    // Load built-in list
    _blockedDomains.addAll(_builtInBlocklist);

    // Try loading extended list from assets
    try {
      final content = await rootBundle.loadString('assets/blocklist.txt');
      final lines = content.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
          _blockedDomains.add(trimmed);
        }
      }
    } catch (_) {
      // Asset not found — that's fine, built-in list still active
    }

    _initialized = true;
    AppLogger.info('AdBlocker initialized with ${_blockedDomains.length} blocked domains');
  }

  /// Returns true if the URL should be blocked
  bool shouldBlock(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      for (final domain in _blockedDomains) {
        if (host == domain || host.endsWith('.$domain')) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  /// HLS/DASH/progressive media. These must not go through
  /// [shouldInterceptRequest] — the Dart hop breaks range requests and MSE.
  bool isMediaUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.startsWith('blob:') ||
        lower.contains('googlevideo') ||
        lower.contains('/videoplayback') ||
        lower.contains('mime=video') ||
        lower.contains('mime=audio')) {
      return true;
    }
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? lower;
    const extensions = <String>[
      '.m3u8',
      '.mpd',
      '.mp4',
      '.webm',
      '.m4s',
      '.m4a',
      '.ts',
      '.aac',
      '.mp3',
    ];
    for (final ext in extensions) {
      if (path.endsWith(ext)) {
        return true;
      }
    }
    return false;
  }

  /// Skip intercept for media and static assets so playback is not stalled.
  bool shouldSkipIntercept(String url) {
    if (isMediaUrl(url)) {
      return true;
    }
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    const extensions = <String>[
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.webp',
      '.svg',
      '.ico',
      '.woff',
      '.woff2',
      '.ttf',
      '.otf',
    ];
    for (final ext in extensions) {
      if (path.endsWith(ext)) {
        return true;
      }
    }
    return false;
  }

  /// Restrict navigation to safe web schemes only.
  bool isAllowedScheme(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    return scheme == 'https' || scheme == 'http' || scheme == 'about';
  }

  /// Best-effort check for known malicious or ad-redirect URL patterns.
  bool looksLikeSuspiciousRedirect(String url) {
    final lower = url.toLowerCase();
    const suspiciousTokens = <String>[
      'popup=',
      'popunder=',
      'utm_source=push',
      'adurl=',
      'popads',
      'popcash',
      'doubleclick.net',
      'taboola.com',
      'outbrain.com',
    ];
    for (final token in suspiciousTokens) {
      if (lower.contains(token)) {
        return true;
      }
    }
    return false;
  }

  /// Minimal patches before page scripts run anti-bot checks (best-effort only).
  static const String antiAutomationPatchJs = '''
(function() {
  try {
    Object.defineProperty(navigator, 'webdriver', {
      get: function() { return false; },
      configurable: true
    });
  } catch (e) {}
})();
''';

  /// JavaScript to inject into every page to hide ad elements
  static const String adHidingJs = '''
(function() {
  if (window.__clearcastAdHide) return;
  window.__clearcastAdHide = true;

  const adSelectors = [
    'iframe[src*="doubleclick"]',
    'iframe[src*="googlesyndication"]',
    'iframe[src*="adnxs"]',
    'iframe[src*="taboola"]',
    'iframe[src*="outbrain"]',
    'div[id*="google_ads"]',
    'div[class*="advertisement"]',
    'div[class*="adsbygoogle"]',
    'div[id*="taboola"]',
    'div[id*="outbrain"]',
    'ins.adsbygoogle',
    '[data-ad-slot]',
    '[data-ad-unit]',
    '.ad-banner',
    '.ad-container',
    '.sponsored-content',
    '#ad-wrapper',
  ];

  const textSignals = [
    "confirm you're not a robot",
    "confirm you are not a robot",
    'scan the qr-code',
    'scan the qr code',
    'verify you are human',
    'click allow to continue',
  ];

  function containsMedia(el) {
    if (!el) return false;
    const tag = (el.tagName || '').toLowerCase();
    if (tag === 'video' || tag === 'audio' || tag === 'iframe' ||
        tag === 'canvas' || tag === 'embed' || tag === 'object') {
      return true;
    }
    return !!(el.querySelector &&
      el.querySelector('video, audio, iframe, canvas, embed, object'));
  }

  function hideElement(el) {
    if (containsMedia(el)) return;
    el.style.setProperty('display', 'none', 'important');
    el.style.setProperty('visibility', 'hidden', 'important');
    el.style.setProperty('pointer-events', 'none', 'important');
  }

  function looksLikeHijackOverlay(el) {
    if (containsMedia(el)) return false;
    const cls = ((el.className && el.className.toString) ? el.className.toString() : '').toLowerCase();
    if (cls.indexOf('player') !== -1 || cls.indexOf('video') !== -1 ||
        cls.indexOf('jwplayer') !== -1 || cls.indexOf('plyr') !== -1) {
      return false;
    }
    const text = (el.innerText || '').toLowerCase().trim();
    return textSignals.some(function(signal) { return text.includes(signal); });
  }

  function hideAds() {
    adSelectors.forEach(function(selector) {
      document.querySelectorAll(selector).forEach(function(el) {
        hideElement(el);
      });
    });
    document.querySelectorAll('div, section, aside, article').forEach(function(el) {
      if (looksLikeHijackOverlay(el)) {
        hideElement(el);
      }
    });
  }

  hideAds();
  const observer = new MutationObserver(hideAds);
  observer.observe(document.body || document.documentElement, {
    childList: true, subtree: true
  });
})();
''';

  /// In-page focus rings for TV remote navigation inside WebView.
  static const String tvFocusOutlineJs = '''
(function() {
  const style = document.createElement('style');
  style.textContent = `
    a:focus, button:focus, input:focus, select:focus, [tabindex]:focus {
      outline: 3px solid #93C643 !important;
      outline-offset: 2px !important;
    }
  `;
  document.head.appendChild(style);
})();
''';

  /// Visible virtual cursor for Android TV, drawn in-page (not Flutter overlay).
  static const String tvVirtualCursorJs = '''
(function() {
  if (window.__tvCursor) return;

  const EDGE = 48;
  let x = window.innerWidth / 2;
  let y = window.innerHeight / 2;
  let active = false;
  let ring = null;

  function ensureRing() {
    if (ring && ring.isConnected) return;
    ring = document.createElement('div');
    ring.setAttribute('id', '__clearcast_tv_cursor');
    ring.style.cssText = [
      'position:fixed',
      'width:30px',
      'height:30px',
      'margin-left:-15px',
      'margin-top:-15px',
      'border:3px solid #93C643',
      'border-radius:50%',
      'background:rgba(147,198,67,0.35)',
      'pointer-events:none',
      'z-index:2147483647',
      'display:none'
    ].join(';');
    (document.body || document.documentElement).appendChild(ring);
  }

  function updateRing() {
    ensureRing();
    ring.style.left = x + 'px';
    ring.style.top = y + 'px';
    ring.style.display = active ? 'block' : 'none';
  }

  function clickAt(px, py) {
    let el = document.elementFromPoint(px, py);
    if (!el) return;
    let target = el;
    for (let i = 0; i < 15 && target; i++) {
      const tag = (target.tagName || '').toLowerCase();
      const role = target.getAttribute && target.getAttribute('role');
      const tabIndex = target.getAttribute && target.getAttribute('tabindex');
      const clickable = tag === 'a' || tag === 'button' || tag === 'input' ||
        tag === 'select' || tag === 'textarea' || tag === 'label' ||
        role === 'button' || role === 'link' || role === 'menuitem' ||
        target.onclick || (tabIndex !== null && tabIndex !== '-1');
      if (clickable) {
        el = target;
        break;
      }
      target = target.parentElement;
    }
    const opts = {
      bubbles: true,
      cancelable: true,
      clientX: px,
      clientY: py,
      view: window
    };
    ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click'].forEach(function(type) {
      el.dispatchEvent(new MouseEvent(type, opts));
    });
    try {
      if (el.focus) el.focus({ preventScroll: false });
    } catch (e) {
      if (el.focus) el.focus();
    }
  }

  function move(dx, dy) {
    const maxX = Math.max(0, window.innerWidth - 1);
    const maxY = Math.max(0, window.innerHeight - 1);
    let nx = Math.max(0, Math.min(maxX, x + dx));
    let ny = Math.max(0, Math.min(maxY, y + dy));

    if (nx <= EDGE && dx < 0) window.scrollBy(dx, 0);
    if (nx >= maxX - EDGE && dx > 0) window.scrollBy(dx, 0);
    if (ny <= EDGE && dy < 0) window.scrollBy(0, dy);
    if (ny >= maxY - EDGE && dy > 0) window.scrollBy(0, dy);

    x = nx;
    y = ny;
    updateRing();
  }

  window.addEventListener('resize', function() {
    x = Math.min(x, Math.max(0, window.innerWidth - 1));
    y = Math.min(y, Math.max(0, window.innerHeight - 1));
    updateRing();
  });

  window.__tvCursor = {
    activate: function() {
      active = true;
      updateRing();
    },
    deactivate: function() {
      active = false;
      updateRing();
    },
    move: function(dx, dy) {
      if (active) move(dx, dy);
    },
    click: function() {
      if (active) clickAt(x, y);
    },
    setPosition: function(px, py) {
      x = px;
      y = py;
      updateRing();
    },
    isActive: function() {
      return active;
    }
  };
})();
''';

  static String jsClickAtPoint(double x, double y) => '''
(function() {
  var px = $x;
  var py = $y;
  var el = document.elementFromPoint(px, py);
  if (!el) return;
  var target = el;
  for (var i = 0; i < 15 && target; i++) {
    var tag = (target.tagName || '').toLowerCase();
    var role = target.getAttribute && target.getAttribute('role');
    var tabIndex = target.getAttribute && target.getAttribute('tabindex');
    var clickable = tag === 'a' || tag === 'button' || tag === 'input' ||
      tag === 'select' || tag === 'textarea' || tag === 'label' ||
      role === 'button' || role === 'link' || role === 'menuitem' ||
      target.onclick || (tabIndex !== null && tabIndex !== '-1');
    if (clickable) {
      el = target;
      break;
    }
    target = target.parentElement;
  }
  var opts = { bubbles: true, cancelable: true, clientX: px, clientY: py, view: window };
  ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click'].forEach(function(type) {
    el.dispatchEvent(new MouseEvent(type, opts));
  });
  try {
    if (el.focus) el.focus({ preventScroll: false });
  } catch (e) {
    if (el.focus) el.focus();
  }
})();
''';

  static String jsTvCursorSetPosition(double x, double y) =>
      'window.__tvCursor && window.__tvCursor.setPosition($x, $y);';

  static String jsTvCursorMove(double dx, double dy) =>
      'window.__tvCursor && window.__tvCursor.move($dx, $dy);';

  static const String jsTvCursorClick =
      'window.__tvCursor && window.__tvCursor.click();';

  static const String jsTvCursorActivate =
      'window.__tvCursor && window.__tvCursor.activate();';

  static const String jsTvCursorDeactivate =
      'window.__tvCursor && window.__tvCursor.deactivate();';

  /// D-pad scroll inside the page (non-TV; TV uses Flutter key handler).
  static const String tvScrollJs = '''
(function() {
  document.addEventListener('keydown', function(e) {
    const scrollAmount = 200;
    switch(e.keyCode) {
      case 38:
        window.scrollBy(0, -scrollAmount);
        e.preventDefault();
        break;
      case 40:
        window.scrollBy(0, scrollAmount);
        e.preventDefault();
        break;
      case 37:
        window.scrollBy(-scrollAmount, 0);
        e.preventDefault();
        break;
      case 39:
        window.scrollBy(scrollAmount, 0);
        e.preventDefault();
        break;
    }
  });
})();
''';

  /// Legacy combined scroll + focus (desktop / non-TV Android).
  static const String tvNavigationJs = '''
(function() {
  document.addEventListener('keydown', function(e) {
    const scrollAmount = 200;
    switch(e.keyCode) {
      case 38:
        window.scrollBy(0, -scrollAmount);
        e.preventDefault();
        break;
      case 40:
        window.scrollBy(0, scrollAmount);
        e.preventDefault();
        break;
      case 37:
        window.scrollBy(-scrollAmount, 0);
        e.preventDefault();
        break;
      case 39:
        window.scrollBy(scrollAmount, 0);
        e.preventDefault();
        break;
    }
  });
  const style = document.createElement('style');
  style.textContent = `
    a:focus, button:focus, input:focus, select:focus, [tabindex]:focus {
      outline: 3px solid #93C643 !important;
      outline-offset: 2px !important;
    }
  `;
  document.head.appendChild(style);
})();
''';

  /// WebView settings: [compatibilityMode] uses native default UA + permissive mixed content.
  /// Protection-on uses a real-browser UA, storage, and third-party cookies for sessions/embeds.
  InAppWebViewSettings webViewSettings({required bool compatibilityMode}) {
    final isTv = DeviceProfileService.instance.isAndroidTv;
    final interceptRequests = !compatibilityMode && !isTv;
    return InAppWebViewSettings(
      javaScriptEnabled: true,
      isFindInteractionEnabled: true,
      javaScriptCanOpenWindowsAutomatically: true,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      allowsPictureInPictureMediaPlayback: true,
      useHybridComposition: true,
      hardwareAcceleration: true,
      supportMultipleWindows: true,
      supportZoom: false,
      builtInZoomControls: false,
      displayZoomControls: false,
      mixedContentMode: (compatibilityMode || isTv)
          ? MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE
          : MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
      databaseEnabled: true,
      domStorageEnabled: true,
      thirdPartyCookiesEnabled: true,
      cacheMode: CacheMode.LOAD_DEFAULT,
      useShouldInterceptRequest: interceptRequests,
      useOnLoadResource: kDebugMode && !isTv,
      iframeAllow: 'fullscreen; autoplay; encrypted-media; picture-in-picture',
      iframeAllowFullscreen: true,
      preferredContentMode: UserPreferredContentMode.RECOMMENDED,
      userAgent: compatibilityMode ? null : defaultProtectionUserAgent(),
    );
  }
}
