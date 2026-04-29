import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../layout/responsive_layout.dart';
import '../theme/clearcast_colors.dart';
import '../models/url_item.dart';
import '../services/ad_blocker_service.dart';

class WebViewScreen extends StatefulWidget {
  final UrlItem item;

  const WebViewScreen({super.key, required this.item});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  InAppWebViewController? _webViewController;
  final AdBlockerService _adBlocker = AdBlockerService();
  bool _isLoading = true;
  double _loadingProgress = 0;
  String _currentTitle = '';
  bool _canGoBack = false;
  final FocusNode _webViewFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _adBlocker.initialize();
    _currentTitle = widget.item.title;
  }

  @override
  void dispose() {
    _webViewFocusNode.dispose();
    super.dispose();
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

    switch (event.logicalKey) {
      case LogicalKeyboardKey.goBack:
      case LogicalKeyboardKey.escape:
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
                  initialUrlRequest: URLRequest(
                    url: WebUri(widget.item.url),
                  ),
                  initialSettings: _adBlocker.webViewSettings,
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

                    // Inject ad-hiding JS
                    await controller.evaluateJavascript(
                      source: AdBlockerService.adHidingJs,
                    );

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
                    final url = navigationAction.request.url?.toString() ?? '';
                    if (_adBlocker.shouldBlock(url)) {
                      return NavigationActionPolicy.CANCEL;
                    }
                    return NavigationActionPolicy.ALLOW;
                  },
                  shouldInterceptRequest: (controller, request) async {
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
                    // Silently ignore blocked resource errors
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
              message: 'Ad blocking active',
              child: Icon(
                Icons.shield_rounded,
                color: ClearCastColors.lime,
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
                    Icons.shield_rounded,
                    color: ClearCastColors.lime,
                    size: badgeIcon,
                  ),
                  SizedBox(width: (r.w * 0.004).clamp(4.0, 8.0)),
                  Text(
                    'AD BLOCKED',
                    style: TextStyle(
                      color: ClearCastColors.lime,
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
