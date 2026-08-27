import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../l10n/app_text.dart';

class ManagerWebAdminScreen extends StatefulWidget {
  final String entryUrl;

  const ManagerWebAdminScreen({super.key, required this.entryUrl});

  @override
  State<ManagerWebAdminScreen> createState() => _ManagerWebAdminScreenState();
}

class _ManagerWebAdminScreenState extends State<ManagerWebAdminScreen> {
  late final WebViewController _controller;
  int _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent('TranvikoMobileWebView/1.0 Android')
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            if (mounted) setState(() => _progress = value);
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _error = null);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame != true || !mounted) return;
            setState(() => _error = error.description);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.entryUrl));
  }

  Future<void> _goBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          leading: IconButton(
            tooltip: appTC(context, 'back'),
            onPressed: _goBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Text(
            appTC(context, 'directorSpace'),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          actions: [
            IconButton(
              tooltip: appTC(context, 'refresh'),
              onPressed: _controller.reload,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          bottom: _progress < 100
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(3),
                  child: LinearProgressIndicator(value: _progress / 100),
                )
              : null,
        ),
        body: _error == null
            ? WebViewWidget(controller: _controller)
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_rounded, size: 48),
                      const SizedBox(height: 14),
                      const Text(
                        'WebAdmin momentanement indisponible',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _controller.reload,
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(appTC(context, 'retry')),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
