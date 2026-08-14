import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class PlainWebView extends StatelessWidget {
  final String url;
  final InAppWebViewSettings settings;
  final FindInteractionController? findInteractionController;
  final void Function(InAppWebViewController controller) onWebViewCreated;
  final void Function(InAppWebViewController controller, WebUri? url) onLoadStart;
  final void Function(InAppWebViewController controller, WebUri? url) onLoadStop;
  final void Function(InAppWebViewController controller, int progress)
      onProgressChanged;
  final void Function(
    InAppWebViewController controller,
    WebUri? url,
    bool? isReload,
  )? onUpdateVisitedHistory;
  final Future<NavigationActionPolicy?> Function(
    InAppWebViewController controller,
    NavigationAction navigationAction,
  )? shouldOverrideUrlLoading;
  final Future<bool?> Function(
    InAppWebViewController controller,
    CreateWindowAction createWindowAction,
  )? onCreateWindow;
  final Future<PermissionResponse?> Function(
    InAppWebViewController controller,
    PermissionRequest permissionRequest,
  )? onPermissionRequest;
  final void Function(
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceError error,
  ) onReceivedError;
  final void Function(
    InAppWebViewController controller,
    ConsoleMessage consoleMessage,
  )? onConsoleMessage;
  final void Function(
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceResponse errorResponse,
  )? onReceivedHttpError;
  final void Function(
    InAppWebViewController controller,
    RenderProcessGoneDetail detail,
  )? onRenderProcessGone;
  final void Function(
    InAppWebViewController controller,
    LoadedResource resource,
  )? onLoadResource;

  const PlainWebView({
    super.key,
    required this.url,
    required this.settings,
    this.findInteractionController,
    required this.onWebViewCreated,
    required this.onLoadStart,
    required this.onLoadStop,
    required this.onProgressChanged,
    this.onUpdateVisitedHistory,
    this.shouldOverrideUrlLoading,
    this.onCreateWindow,
    this.onPermissionRequest,
    required this.onReceivedError,
    this.onConsoleMessage,
    this.onReceivedHttpError,
    this.onRenderProcessGone,
    this.onLoadResource,
  });

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: settings,
      findInteractionController: findInteractionController,
      onWebViewCreated: onWebViewCreated,
      onLoadStart: onLoadStart,
      onLoadStop: onLoadStop,
      onProgressChanged: onProgressChanged,
      onUpdateVisitedHistory: onUpdateVisitedHistory,
      shouldOverrideUrlLoading: shouldOverrideUrlLoading,
      onCreateWindow: onCreateWindow,
      onPermissionRequest: onPermissionRequest,
      onReceivedError: onReceivedError,
      onConsoleMessage: onConsoleMessage,
      onReceivedHttpError: onReceivedHttpError,
      onRenderProcessGone: onRenderProcessGone,
      onLoadResource: onLoadResource,
    );
  }
}
