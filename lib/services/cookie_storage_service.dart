import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'logger_service.dart';

/// Persists WebView cookies per Google Sheets entry URL in [SharedPreferences].
class CookieStorageService {
  static final CookieStorageService _instance = CookieStorageService._();
  factory CookieStorageService() => _instance;
  CookieStorageService._();

  static const String _prefsPrefix = 'clearcast_cookies_';
  static const int _maxCookiesPerItem = 80;

  final CookieManager _cookieManager = CookieManager.instance();

  String _prefsKey(String itemUrl) {
    final uri = Uri.tryParse(itemUrl);
    final host = (uri?.host ?? itemUrl).toLowerCase();
    final path = uri?.path.isEmpty == true ? '/' : (uri?.path ?? '/');
    return '$_prefsPrefix$host$path';
  }

  String? _hostFor(String itemUrl) {
    try {
      return Uri.parse(itemUrl).host.toLowerCase();
    } catch (_) {
      return null;
    }
  }

  bool _cookieMatchesSite(Cookie cookie, String siteHost) {
    final raw = (cookie.domain ?? siteHost).toLowerCase();
    final domain = raw.startsWith('.') ? raw.substring(1) : raw;
    return domain == siteHost || domain.endsWith('.$siteHost');
  }

  List<String> _urlsForItem(String itemUrl, List<String> extraUrls) {
    final urls = <String>{itemUrl};
    for (final extra in extraUrls) {
      if (extra.trim().isNotEmpty) {
        urls.add(extra.trim());
      }
    }
    return urls.toList();
  }

  /// Loads stored cookies into the WebView cookie store before navigation.
  /// Returns how many cookies were applied.
  Future<int> restoreForItem(
    String itemUrl, {
    List<String> extraUrls = const [],
    InAppWebViewController? webViewController,
  }) async {
    final host = _hostFor(itemUrl);
    if (host == null || host.isEmpty) {
      return 0;
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey(itemUrl));
    if (raw == null || raw.isEmpty) {
      return 0;
    }

    List<dynamic> decoded;
    try {
      decoded = jsonDecode(raw) as List<dynamic>;
    } catch (e) {
      AppLogger.warn('Skipped corrupt cookie payload for $itemUrl: $e');
      return 0;
    }

    var restored = 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final targetUrls = _urlsForItem(itemUrl, extraUrls);

    for (final entry in decoded) {
      if (entry is! Map) {
        continue;
      }
      final cookie = Cookie.fromMap(Map<String, dynamic>.from(entry));
      if (cookie == null || cookie.name.isEmpty) {
        continue;
      }
      if (cookie.expiresDate != null && cookie.expiresDate! < now) {
        continue;
      }

      final cookieHost = (cookie.domain ?? host).toLowerCase().replaceFirst(
            RegExp(r'^\.'),
            '',
          );
      var setUrl = itemUrl;
      for (final candidate in targetUrls) {
        final candidateHost = _hostFor(candidate);
        if (candidateHost != null &&
            (cookieHost == candidateHost ||
                cookieHost.endsWith('.$candidateHost') ||
                candidateHost.endsWith('.$cookieHost'))) {
          setUrl = candidate;
          break;
        }
      }

      try {
        await _cookieManager.setCookie(
          url: WebUri(setUrl),
          name: cookie.name,
          value: cookie.value?.toString() ?? '',
          path: cookie.path ?? '/',
          domain: cookie.domain,
          expiresDate: cookie.expiresDate,
          isSecure: cookie.isSecure,
          isHttpOnly: cookie.isHttpOnly,
          sameSite: cookie.sameSite,
          webViewController: webViewController,
        );
        restored++;
      } catch (e) {
        AppLogger.warn('Failed to restore cookie ${cookie.name} for $itemUrl');
      }
    }

    if (restored > 0) {
      AppLogger.info('Restored $restored cookie(s) for $itemUrl');
    }
    return restored;
  }

  /// How many cookies are stored locally for this sheet item (not yet expired).
  Future<int> storedCountForItem(String itemUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey(itemUrl));
    if (raw == null || raw.isEmpty) {
      return 0;
    }
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final now = DateTime.now().millisecondsSinceEpoch;
      return decoded.where((entry) {
        if (entry is! Map) {
          return false;
        }
        final cookie = Cookie.fromMap(Map<String, dynamic>.from(entry));
        if (cookie == null) {
          return false;
        }
        if (cookie.expiresDate != null && cookie.expiresDate! < now) {
          return false;
        }
        return true;
      }).length;
    } catch (_) {
      return 0;
    }
  }

  /// Snapshots cookies for the sheet item's site and extra allowed hosts.
  Future<int> saveForItem(
    String itemUrl, {
    List<String> extraUrls = const [],
    InAppWebViewController? webViewController,
  }) async {
    final host = _hostFor(itemUrl);
    if (host == null || host.isEmpty) {
      return 0;
    }

    final merged = <String, Cookie>{};
    final targetUrls = _urlsForItem(itemUrl, extraUrls);
    final hosts = targetUrls
        .map(_hostFor)
        .whereType<String>()
        .where((h) => h.isNotEmpty)
        .toSet();

    for (final url in targetUrls) {
      try {
        for (final cookie in await _cookieManager.getCookies(
          url: WebUri(url),
          webViewController: webViewController,
        )) {
          merged[_cookieKey(cookie)] = cookie;
        }
      } catch (e) {
        AppLogger.warn('getCookies failed for $url: $e');
      }
    }

    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.android) {
      try {
        for (final cookie in await _cookieManager.getAllCookies()) {
          for (final siteHost in hosts) {
            if (_cookieMatchesSite(cookie, siteHost)) {
              merged[_cookieKey(cookie)] = cookie;
              break;
            }
          }
        }
      } catch (e) {
        AppLogger.warn('getAllCookies failed for $itemUrl: $e');
      }
    }

    if (merged.isEmpty) {
      return 0;
    }

    final cookies = merged.values.take(_maxCookiesPerItem).toList();
    final payload = jsonEncode(cookies.map((c) => c.toMap()).toList());

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey(itemUrl), payload);
    AppLogger.info('Saved ${cookies.length} cookie(s) for $itemUrl');
    return cookies.length;
  }

  String _cookieKey(Cookie cookie) {
    return '${cookie.name}|${cookie.domain ?? ''}|${cookie.path ?? '/'}';
  }
}
