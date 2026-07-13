import 'package:flutter/widgets.dart';

class DiagnosticQrCode extends StatelessWidget {
  const DiagnosticQrCode({
    required this.svg,
    super.key,
    this.semanticLabel = 'QR code',
  });

  final String svg;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
