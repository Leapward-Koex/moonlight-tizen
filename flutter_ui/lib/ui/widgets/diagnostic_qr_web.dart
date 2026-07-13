import 'dart:ui_web' as ui_web;
import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

class DiagnosticQrCode extends StatefulWidget {
  const DiagnosticQrCode({
    required this.svg,
    super.key,
    this.semanticLabel = 'QR code',
  });

  final String svg;
  final String semanticLabel;

  @override
  State<DiagnosticQrCode> createState() => _DiagnosticQrCodeState();
}

class _DiagnosticQrCodeState extends State<DiagnosticQrCode> {
  static int _nextId = 0;
  late final String _viewType = 'moonlight-diagnostic-qr-${_nextId++}';

  @override
  void initState() {
    super.initState();
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final element = web.HTMLDivElement()
        ..setAttribute('aria-label', widget.semanticLabel)
        ..style.width = '100%'
        ..style.height = '100%'
        ..innerHTML = widget.svg.toJS;
      return element;
    });
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
