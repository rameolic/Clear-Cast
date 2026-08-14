import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:url_launcher/url_launcher.dart';

import '../layout/responsive_layout.dart';
import '../theme/clearcast_colors.dart';
import '../models/url_item.dart';
import '../services/ad_blocker_service.dart';
import '../services/cookie_storage_service.dart';
import '../services/device_profile_service.dart';
import '../services/logger_service.dart';
import '../services/navigation_guard_service.dart';
import '../widgets/plain_webview.dart';
import '../widgets/tv_focusable.dart';

class WebViewScreen extends StatefulWidget {
  final UrlItem item;
  final bool compatibilityMode;

  const WebViewScreen({
    super.key,
    required this.item,
    this.compatibilityMode = false,
  });

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  InAppWebViewController? _webViewController;
  final AdBlockerService _adBlocker = AdBlockerService();
  late final FindInteractionController _findInteractionController;
  bool _isLoading = true;
  double _loadingProgress = 0;
  String _currentTitle = '';
  final FocusNode _webViewFocusNode = FocusNode();
  final FocusNode _backButtonFocusNode = FocusNode();
  final TextEditingController _findController = TextEditingController();
  final FocusNode _findFocusNode = FocusNode();
  bool _showFindBar = false;
  int _findActiveMatch = 0;
  int _findTotalMatches = 0;
  bool _cookiesReady = false;
  int _sessionCookieCount = 0;
  final CookieStorageService _cookieStorage = CookieStorageService();
  Uri? _lastCommittedMainFrameUri;
  DateTime? _lastCommittedAt;
  bool _tvCursorHintShown = false;
  static const double _tvCursorStep = 28;
  static const double _tvCursorMaxStep = 96;
  static const double _tvEdgeScroll = 48;
  Offset _tvCursor = Offset.zero;
  Size _tvWebViewSize = Size.zero;
  bool _tvCursorReady = false;
  bool _handlingBack = false;
  int _heldMoves = 0;
  LogicalKeyboardKey? _heldDirection;

  bool _shouldCancelTopLevelNavigation(WebUri? targetUrl) {
    final url = targetUrl?.toString() ?? '';
    if (url.isEmpty) {
      return true;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) {
      return true;
    }

    if (!_adBlocker.isAllowedScheme(uri)) {
      return true;
    }

    if (_adBlocker.shouldBlock(url) ||
        _adBlocker.looksLikeSuspiciousRedirect(url)) {
      return true;
    }

    return false;
  }

  @override
  void initState() {
    super.initState();
    AppLogger.webView(
      widget.compatibilityMode
          ? 'open url=${widget.item.url} protection=off tv=${DeviceProfileService.instance.isAndroidTv}'
          : 'open url=${widget.item.url} protection=on tv=${DeviceProfileService.instance.isAndroidTv}',
    );
    if (widget.item.allowedUrls.isEmpty) {
      AppLogger.warn(
        'No allowed redirect URLs for "${widget.item.title}". '
        'Add column F in Sheets and re-publish (File → Share → Publish to web).',
      );
    } else {
      AppLogger.info(
        'Allowed redirect URLs for "${widget.item.title}": '
        '${widget.item.allowedUrls.join(', ')}',
      );
    }
    _currentTitle = widget.item.title;
    _findInteractionController = FindInteractionController(
      onFindResultReceived: (controller, activeMatchOrdinal, numberOfMatches,
          isDoneCounting) async {
        if (!mounted) {
          return;
        }
        setState(() {
          _findActiveMatch = activeMatchOrdinal;
          _findTotalMatches = numberOfMatches;
        });
      },
    );
    _prepareCookies();
    _webViewFocusNode.addListener(_handleWebViewFocusChanged);
    _findFocusNode.addListener(_onFindFocusChanged);
  }

  void _onFindFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleWebViewFocusChanged() {
    if (!DeviceProfileService.instance.isAndroidTv) {
      return;
    }
    final controller = _webViewController;
    final hasPageFocus = _webViewFocusNode.hasFocus && !_showFindBar;
    if (controller != null) {
      if (hasPageFocus) {
        controller.evaluateJavascript(source: AdBlockerService.jsTvCursorActivate);
        _syncTvCursorToJs();
      } else {
        controller.evaluateJavascript(
          source: AdBlockerService.jsTvCursorDeactivate,
        );
      }
    }
  }

  void _ensureTvCursor(Size size) {
    if (!DeviceProfileService.instance.isAndroidTv || size.width <= 0) {
      return;
    }
    _tvWebViewSize = size;
    if (_tvCursorReady) {
      return;
    }
    _tvCursor = Offset(size.width / 2, size.height / 2);
    _tvCursorReady = true;
    _syncTvCursorToJs();
  }

