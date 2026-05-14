import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Keeps main-frame navigation on the sheet item origin, plus optional allowed bases.
class NavigationGuard {
  static const Duration _bounceWindow = Duration(seconds: 90);

  static const Set<String> _contentPathRoots = {
    'movie',
    'movies',
    'watch',
    'video',
    'tv',
    'play',
    'embed',
    'title',
    'show',
    'series',
  };

  static String normalizedHost(String host) {
    var h = host.toLowerCase();
    if (h.startsWith('www.')) {
      h = h.substring(4);
    }
    return h;
  }

  /// True when [target] stays on the same site as [baseUrl].
  static bool matchesBaseUrl(String baseUrl, Uri target) {
    if (target.scheme == 'about') {
      return true;
    }
    final baseUri = Uri.tryParse(baseUrl);
    if (baseUri == null || baseUri.host.isEmpty) {
      return false;
    }
    if (target.host.isEmpty) {
      return false;
    }

    final baseHost = normalizedHost(baseUri.host);
    final targetHost = normalizedHost(target.host);
    if (baseHost == targetHost) {
      return true;
    }
    return targetHost.endsWith('.$baseHost');
  }

  /// True when [target] matches the sheet item URL or any allowed redirect base.
  static bool isNavigationAllowed({
    required String sheetItemUrl,
    required List<String> allowedUrls,
    required Uri target,
  }) {
    if (matchesBaseUrl(sheetItemUrl, target)) {
      return true;
    }
    for (final allowed in allowedUrls) {
      if (matchesBaseUrl(allowed, target)) {
        return true;
      }
    }
    return false;
  }

  static bool hasUserGesture(bool? hasGesture) => hasGesture == true;

