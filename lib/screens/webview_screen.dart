import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../layout/responsive_layout.dart';
import '../theme/clearcast_colors.dart';
import '../models/url_item.dart';
import '../services/ad_blocker_service.dart';

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

  @override
  void initState() {
    super.initState();
    _adBlocker.initialize();
    _currentTitle = widget.item.title;
    _findInteractionController = FindInteractionController(
      onFindResultReceived: (controller, activeMatchOrdinal, numberOfMatches, isDoneCounting) async {
        if (!mounted) {
          return;
        }
        setState(() {
          _findActiveMatch = activeMatchOrdinal;
          _findTotalMatches = numberOfMatches;
        });
      },
    );
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
    final isCtrlOrMeta =
        HardwareKeyboard.instance.isControlPressed ||
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
          if (shouldPop && mounted) Navigator.of(context).pop();
        });
        return KeyEventResult.handled;

      // D-pad scroll inside WebView via JS
      case LogicalKeyboardKey.arrowUp:
        _webViewController?.evaluateJavascript(source: 'window.scrollBy(0, -200)');
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _webViewController?.evaluateJavascript(source: 'window.scrollBy(0, 200)');
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _webViewController?.evaluateJavascript(source: 'window.scrollBy(-200, 0)');
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _webViewController?.evaluateJavascript(source: 'window.scrollBy(200, 0)');
        return KeyEventResult.handled;

      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: ClearCastColors.scaffold,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final r = ResponsiveLayout(constraints.biggest);
            return Column(
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
              child: Focus(
                focusNode: _webViewFocusNode,
                onKeyEvent: _handleKeyEvent,
                child: InAppWebView(
                  findInteractionController: _findInteractionController,
                  initialUrlRequest: URLRequest(
                    url: WebUri(widget.item.url),
                  ),
                  initialSettings: _adBlocker.webViewSettings(
                    compatibilityMode: widget.compatibilityMode,
                  ),
                  onWebViewCreated: (controller) {
                    _webViewController = controller;
                    _webViewFocusNode.requestFocus();
                  },
                  onLoadStart: (controller, url) {
                    setState(() {
                      _isLoading = true;
                      _loadingProgress = 0;
                    });
                  },
                  onLoadStop: (controller, url) async {
                    setState(() => _isLoading = false);

                    if (!widget.compatibilityMode) {
                      // Inject ad-hiding JS
                      await controller.evaluateJavascript(
                        source: AdBlockerService.adHidingJs,
                      );
                    }

                    // Inject TV navigation JS
                    await controller.evaluateJavascript(
                      source: AdBlockerService.tvNavigationJs,
                    );

                    // Update back button state
                    final canGoBack = await controller.canGoBack();
                    setState(() => _canGoBack = canGoBack);

                    // Update title
                    final title = await controller.getTitle();
                    if (title != null && title.isNotEmpty) {
                      setState(() => _currentTitle = title);
                    }
                  },
                  onProgressChanged: (controller, progress) {
                    setState(() => _loadingProgress = progress.toDouble());
                  },
                  // ─── AD BLOCKING: intercept every request ───
                  shouldOverrideUrlLoading: (controller, navigationAction) async {
                    if (widget.compatibilityMode) {
                      return NavigationActionPolicy.ALLOW;
                    }
                    final url = navigationAction.request.url?.toString() ?? '';
                    if (_adBlocker.shouldBlock(url)) {
                      return NavigationActionPolicy.CANCEL;
                    }
                    return NavigationActionPolicy.ALLOW;
                  },
                  shouldInterceptRequest: (controller, request) async {
                    if (widget.compatibilityMode) {
                      return null;
                    }
                    final url = request.url.toString();
                    if (_adBlocker.shouldBlock(url)) {
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
                  onReceivedError: (controller, request, error) {
                    if (widget.compatibilityMode) {
                      return;
                    }
                    // Silently ignore blocked resource errors.
                  },
                ),
              ),
            ),
              ],
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
            autofocus: false,
            onTap: () async {
              final shouldPop = await _onWillPop();
              if (shouldPop && mounted) Navigator.of(context).pop();
            },
          ),
          SizedBox(width: (r.w * 0.008).clamp(8.0, 16.0)),
          _TVButton(
            layout: r,
            icon: Icons.refresh_rounded,
            label: 'Reload',
            onTap: () => _webViewController?.reload(),
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
          if (r.isCompactWidth)
            Tooltip(
              message: widget.compatibilityMode
                  ? 'Compatibility mode enabled'
                  : 'Ad blocking active',
              child: Icon(
                widget.compatibilityMode
                    ? Icons.tune_rounded
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
                color: ClearCastColors.lime.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: ClearCastColors.lime.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.compatibilityMode
                        ? Icons.tune_rounded
                        : Icons.shield_rounded,
                    color: widget.compatibilityMode
                        ? Colors.amberAccent
                        : ClearCastColors.lime,
                    size: badgeIcon,
                  ),
                  SizedBox(width: (r.w * 0.004).clamp(4.0, 8.0)),
                  Text(
                    widget.compatibilityMode
                        ? 'COMPAT MODE'
                        : 'AD BLOCKED',
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
                  hintText: 'Find in page... (Enter next, Shift+Enter previous, Esc close)',
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
    return Focus(
      autofocus: widget.autofocus,
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