  void _syncTvCursorToJs() {
    if (!_tvCursorReady) {
      return;
    }
    _webViewController?.evaluateJavascript(
      source: AdBlockerService.jsTvCursorSetPosition(
        _tvCursor.dx,
        _tvCursor.dy,
      ),
    );
  }

  double _acceleratedStep() {
    return (_tvCursorStep + _heldMoves * 8).clamp(
      _tvCursorStep,
      _tvCursorMaxStep,
    );
  }

  bool _moveTvCursor(double dx, double dy) {
    if (!_tvCursorReady) {
      return false;
    }
    const edge = _tvEdgeScroll;
    var x = _tvCursor.dx + dx;
    var y = _tvCursor.dy + dy;

    if (y < edge && dy < 0) {
      _backButtonFocusNode.requestFocus();
      return true;
    }

    if (x < edge && dx < 0) {
      _webViewController?.evaluateJavascript(
        source: 'window.scrollBy(${dx.toInt()}, 0)',
      );
      x = edge;
    } else if (x > _tvWebViewSize.width - edge && dx > 0) {
      _webViewController?.evaluateJavascript(
        source: 'window.scrollBy(${dx.toInt()}, 0)',
      );
      x = _tvWebViewSize.width - edge;
    }
    if (y > _tvWebViewSize.height - edge && dy > 0) {
      _webViewController?.evaluateJavascript(
        source: 'window.scrollBy(0, ${dy.toInt()})',
      );
      y = _tvWebViewSize.height - edge;
    }

    _tvCursor = Offset(
      x.clamp(0, _tvWebViewSize.width),
      y.clamp(0, _tvWebViewSize.height),
    );
    _syncTvCursorToJs();
    return true;
  }

  void _clickTvCursor() {
    if (!_tvCursorReady) {
      return;
    }
    _webViewController?.evaluateJavascript(
      source: AdBlockerService.jsClickAtPoint(_tvCursor.dx, _tvCursor.dy),
    );
  }

  void _deactivateTvCursor() {
    _webViewController?.evaluateJavascript(
      source: AdBlockerService.jsTvCursorDeactivate,
    );
  }

  void _activateTvCursor() {
    _webViewController?.evaluateJavascript(
      source: AdBlockerService.jsTvCursorActivate,
    );
    _syncTvCursorToJs();
  }

