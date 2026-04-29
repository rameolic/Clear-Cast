import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class AdBlockerService {
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
  ];

  function hideAds() {
    adSelectors.forEach(function(selector) {
      document.querySelectorAll(selector).forEach(function(el) {
        el.style.setProperty('display', 'none', 'important');
        el.style.setProperty('visibility', 'hidden', 'important');
        el.style.setProperty('height', '0', 'important');
        el.style.setProperty('overflow', 'hidden', 'important');
      });
    });
  }

  // Run immediately and observe DOM mutations
  hideAds();
  const observer = new MutationObserver(hideAds);
  observer.observe(document.body || document.documentElement, {
    childList: true, subtree: true
  });
})();
''';

  /// JavaScript to enable D-pad / TV remote scrolling inside WebView
  static const String tvNavigationJs = '''
(function() {
  document.addEventListener('keydown', function(e) {
    const scrollAmount = 200;
    switch(e.keyCode) {
      case 38: // DPAD UP
        window.scrollBy(0, -scrollAmount);
        e.preventDefault();
        break;
      case 40: // DPAD DOWN
        window.scrollBy(0, scrollAmount);
        e.preventDefault();
        break;
      case 37: // DPAD LEFT
        window.scrollBy(-scrollAmount, 0);
        e.preventDefault();
        break;
      case 39: // DPAD RIGHT
        window.scrollBy(scrollAmount, 0);
        e.preventDefault();
        break;
    }
  });

  // Make all focusable elements highlight visibly when focused via D-pad
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

  /// WebView settings optimized for TV + ad blocking
  InAppWebViewSettings get webViewSettings => InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        useHybridComposition: true,
        supportZoom: false,
        builtInZoomControls: false,
        displayZoomControls: false,
        // Block mixed content
        mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
        // Disable unnecessary features
        databaseEnabled: false,
        domStorageEnabled: true,
        // User agent pretending to be a browser for better compatibility
        userAgent:
            'Mozilla/5.0 (Linux; Android 9; AFT) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      );
}
