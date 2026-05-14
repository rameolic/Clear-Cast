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
  bool _canGoBack = false;
  final FocusNode _webViewFocusNode = FocusNode();
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
  Uri? _pinnedAllowedPageUri;

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
    AppLogger.info(
      widget.compatibilityMode
          ? 'Opening WebView for ${widget.item.url} (protection OFF — no blocking or injected scripts)'
          : 'Opening WebView for ${widget.item.url}',
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
  }

  Future<void> _prepareCookies() async {
    final restored =
        await _cookieStorage.restoreForItem(widget.item.url);
    final stored = await _cookieStorage.storedCountForItem(widget.item.url);
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

  @override
  void dispose() {
    _webViewFocusNode.dispose();
    _findController.dispose();
    _findFocusNode.dispose();
    super.dispose();
  }

  void _openFindBar() {
    setState(() => _showFindBar = true);
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

  /// Handle hardware back button and D-pad back
  Future<bool> _onWillPop() async {
    if (_canGoBack && _webViewController != null) {
      await _webViewController!.goBack();
      return false;
    }
    return true;
  }

  /// Handle TV remote key events when WebView has focus
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final useRemoteScroll =
        DeviceProfileService.instance.prefersDpadNavigation;
    final isCtrlOrMeta = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    if (event.logicalKey == LogicalKeyboardKey.keyF && isCtrlOrMeta) {
      _openFindBar();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.slash) {
      _openFindBar();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_showFindBar && _findFocusNode.hasFocus) {
        if (isShift) {
          _findPrevious();
        } else {
          _findNext();
        }
        return KeyEventResult.handled;
      }
    }

    switch (event.logicalKey) {
      case LogicalKeyboardKey.goBack:
      case LogicalKeyboardKey.escape:
        if (_showFindBar) {
          _closeFindBar();
          return KeyEventResult.handled;
        }
        _onWillPop().then((shouldPop) {
          if (shouldPop && mounted) {
            _exitWebView();
          }
        });
        return KeyEventResult.handled;

      // D-pad scroll inside WebView via JS
      case LogicalKeyboardKey.arrowUp:
        if (!useRemoteScroll) return KeyEventResult.ignored;
        _webViewController?.evaluateJavascript(
            source: 'window.scrollBy(0, -200)');
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        if (!useRemoteScroll) return KeyEventResult.ignored;
        _webViewController?.evaluateJavascript(
            source: 'window.scrollBy(0, 200)');
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        if (!useRemoteScroll) return KeyEventResult.ignored;
        _webViewController?.evaluateJavascript(
            source: 'window.scrollBy(-200, 0)');
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        if (!useRemoteScroll) return KeyEventResult.ignored;
        _webViewController?.evaluateJavascript(
            source: 'window.scrollBy(200, 0)');
        return KeyEventResult.handled;

      default:
        return KeyEventResult.ignored;
    }
  }

  void _handleWebViewCreated(InAppWebViewController controller) {
    _webViewController = controller;
    if (!DeviceProfileService.instance.isAndroidTv) {
      _webViewFocusNode.requestFocus();
    }
  }

  Future<void> _handleLoadStart(
    InAppWebViewController controller,
    WebUri? url,
  ) async {
    final started = Uri.tryParse(url?.toString() ?? '');
    AppLogger.info('WebView load start: ${url?.toString() ?? widget.item.url}');

    if (started != null &&
        NavigationGuard.isScriptedBounceToSheetEntry(
          sheetItemUrl: widget.item.url,
          allowedUrls: widget.item.allowedUrls,
          previous: _lastCommittedMainFrameUri,
          previousAt: _lastCommittedAt,
          hasGesture: false,
          target: started,
        )) {
      final restore = _pinnedAllowedPageUri ?? _lastCommittedMainFrameUri;
      AppLogger.warn(
        'Stopped catalog bounce in onLoadStart: ${restore.toString()} -> ${started.toString()}',
      );
      await controller.stopLoading();
      if (restore != null) {
        await controller.loadUrl(
          urlRequest: URLRequest(url: WebUri(restore.toString())),
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Blocked an automatic redirect back to the catalog page.',
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingProgress = 0;
    });
  }

  Future<void> _handleLoadStop(InAppWebViewController controller, WebUri? url) async {
    AppLogger.info('WebView load finished: ${url?.toString() ?? widget.item.url}');
    final committed = Uri.tryParse(url?.toString() ?? '');
    if (committed != null) {
      _lastCommittedMainFrameUri = committed;
      _lastCommittedAt = DateTime.now();
      if (NavigationGuard.isOnAllowedExternalSite(
        sheetItemUrl: widget.item.url,
        allowedUrls: widget.item.allowedUrls,
        uri: committed,
      )) {
        _pinnedAllowedPageUri = committed;
      }
    }
    setState(() => _isLoading = false);

    final title = await controller.getTitle();
    final isChallengePage = NavigationGuard.looksLikeCloudflareChallenge(title);

    if (isChallengePage) {
      AppLogger.info(
        'Skipping injected scripts while Cloudflare challenge is active',
      );
    } else {
      await _injectPageHelpers(
        controller,
        committed: committed,
        includeProtectionScripts: !widget.compatibilityMode,
      );
    }

    final canGoBack = await controller.canGoBack();
    setState(() => _canGoBack = canGoBack);

    if (title != null && title.isNotEmpty) {
      setState(() => _currentTitle = title);
    }

    await _persistCookies();
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
      await controller.evaluateJavascript(
        source: AdBlockerService.tvFocusOutlineJs,
      );
    } else {
      await controller.evaluateJavascript(
        source: AdBlockerService.tvNavigationJs,
      );
    }
  }

  void _handleProgressChanged(InAppWebViewController controller, int progress) {
    setState(() => _loadingProgress = progress.toDouble());
  }

  Future<void> _handleVisitedHistory(
    InAppWebViewController controller,
    WebUri? url,
    bool? isReload,
  ) async {
    // History updates are tracked via onLoadStop committed URL.
  }

  void _handleReceivedError(
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceError error,
  ) {
    if (widget.compatibilityMode) {
      return;
    }
    // Silently ignore blocked resource errors.
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
      AppLogger.warn('Blocked popup window without a URL');
      return false;
    }

    if (NavigationGuard.isNavigationAllowed(
      sheetItemUrl: widget.item.url,
      allowedUrls: widget.item.allowedUrls,
      target: popupUri,
    )) {
      AppLogger.info('Loading allowed popup URL in main frame: $raw');
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(raw)),
      );
      return false;
    }

    AppLogger.warn('Blocked popup window request: $raw');
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
      AppLogger.warn(
        bounceToEntry
            ? 'Blocked scripted bounce back to catalog URL from ${_lastCommittedMainFrameUri.toString()} to ${targetUri.toString()}'
            : navigationAllowed
                ? 'Blocked scripted redirect from ${_lastCommittedMainFrameUri.toString()} to ${targetUri.toString()}'
                : 'Blocked off-site navigation from ${widget.item.url} to ${targetUri.toString()}',
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
      return NavigationActionPolicy.ALLOW;
    }

    if (navigationAction.isForMainFrame &&
        _shouldCancelTopLevelNavigation(navigationAction.request.url)) {
      AppLogger.warn(
        'Blocked top-level navigation: ${navigationAction.request.url?.toString() ?? 'unknown'}',
      );
      return NavigationActionPolicy.CANCEL;
    }

    final url = navigationAction.request.url?.toString() ?? '';
    if (_adBlocker.shouldBlock(url)) {
      AppLogger.warn('Blocked navigation by domain filter: $url');
      return NavigationActionPolicy.CANCEL;
    }
    return NavigationActionPolicy.ALLOW;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (!context.mounted) {
          return;
        }
        if (shouldPop) {
          await _persistCookies();
          if (context.mounted) {
            Navigator.of(context).pop();
          }
        }
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
                    value: _loadingProgress > 0 ? _loadingProgress / 100 : null,
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
                    child: widget.compatibilityMode
                        ? PlainWebView(
                            url: widget.item.url,
                            settings: _adBlocker.webViewSettings(
                              compatibilityMode: true,
                            ),
                            onWebViewCreated: _handleWebViewCreated,
                            onLoadStart: _handleLoadStart,
                            onLoadStop: _handleLoadStop,
                            onProgressChanged: _handleProgressChanged,
                            onUpdateVisitedHistory: _handleVisitedHistory,
                            shouldOverrideUrlLoading: _handleNavigationOverride,
                            onReceivedError: _handleReceivedError,
                          )
                        : InAppWebView(
                            findInteractionController: _findInteractionController,
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
                            onUpdateVisitedHistory: _handleVisitedHistory,
                            onCreateWindow: _handleCreateWindow,
                      shouldOverrideUrlLoading: _handleNavigationOverride,
                      shouldInterceptRequest: (controller, request) async {
                        final url = request.url.toString();
                        if (_adBlocker.shouldBlock(url)) {
                          AppLogger.warn('Blocked resource request: $url');
                          // Return empty response instead of the ad content
                          return WebResourceResponse(
                            contentType: 'text/plain',
                            statusCode: 204,
                            reasonPhrase: 'No Content',
                            headers: {'Content-Length': '0'},
                            data: Uint8List(0),
                          );
                        }
                        return null; // Allow the request
                      },
                      onReceivedError: _handleReceivedError,
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
            autofocus: DeviceProfileService.instance.isAndroidTv,
            onTap: () async {
              final shouldPop = await _onWillPop();
              if (shouldPop && mounted) {
                await _exitWebView();
              }
            },
          ),
          SizedBox(width: (r.w * 0.008).clamp(8.0, 16.0)),
          _TVButton(
            layout: r,
            icon: Icons.home_rounded,
            label: 'Home',
            onTap: _exitWebView,
          ),
          SizedBox(width: (r.w * 0.008).clamp(8.0, 16.0)),
          _TVButton(
            layout: r,
            icon: Icons.refresh_rounded,
            label: 'Reload',
            onTap: () => _webViewController?.reload(),
          ),
          SizedBox(width: (r.w * 0.008).clamp(8.0, 16.0)),
          _TVButton(
            layout: r,
            icon: Icons.open_in_browser_rounded,
            label: 'Browser',
            onTap: _openInExternalBrowser,
          ),
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
                    widget.compatibilityMode ? 'PROTECTION OFF' : 'PROTECTION ON',
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
              _findTotalMatches == 0
                  ? '0'
                  : '$_findActiveMatch/$_findTotalMatches',
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

/// Reusable TV-focusable button for the top bar
class _TVButton extends StatefulWidget {
  final ResponsiveLayout layout;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool autofocus;

  const _TVButton({
    required this.layout,
    required this.icon,
    required this.label,
    required this.onTap,
    this.autofocus = false,
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
      autofocus: widget.autofocus,
      onPressed: widget.onTap,
      onFocusChange: (v) => setState(() => _focused = v),
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