  void _showTvCursorHintIfNeeded() {
    if (_tvCursorHintShown || !DeviceProfileService.instance.isAndroidTv) {
      return;
    }
    _tvCursorHintShown = true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'D-pad moves the cursor · OK / Enter clicks · ↑ toolbar · Back goes to previous page',
        ),
        duration: Duration(seconds: 4),
      ),
    );
  }

  Future<void> _prepareCookies() async {
    final restored = await _cookieStorage.restoreForItem(
      widget.item.url,
      extraUrls: widget.item.allowedUrls,
    );
    final stored = await _cookieStorage.storedCountForItem(widget.item.url);
    AppLogger.webView(
      'cookies restored=$restored stored=$stored url=${widget.item.url}',
    );
    if (mounted) {
      setState(() {
        _sessionCookieCount = restored > 0 ? restored : stored;
        _cookiesReady = true;
      });
    }
  }

  Future<void> _persistCookies() async {
    final controller = _webViewController;
    if (controller == null) {
      return;
    }
    final saved = await _cookieStorage.saveForItem(
      widget.item.url,
      extraUrls: widget.item.allowedUrls,
      webViewController: controller,
    );
    if (mounted && saved > 0) {
      setState(() => _sessionCookieCount = saved);
    }
  }

  Future<void> _exitWebView() async {
    await _persistCookies();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleBack() async {
    if (_handlingBack) {
      return;
    }
    _handlingBack = true;
    try {
      if (_showFindBar) {
        AppLogger.webView('back closed find bar');
        await _closeFindBar();
        return;
      }
      final controller = _webViewController;
      final canGoBack = controller != null && await controller.canGoBack();
      AppLogger.webView(
        'back canGoBack=$canGoBack current=${_logUrl(_lastCommittedMainFrameUri)}',
      );
      if (canGoBack) {
        await controller.goBack();
        return;
      }
      await _exitWebView();
    } finally {
      _handlingBack = false;
    }
  }

  @override
  void dispose() {
    _webViewFocusNode.removeListener(_handleWebViewFocusChanged);
    _findFocusNode.removeListener(_onFindFocusChanged);
    _webViewFocusNode.dispose();
    _backButtonFocusNode.dispose();
    _findController.dispose();
    _findFocusNode.dispose();
    _findInteractionController.dispose();
    super.dispose();
  }

  void _openFindBar() {
    setState(() {
      _showFindBar = true;
    });
    _deactivateTvCursor();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _findFocusNode.requestFocus();
      _findController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _findController.text.length,
      );
    });
  }

  Future<void> _closeFindBar() async {
    await _findInteractionController.clearMatches();
    if (!mounted) {
      return;
    }
    setState(() {
      _showFindBar = false;
      _findController.clear();
      _findActiveMatch = 0;
      _findTotalMatches = 0;
    });
    _webViewFocusNode.requestFocus();
  }

  Future<void> _searchInPage(String query) async {
    final text = query.trim();
    if (text.isEmpty) {
      await _findInteractionController.clearMatches();
      if (mounted) {
        setState(() {
          _findActiveMatch = 0;
          _findTotalMatches = 0;
        });
      }
      return;
    }
    await _findInteractionController.findAll(find: text);
  }

  Future<void> _findNext() async {
    if (_findController.text.trim().isEmpty) {
      return;
    }
    await _findInteractionController.findNext(forward: true);
  }

  Future<void> _findPrevious() async {
    if (_findController.text.trim().isEmpty) {
      return;
    }
    await _findInteractionController.findNext(forward: false);
  }

  bool _isTvCursorActivationKey(LogicalKeyboardKey key) {
    return TvActivationKeys.isActivationKey(key);
  }

  KeyEventResult _handleArrow(LogicalKeyboardKey key, {required bool repeat}) {
    final isTv = DeviceProfileService.instance.isAndroidTv;
    final useRemoteScroll =
        DeviceProfileService.instance.prefersDpadNavigation;
    if (!useRemoteScroll) {
      return KeyEventResult.ignored;
    }

    if (!repeat || _heldDirection != key) {
      _heldMoves = 0;
      _heldDirection = key;
    } else {
      _heldMoves++;
    }
    final step = _acceleratedStep();

    if (isTv && _webViewFocusNode.hasFocus) {
      switch (key) {
        case LogicalKeyboardKey.arrowUp:
          _moveTvCursor(0, -step);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowDown:
          _moveTvCursor(0, step);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowLeft:
          _moveTvCursor(-step, 0);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowRight:
          _moveTvCursor(step, 0);
          return KeyEventResult.handled;
        default:
          break;
      }
    }

    switch (key) {
      case LogicalKeyboardKey.arrowUp:
        _webViewController?.evaluateJavascript(
          source: 'window.scrollBy(0, -200)',
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _webViewController?.evaluateJavascript(
          source: 'window.scrollBy(0, 200)',
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _webViewController?.evaluateJavascript(
          source: 'window.scrollBy(-200, 0)',
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _webViewController?.evaluateJavascript(
          source: 'window.scrollBy(200, 0)',
        );
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final isTv = DeviceProfileService.instance.isAndroidTv;
    final isCtrlOrMeta = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final repeat = event is KeyRepeatEvent;

    if (!repeat &&
        event.logicalKey == LogicalKeyboardKey.keyF &&
        isCtrlOrMeta) {
      _openFindBar();
      return KeyEventResult.handled;
    }
    if (!repeat && event.logicalKey == LogicalKeyboardKey.slash) {
      _openFindBar();
      return KeyEventResult.handled;
    }
    if (!repeat && _isTvCursorActivationKey(event.logicalKey)) {
      if (_showFindBar && _findFocusNode.hasFocus) {
        if (isShift) {
          _findPrevious();
        } else {
          _findNext();
        }
        return KeyEventResult.handled;
      }
      if (isTv && _webViewFocusNode.hasFocus) {
        _clickTvCursor();
        return KeyEventResult.handled;
      }
    }

    switch (event.logicalKey) {
      case LogicalKeyboardKey.goBack:
      case LogicalKeyboardKey.escape:
        if (repeat) {
          return KeyEventResult.handled;
        }
        _handleBack();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
      case LogicalKeyboardKey.arrowDown:
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.arrowRight:
        return _handleArrow(event.logicalKey, repeat: repeat);
      default:
        return KeyEventResult.ignored;
    }
  }

  String _logUrl(Object? url, {int max = 240}) {
    final value = url?.toString() ?? 'null';
    if (value.length <= max) {
      return value;
    }
    return '${value.substring(0, max)}…';
  }

  bool _looksLikeMedia(String url) => _adBlocker.isMediaUrl(url);

  void _handleWebViewCreated(InAppWebViewController controller) {
    _webViewController = controller;
    AppLogger.webView(
      'created controller protection=${widget.compatibilityMode ? 'off' : 'on'}',
    );
    _logWebViewSettings(controller);
    if (!DeviceProfileService.instance.isAndroidTv) {
      _webViewFocusNode.requestFocus();
    }
  }

  Future<void> _logWebViewSettings(InAppWebViewController controller) async {
    try {
      final settings = await controller.getSettings();
      AppLogger.webView(
        'settings ua=${settings?.userAgent} '
        'mixed=${settings?.mixedContentMode} '
        'contentMode=${settings?.preferredContentMode} '
        'js=${settings?.javaScriptEnabled} '
        'mediaGesture=${settings?.mediaPlaybackRequiresUserGesture} '
        'inline=${settings?.allowsInlineMediaPlayback} '
        'multiWindow=${settings?.supportMultipleWindows}',
      );
    } catch (e) {
      AppLogger.webView('settings read failed: $e');
    }
  }

  void _focusWebViewForTv() {
    if (!DeviceProfileService.instance.isAndroidTv || !mounted) {
      return;
    }
    _webViewFocusNode.requestFocus();
    _activateTvCursor();
    _showTvCursorHintIfNeeded();
  }

  Future<void> _handleLoadStart(
    InAppWebViewController controller,
    WebUri? url,
  ) async {
    AppLogger.webView('load start ${_logUrl(url ?? widget.item.url)}');
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoading = true;
      _loadingProgress = 0;
    });
  }

  Future<void> _handleLoadStop(
    InAppWebViewController controller,
    WebUri? url,
  ) async {
    AppLogger.webView('load stop ${_logUrl(url ?? widget.item.url)}');
    final committed = Uri.tryParse(url?.toString() ?? '');
    if (committed != null) {
      _lastCommittedMainFrameUri = committed;
      _lastCommittedAt = DateTime.now();
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }

    final title = await controller.getTitle();
    final isChallengePage = NavigationGuard.looksLikeCloudflareChallenge(title);

    if (isChallengePage) {
      AppLogger.webView(
        'skip inject scripts — Cloudflare challenge title="$title"',
      );
      if (DeviceProfileService.instance.isAndroidTv) {
        await _injectTvCursorHelpers(controller);
      }
    } else {
      await _injectPageHelpers(
        controller,
        committed: committed,
        includeProtectionScripts: !widget.compatibilityMode,
      );
    }

    if (title != null && title.isNotEmpty && mounted) {
      setState(() => _currentTitle = title);
    }

    await _persistCookies();

    if (DeviceProfileService.instance.isAndroidTv) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusWebViewForTv();
      });
    }
  }

  Future<void> _injectPageHelpers(
    InAppWebViewController controller, {
    required Uri? committed,
    required bool includeProtectionScripts,
  }) async {
    final isTv = DeviceProfileService.instance.isAndroidTv;
    final onAllowedExternal = committed != null &&
        NavigationGuard.isOnAllowedExternalSite(
          sheetItemUrl: widget.item.url,
          allowedUrls: widget.item.allowedUrls,
          uri: committed,
        );

    AppLogger.webView(
      'inject helpers protection=$includeProtectionScripts '
      'allowedExternal=$onAllowedExternal tv=$isTv '
      'url=${_logUrl(committed)}',
    );
    if (includeProtectionScripts) {
      await controller.evaluateJavascript(
        source: AdBlockerService.antiAutomationPatchJs,
      );
      if (!onAllowedExternal) {
        await controller.evaluateJavascript(
          source: AdBlockerService.adHidingJs,
        );
      }
    }

    if (isTv) {
      await _injectTvCursorHelpers(controller);
    } else {
      await controller.evaluateJavascript(
        source: AdBlockerService.tvNavigationJs,
      );
    }
  }

  Future<void> _injectTvCursorHelpers(InAppWebViewController controller) async {
    await controller.evaluateJavascript(
      source: AdBlockerService.tvFocusOutlineJs,
    );
    await controller.evaluateJavascript(
      source: AdBlockerService.tvVirtualCursorJs,
    );
    await controller.evaluateJavascript(
      source: AdBlockerService.jsTvCursorActivate,
    );
    _syncTvCursorToJs();
  }

  void _handleProgressChanged(InAppWebViewController controller, int progress) {
    if (progress == 0 || progress == 100 || progress % 25 == 0) {
      AppLogger.webView('progress $progress%');
    }
    if (!mounted) {
      return;
    }
    setState(() => _loadingProgress = progress.toDouble());
  }

  Future<void> _handleVisitedHistory(
    InAppWebViewController controller,
    WebUri? url,
    bool? isReload,
  ) async {
    AppLogger.webView(
      'history ${_logUrl(url)} reload=${isReload == true}',
    );
  }

  void _handleConsoleMessage(
    InAppWebViewController controller,
    ConsoleMessage consoleMessage,
  ) {
    AppLogger.webView(
      'console ${consoleMessage.messageLevel} ${consoleMessage.message}',
    );
  }

  void _handleReceivedHttpError(
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceResponse errorResponse,
  ) {
    AppLogger.webView(
      'http error ${errorResponse.statusCode} '
      '${errorResponse.reasonPhrase ?? ''} '
      'mainFrame=${request.isForMainFrame} '
      '${_logUrl(request.url)}',
    );
  }

  void _handleRenderProcessGone(
    InAppWebViewController controller,
    RenderProcessGoneDetail detail,
  ) {
    AppLogger.webView(
      'render process gone crash=${detail.didCrash} '
      'priority=${detail.rendererPriorityAtExit}',
    );
  }

  void _handleLoadResource(
    InAppWebViewController controller,
    LoadedResource resource,
  ) {
    final url = resource.url?.toString() ?? '';
    if (!_looksLikeMedia(url) && resource.initiatorType != 'video') {
      return;
    }
    AppLogger.webView(
      'media resource type=${resource.initiatorType} '
      'ms=${resource.duration?.toStringAsFixed(0)} '
      '${_logUrl(url)}',
    );
  }

  void _handleReceivedError(
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceError error,
  ) {
    AppLogger.webView(
      'load error type=${error.type} ${error.description} '
      'mainFrame=${request.isForMainFrame} ${_logUrl(request.url)}',
    );
    if (request.isForMainFrame != true) {
      return;
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Page failed to load: ${error.description}',
        ),
        action: SnackBarAction(
          label: 'Retry',
          onPressed: () => controller.reload(),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<PermissionResponse?> _handlePermissionRequest(
    InAppWebViewController controller,
    PermissionRequest permissionRequest,
  ) async {
    final grantMedia = permissionRequest.resources.contains(
      PermissionResourceType.PROTECTED_MEDIA_ID,
    );
    AppLogger.webView(
      'permission origin=${permissionRequest.origin} '
      'resources=${permissionRequest.resources} '
      'action=${grantMedia ? 'GRANT' : 'DENY'}',
    );
    return PermissionResponse(
      resources: permissionRequest.resources,
      action: grantMedia
          ? PermissionResponseAction.GRANT
          : PermissionResponseAction.DENY,
    );
  }

  Future<void> _openInExternalBrowser() async {
    final raw = _lastCommittedMainFrameUri?.toString() ?? widget.item.url;
    final uri = Uri.tryParse(raw);
    if (uri == null) {
      return;
    }
    await _persistCookies();
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open in your system browser.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<bool> _handleCreateWindow(
    InAppWebViewController controller,
    CreateWindowAction createWindowAction,
  ) async {
    final raw = createWindowAction.request.url?.toString() ?? '';
    final popupUri = Uri.tryParse(raw);
    if (popupUri == null || raw.isEmpty) {
      AppLogger.webView('popup blocked — no URL');
      return false;
    }

    if (NavigationGuard.isNavigationAllowed(
      sheetItemUrl: widget.item.url,
      allowedUrls: widget.item.allowedUrls,
      target: popupUri,
    )) {
      AppLogger.webView('popup allowed → load in main frame ${_logUrl(raw)}');
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(raw)),
      );
      return false;
    }

    AppLogger.webView('popup blocked ${_logUrl(raw)}');
    return false;
  }

  Future<NavigationActionPolicy> _handleNavigationOverride(
    InAppWebViewController controller,
    NavigationAction navigationAction,
  ) async {
    final targetUri = Uri.tryParse(
      navigationAction.request.url?.toString() ?? '',
    );
    final navigationAllowed = targetUri != null &&
        NavigationGuard.isNavigationAllowed(
          sheetItemUrl: widget.item.url,
          allowedUrls: widget.item.allowedUrls,
          target: targetUri,
        );
    final navSummary =
        'mainFrame=${navigationAction.isForMainFrame} '
        'gesture=${navigationAction.hasGesture} '
        'redirect=${navigationAction.isRedirect} '
        '${_logUrl(navigationAction.request.url)}';

    if (targetUri != null &&
        navigationAction.isForMainFrame &&
        NavigationGuard.shouldBlockMainFrameNavigation(
          sheetItemUrl: widget.item.url,
          allowedUrls: widget.item.allowedUrls,
          previous: _lastCommittedMainFrameUri,
          previousAt: _lastCommittedAt,
          navigationAction: navigationAction,
          target: targetUri,
        )) {
      final bounceToEntry = NavigationGuard.isScriptedBounceToSheetEntry(
        sheetItemUrl: widget.item.url,
        allowedUrls: widget.item.allowedUrls,
        previous: _lastCommittedMainFrameUri,
        previousAt: _lastCommittedAt,
        hasGesture: navigationAction.hasGesture,
        target: targetUri,
      );
      AppLogger.webView(
        bounceToEntry
            ? 'nav CANCEL scripted bounce $navSummary from ${_logUrl(_lastCommittedMainFrameUri)}'
            : navigationAllowed
                ? 'nav CANCEL scripted redirect $navSummary from ${_logUrl(_lastCommittedMainFrameUri)}'
                : 'nav CANCEL off-site $navSummary',
      );
      if (mounted) {
        final sheetHost =
            Uri.tryParse(widget.item.url)?.host ?? 'this catalog site';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              bounceToEntry
                  ? 'Blocked an automatic redirect back to the catalog page.'
                  : navigationAllowed
                      ? 'Blocked an automatic redirect away from this page.'
                      : 'Only $sheetHost and allowed redirect sites from your sheet are permitted.',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return NavigationActionPolicy.CANCEL;
    }

    if (widget.compatibilityMode || navigationAllowed) {
      if (navigationAction.isForMainFrame) {
        AppLogger.webView('nav ALLOW $navSummary');
      }
      return NavigationActionPolicy.ALLOW;
    }

    if (navigationAction.isForMainFrame &&
        _shouldCancelTopLevelNavigation(navigationAction.request.url)) {
      AppLogger.webView('nav CANCEL top-level $navSummary');
      return NavigationActionPolicy.CANCEL;
    }

    final url = navigationAction.request.url?.toString() ?? '';
    if (_adBlocker.shouldBlock(url)) {
      AppLogger.webView('nav CANCEL domain filter $navSummary');
      return NavigationActionPolicy.CANCEL;
    }
    if (navigationAction.isForMainFrame) {
      AppLogger.webView('nav ALLOW $navSummary');
    }
    return NavigationActionPolicy.ALLOW;
  }

  Future<WebResourceResponse?> _interceptRequest(
    InAppWebViewController controller,
    WebResourceRequest request,
  ) async {
    if (widget.compatibilityMode) {
      return null;
    }
    final url = request.url.toString();
    // Media and images must return immediately. Logging or domain scans on
    // this path stall HLS segments and produce audio-only playback.
    if (_adBlocker.shouldSkipIntercept(url)) {
      return null;
    }
    if (_adBlocker.shouldBlock(url)) {
      AppLogger.webView('intercept BLOCK ${_logUrl(url)}');
      return WebResourceResponse(
        contentType: 'text/plain',
        statusCode: 204,
        reasonPhrase: 'No Content',
        headers: {'Content-Length': '0'},
        data: Uint8List(0),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          return;
        }
        await _handleBack();
      },
      child: Scaffold(
        backgroundColor: ClearCastColors.scaffold,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final isTv = DeviceProfileService.instance.isAndroidTv;
            final r = ResponsiveLayout(constraints.biggest, isTv: isTv);
            return TvNavigationScope(
              child: Column(
                children: [
                  _buildTopBar(r),
                  if (_showFindBar) _buildFindBar(r),
                  if (_isLoading)
                    LinearProgressIndicator(
                      value:
                          _loadingProgress > 0 ? _loadingProgress / 100 : null,
                      backgroundColor: ClearCastColors.surfaceMuted,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        ClearCastColors.lime,
                      ),
                      minHeight:
                          (r.toolbarHeight() * 0.05).clamp(2.0, 5.0).toDouble(),
                    ),
                  Expanded(
                    child: !_cookiesReady
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: ClearCastColors.lime,
                            ),
                          )
                        : Focus(
                            focusNode: _webViewFocusNode,
                            onKeyEvent: _handleKeyEvent,
                            child: LayoutBuilder(
                              builder: (context, webConstraints) {
                                final webSize = webConstraints.biggest;
                                if (isTv && webSize.width > 0) {
                                  _ensureTvCursor(webSize);
                                }
                                final useIntercept =
                                    !widget.compatibilityMode && !isTv;
                                if (widget.compatibilityMode) {
                                  return PlainWebView(
                                    url: widget.item.url,
                                    settings: _adBlocker.webViewSettings(
                                      compatibilityMode: true,
                                    ),
                                    findInteractionController:
                                        _findInteractionController,
                                    onWebViewCreated: _handleWebViewCreated,
                                    onLoadStart: _handleLoadStart,
                                    onLoadStop: _handleLoadStop,
                                    onProgressChanged: _handleProgressChanged,
                                    onUpdateVisitedHistory:
                                        _handleVisitedHistory,
                                    shouldOverrideUrlLoading:
                                        _handleNavigationOverride,
                                    onCreateWindow: _handleCreateWindow,
                                    onPermissionRequest:
                                        _handlePermissionRequest,
                                    onReceivedError: _handleReceivedError,
                                    onConsoleMessage: _handleConsoleMessage,
                                    onReceivedHttpError:
                                        _handleReceivedHttpError,
                                    onRenderProcessGone:
                                        _handleRenderProcessGone,
                                    onLoadResource: _handleLoadResource,
                                  );
                                }
                                return InAppWebView(
                                  findInteractionController:
                                      _findInteractionController,
                                  initialUrlRequest: URLRequest(
                                    url: WebUri(widget.item.url),
                                  ),
                                  initialSettings: _adBlocker.webViewSettings(
                                    compatibilityMode: false,
                                  ),
                                  onWebViewCreated: _handleWebViewCreated,
                                  onLoadStart: _handleLoadStart,
                                  onLoadStop: _handleLoadStop,
                                  onProgressChanged: _handleProgressChanged,
                                  onUpdateVisitedHistory:
                                      _handleVisitedHistory,
                                  onCreateWindow: _handleCreateWindow,
                                  shouldOverrideUrlLoading:
                                      _handleNavigationOverride,
                                  shouldInterceptRequest: useIntercept
                                      ? _interceptRequest
                                      : null,
                                  onPermissionRequest:
                                      _handlePermissionRequest,
                                  onReceivedError: _handleReceivedError,
                                  onConsoleMessage: _handleConsoleMessage,
                                  onReceivedHttpError:
                                      _handleReceivedHttpError,
                                  onRenderProcessGone:
                                      _handleRenderProcessGone,
                                  onLoadResource: _handleLoadResource,
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTopBar(ResponsiveLayout r) {
    final isTv = DeviceProfileService.instance.isAndroidTv;
    final badgeFont = r.toolbarBadgeFontSize();
    final badgeIcon = badgeFont + 3;
    return Container(
      height: r.toolbarHeight(),
      padding: EdgeInsets.symmetric(horizontal: r.toolbarHorizontalPadding()),
      decoration: BoxDecoration(
        color: ClearCastColors.surface,
        border: Border(
          bottom: BorderSide(
            color: ClearCastColors.darkGreen.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          _TVButton(
            layout: r,
            icon: Icons.arrow_back_rounded,
            label: 'Back',
            focusNode: _backButtonFocusNode,
            onToolbarFocus: _deactivateTvCursor,
            onKeyEvent: (node, event) {
              if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
                  event.logicalKey == LogicalKeyboardKey.arrowDown &&
                  isTv) {
                _focusWebViewForTv();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            onTap: _handleBack,
          ),
          SizedBox(width: (r.w * 0.008).clamp(8.0, 16.0)),
          _TVButton(
            layout: r,
            icon: Icons.home_rounded,
            label: 'Home',
            onToolbarFocus: _deactivateTvCursor,
            onTap: _exitWebView,
          ),
          SizedBox(width: (r.w * 0.008).clamp(8.0, 16.0)),
          _TVButton(
            layout: r,
            icon: Icons.refresh_rounded,
            label: 'Reload',
            onToolbarFocus: _deactivateTvCursor,
            onTap: () => _webViewController?.reload(),
          ),
          if (!isTv) ...[
            SizedBox(width: (r.w * 0.008).clamp(8.0, 16.0)),
            _TVButton(
              layout: r,
              icon: Icons.open_in_browser_rounded,
              label: 'Browser',
              onToolbarFocus: _deactivateTvCursor,
              onTap: _openInExternalBrowser,
            ),
          ],
          SizedBox(width: (r.w * 0.008).clamp(8.0, 16.0)),
          _TVButton(
            layout: r,
            icon: Icons.find_in_page_rounded,
            label: 'Find',
            onToolbarFocus: _deactivateTvCursor,
            onTap: _openFindBar,
          ),
          if (isTv) ...[
            SizedBox(width: (r.w * 0.008).clamp(8.0, 16.0)),
            _TVButton(
              layout: r,
              icon: Icons.ads_click_rounded,
              label: 'Page',
              onToolbarFocus: _deactivateTvCursor,
              onTap: _focusWebViewForTv,
            ),
          ],
          SizedBox(width: (r.w * 0.01).clamp(10.0, 20.0)),
          Expanded(
            child: Text(
              _currentTitle,
              style: TextStyle(
                color: Colors.white70,
                fontSize: r.toolbarTitleSize(),
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_sessionCookieCount > 0)
            Padding(
              padding: EdgeInsets.only(right: (r.w * 0.008).clamp(6.0, 12.0)),
              child: Tooltip(
                message:
                    '$_sessionCookieCount saved session cookie(s) for this site',
                child: Icon(
                  Icons.cookie_rounded,
                  color: Colors.white.withValues(alpha: 0.55),
                  size: badgeIcon,
                ),
              ),
            ),
          if (r.isCompactWidth)
            Tooltip(
              message: widget.compatibilityMode
                  ? 'Protection off — no blocking or injected scripts'
                  : 'Protection on — blocking active',
              child: Icon(
                widget.compatibilityMode
                    ? Icons.shield_outlined
                    : Icons.shield_rounded,
                color: widget.compatibilityMode
                    ? Colors.amberAccent
                    : ClearCastColors.lime,
                size: badgeIcon,
              ),
            )
          else
            Container(
              padding: r.toolbarBadgePadding(),
              decoration: BoxDecoration(
                color: widget.compatibilityMode
                    ? Colors.amberAccent.withValues(alpha: 0.1)
                    : ClearCastColors.lime.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: widget.compatibilityMode
                      ? Colors.amberAccent.withValues(alpha: 0.35)
                      : ClearCastColors.lime.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.compatibilityMode
                        ? Icons.shield_outlined
                        : Icons.shield_rounded,
                    color: widget.compatibilityMode
                        ? Colors.amberAccent
                        : ClearCastColors.lime,
                    size: badgeIcon,
                  ),
                  SizedBox(width: (r.w * 0.004).clamp(4.0, 8.0)),
                  Text(
                    widget.compatibilityMode
                        ? 'PROTECTION OFF'
                        : 'PROTECTION ON',
                    style: TextStyle(
                      color: widget.compatibilityMode
                          ? Colors.amberAccent
                          : ClearCastColors.lime,
                      fontSize: badgeFont,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFindBar(ResponsiveLayout r) {
    final displayMatch = _findTotalMatches == 0
        ? 0
        : (_findActiveMatch + 1).clamp(1, _findTotalMatches);
    return Container(
      color: ClearCastColors.surface,
      padding: EdgeInsets.fromLTRB(
        r.toolbarHorizontalPadding(),
        (r.h * 0.008).clamp(6.0, 10.0),
        r.toolbarHorizontalPadding(),
        (r.h * 0.01).clamp(8.0, 12.0),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: ClearCastColors.scaffoldDeep,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _findFocusNode.hasFocus
                ? ClearCastColors.lime
                : Colors.white.withValues(alpha: 0.2),
            width: _findFocusNode.hasFocus ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          children: [
            Icon(
              Icons.find_in_page_rounded,
              color: _findFocusNode.hasFocus
                  ? ClearCastColors.lime
                  : Colors.white.withValues(alpha: 0.6),
              size: r.tvButtonIconSize(),
            ),
            SizedBox(width: (r.w * 0.006).clamp(6.0, 12.0)),
            Expanded(
              child: TextField(
                controller: _findController,
                focusNode: _findFocusNode,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: r.toolbarTitleSize(),
                ),
                cursorColor: ClearCastColors.lime,
                textInputAction: TextInputAction.search,
                onChanged: _searchInPage,
                onSubmitted: (_) => _findNext(),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  hintText:
                      'Find in page... (Enter next, Shift+Enter previous, Esc close)',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: r.toolbarTitleSize(),
                  ),
                ),
              ),
            ),
            SizedBox(width: (r.w * 0.006).clamp(6.0, 12.0)),
            Text(
              _findTotalMatches == 0 ? '0' : '$displayMatch/$_findTotalMatches',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: r.toolbarBadgeFontSize(),
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(width: (r.w * 0.005).clamp(4.0, 10.0)),
            IconButton(
              onPressed: _findPrevious,
              tooltip: 'Previous match',
              icon: Icon(
                Icons.keyboard_arrow_up_rounded,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
            IconButton(
              onPressed: _findNext,
              tooltip: 'Next match',
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
            IconButton(
              onPressed: _closeFindBar,
              tooltip: 'Close find',
              icon: Icon(
                Icons.close_rounded,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TVButton extends StatefulWidget {
  final ResponsiveLayout layout;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onToolbarFocus;
  final FocusNode? focusNode;
  final KeyEventResult Function(FocusNode node, KeyEvent event)? onKeyEvent;

  const _TVButton({
    required this.layout,
    required this.icon,
    required this.label,
    required this.onTap,
    this.onToolbarFocus,
    this.focusNode,
    this.onKeyEvent,
  });

  @override
  State<_TVButton> createState() => _TVButtonState();
}

class _TVButtonState extends State<_TVButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.layout;
    return TvFocusable(
      focusNode: widget.focusNode,
      onPressed: widget.onTap,
      onKeyEvent: widget.onKeyEvent,
      onFocusChange: (v) {
        setState(() => _focused = v);
        if (v) {
          widget.onToolbarFocus?.call();
        }
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: r.tvButtonPadding(),
          decoration: BoxDecoration(
            color: _focused
                ? ClearCastColors.lime.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _focused
                  ? ClearCastColors.lime
                  : Colors.white.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                color: _focused
                    ? ClearCastColors.lime
                    : Colors.white.withValues(alpha: 0.6),
                size: r.tvButtonIconSize(),
              ),
              SizedBox(width: (r.w * 0.004).clamp(4.0, 10.0)),
              Text(
                widget.label,
                style: TextStyle(
                  color: _focused
                      ? ClearCastColors.lime
                      : Colors.white.withValues(alpha: 0.6),
                  fontSize: r.tvButtonLabelSize(),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
