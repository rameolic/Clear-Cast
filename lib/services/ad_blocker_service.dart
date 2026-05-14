import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
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
      'redirect_url=',
      'redirect_uri=',
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
    '[class*="popup"]',
    '[id*="popup"]',
    '[class*="overlay"]',
    '[id*="overlay"]',
    '[class*="modal"]',
    '[id*="modal"]',
    '[class*="interstitial"]',
    '[id*="interstitial"]',
    '[class*="captcha"]',
    '[id*="captcha"]',
    'iframe[src*="captcha"]',
    'iframe[src*="cloudflare"]',
    'iframe[src*="recaptcha"]',
  ];

  const textSignals = [
    "confirm you're not a robot",
    "confirm you are not a robot",
    'scan the qr-code',
    'scan the qr code',
    'verify you are human',
    'click allow to continue',
  ];

  function hideElement(el) {
    el.style.setProperty('display', 'none', 'important');
    el.style.setProperty('visibility', 'hidden', 'important');
    el.style.setProperty('opacity', '0', 'important');
    el.style.setProperty('pointer-events', 'none', 'important');
    el.style.setProperty('height', '0', 'important');
    el.style.setProperty('max-height', '0', 'important');
    el.style.setProperty('overflow', 'hidden', 'important');
  }

  function looksLikeHijackOverlay(el) {
    const text = (el.innerText || '').toLowerCase().trim();
    const hasSignalText = textSignals.some(signal => text.includes(signal));
    if (hasSignalText) return true;

    const style = window.getComputedStyle(el);
    const isFixed = style.position === 'fixed' || style.position === 'sticky';
    const z = parseInt(style.zIndex || '0', 10);
    const wide = el.offsetWidth >= window.innerWidth * 0.75;
    const tall = el.offsetHeight >= window.innerHeight * 0.35;
    return isFixed && z >= 999 && wide && tall;
  }

  function hideAds() {
    adSelectors.forEach(function(selector) {
      document.querySelectorAll(selector).forEach(function(el) {
        hideElement(el);
      });
    });

    // Remove first-party anti-bot/ad overlays that are not loaded from ad domains.
    document.querySelectorAll('div, section, aside, article').forEach(function(el) {
      if (looksLikeHijackOverlay(el)) {
        hideElement(el);
      }
    });

    // Sites often lock scrolling when overlays open; restore navigation.
    if (document.body) {
      document.body.style.setProperty('overflow', 'auto', 'important');
      document.body.style.setProperty('position', 'static', 'important');
    }
    if (document.documentElement) {
      document.documentElement.style.setProperty('overflow', 'auto', 'important');
    }
  }

  // Run immediately and observe DOM mutations
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
  InAppWebViewSettings webViewSettings({required bool compatibilityMode}) =>
      InAppWebViewSettings(
        javaScriptEnabled: true,
        isFindInteractionEnabled: true,
        javaScriptCanOpenWindowsAutomatically: false,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        useHybridComposition: true,
        supportMultipleWindows: false,
        supportZoom: false,
        builtInZoomControls: false,
        displayZoomControls: false,
        mixedContentMode: compatibilityMode
            ? MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE
            : MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
        databaseEnabled: true,
        domStorageEnabled: true,
        thirdPartyCookiesEnabled: true,
        cacheMode: CacheMode.LOAD_DEFAULT,
        userAgent:
            compatibilityMode ? null : defaultProtectionUserAgent(),
      );
}