  static bool isContentPath(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.length >= 2) {
      return true;
    }
    if (segments.length == 1) {
      return _contentPathRoots.contains(segments.first.toLowerCase());
    }
    return false;
  }

  static bool isPortalHomePath(Uri uri) {
    final path = uri.path;
    if (path.isEmpty || path == '/') {
      return true;
    }
    if (path == '/index.html' || path == '/index.htm') {
      return true;
    }
    final segments = uri.pathSegments;
    if (segments.length == 1) {
      final root = segments.first.toLowerCase();
      return root == 'browse' || root == 'home' || root == 'index';
    }
    return false;
  }

  static String _normalizedPath(String path) {
    if (path.isEmpty || path == '/') {
      return '/';
    }
    return path.endsWith('/') ? path : '$path/';
  }

  /// Same host + path (ignores query/fragment). Used for CF reloads and refresh.
  static bool isSameDocumentLocation(Uri a, Uri b) {
    return normalizedHost(a.host) == normalizedHost(b.host) &&
        _normalizedPath(a.path) == _normalizedPath(b.path);
  }

  static bool looksLikeCloudflareChallenge(String? title) {
    if (title == null || title.isEmpty) {
      return false;
    }
    final lower = title.toLowerCase();
    return lower.contains('checking your browser') ||
        lower.contains('just a moment') ||
        lower.contains('attention required') ||
        lower.contains('verify you are human');
  }

  /// True when [uri] is the sheet row URL or the site root on that host.
  static bool isSheetEntryUri(String sheetItemUrl, Uri uri) {
    if (!matchesBaseUrl(sheetItemUrl, uri)) {
      return false;
    }
    final sheetUri = Uri.tryParse(sheetItemUrl);
    if (sheetUri == null) {
      return false;
    }
    if (isPortalHomePath(uri)) {
      return true;
    }
    return _normalizedPath(uri.path) == _normalizedPath(sheetUri.path);
  }

  static bool _wasOnAllowedExternalSite({
    required String sheetItemUrl,
    required List<String> allowedUrls,
    required Uri uri,
  }) {
    if (matchesBaseUrl(sheetItemUrl, uri)) {
      return false;
    }
    for (final allowed in allowedUrls) {
      if (matchesBaseUrl(allowed, uri)) {
        return true;
      }
    }
    return false;
  }

  /// True when [uri] is on a host listed in the sheet `allowed` column.
  static bool isOnAllowedExternalSite({
    required String sheetItemUrl,
    required List<String> allowedUrls,
    required Uri uri,
  }) {
    return _wasOnAllowedExternalSite(
      sheetItemUrl: sheetItemUrl,
      allowedUrls: allowedUrls,
      uri: uri,
    );
  }

  /// Blocks scripted jumps back to the catalog/dashboard URL after an allowed redirect.
  static bool isScriptedBounceToSheetEntry({
    required String sheetItemUrl,
    required List<String> allowedUrls,
    required Uri? previous,
    required DateTime? previousAt,
    required bool? hasGesture,
    required Uri target,
  }) {
    if (previous == null || previousAt == null || hasUserGesture(hasGesture)) {
      return false;
    }
    if (isSameDocumentLocation(previous, target)) {
      return false;
    }
    if (!isSheetEntryUri(sheetItemUrl, target)) {
      return false;
    }
    if (isSheetEntryUri(sheetItemUrl, previous)) {
      return false;
    }
    if (DateTime.now().difference(previousAt) >= _bounceWindow) {
      return false;
    }
    if (_wasOnAllowedExternalSite(
      sheetItemUrl: sheetItemUrl,
      allowedUrls: allowedUrls,
      uri: previous,
    )) {
      return true;
    }
    if (matchesBaseUrl(sheetItemUrl, previous) && isContentPath(previous)) {
      return true;
    }
    return false;
  }

  static bool shouldBlockMainFrameNavigation({
    required String sheetItemUrl,
    required List<String> allowedUrls,
    required Uri? previous,
    required DateTime? previousAt,
    required NavigationAction navigationAction,
    required Uri target,
  }) {
    if (!navigationAction.isForMainFrame) {
      return false;
    }

    if (previous != null && isSameDocumentLocation(previous, target)) {
      return false;
    }

    if (!isNavigationAllowed(
      sheetItemUrl: sheetItemUrl,
      allowedUrls: allowedUrls,
      target: target,
    )) {
      return true;
    }

    final gesture = navigationAction.hasGesture;

    if (isScriptedBounceToSheetEntry(
      sheetItemUrl: sheetItemUrl,
      allowedUrls: allowedUrls,
      previous: previous,
      previousAt: previousAt,
      hasGesture: gesture,
      target: target,
    )) {
      return true;
    }

    // Allow further navigation on explicit off-site allowed bases.
    if (!matchesBaseUrl(sheetItemUrl, target)) {
      return false;
    }

    if (isForcedHomepageBounce(
      previous: previous,
      previousAt: previousAt,
      hasGesture: gesture,
      target: target,
    )) {
      return true;
    }
    return isCrossSiteHomepageHijack(
      previous: previous,
      previousAt: previousAt,
      hasGesture: gesture,
      target: target,
    );
  }

  static bool isForcedHomepageBounce({
    required Uri? previous,
    required DateTime? previousAt,
    required bool? hasGesture,
    required Uri target,
  }) {
    if (previous == null || previousAt == null) {
      return false;
    }
    if (hasUserGesture(hasGesture)) {
      return false;
    }
    if (previous.host.toLowerCase() != target.host.toLowerCase()) {
      return false;
    }
    if (!isContentPath(previous) || !isPortalHomePath(target)) {
      return false;
    }
    return DateTime.now().difference(previousAt) < _bounceWindow;
  }

  static bool isCrossSiteHomepageHijack({
    required Uri? previous,
    required DateTime? previousAt,
    required bool? hasGesture,
    required Uri target,
  }) {
    if (previous == null || previousAt == null) {
      return false;
    }
    if (hasUserGesture(hasGesture)) {
      return false;
    }
    if (previous.host.toLowerCase() == target.host.toLowerCase()) {
      return false;
    }
    if (!isContentPath(previous) || !isPortalHomePath(target)) {
      return false;
    }
    return DateTime.now().difference(previousAt) < _bounceWindow;
  }
}
