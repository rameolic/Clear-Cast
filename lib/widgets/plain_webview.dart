import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class PlainWebView extends StatelessWidget {
  final String url;
  final InAppWebViewSettings settings;
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
  final void Function(
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceError error,
  ) onReceivedError;

  const PlainWebView({
    super.key,
    required this.url,
    required this.settings,
    required this.onWebViewCreated,
    required this.onLoadStart,
    required this.onLoadStop,
    required this.onProgressChanged,
    this.onUpdateVisitedHistory,
    this.shouldOverrideUrlLoading,
    required this.onReceivedError,
  });

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: settings,
      onWebViewCreated: onWebViewCreated,
      onLoadStart: onLoadStart,
      onLoadStop: onLoadStop,
      onProgressChanged: onProgressChanged,
      onUpdateVisitedHistory: onUpdateVisitedHistory,
      shouldOverrideUrlLoading: shouldOverrideUrlLoading,
      onReceivedError: onReceivedError,
    );
  }
}
