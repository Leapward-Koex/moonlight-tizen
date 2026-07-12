import 'package:flutter/material.dart';

import '../theme/moonlight_theme.dart';
import '../view_models.dart';
import 'moonlight_dialog.dart';
import 'tv_focusable.dart';

class CodecCapabilityTable extends StatelessWidget {
  const CodecCapabilityTable({
    required this.capabilities,
    required this.onEnabledChanged,
    super.key,
    this.emptyMessage = 'Codec capabilities have not been tested yet.',
  });

  final List<CodecCapabilityViewModel> capabilities;
  final void Function(CodecCapabilityViewModel capability, bool enabled)
  onEnabledChanged;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (capabilities.isEmpty) {
      return ListTile(
        leading: const Icon(Icons.info_outline),
        title: Text(emptyMessage),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 64,
        dataRowMinHeight: 72,
        dataRowMaxHeight: 88,
        columns: const [
          DataColumn(label: Text('Use')),
          DataColumn(label: Text('Codec')),
          DataColumn(label: Text('Profile')),
          DataColumn(label: Text('Status')),
        ],
        rows: [
          for (final capability in capabilities)
            DataRow(
              cells: [
                DataCell(
                  SizedBox.square(
                    dimension: MoonlightMetrics.minHitTarget,
                    child: TvFocusable(
                      semanticLabel:
                          '${capability.codec} ${capability.profile}, '
                          '${capability.enabled ? 'enabled' : 'disabled'}',
                      onActivate: () =>
                          onEnabledChanged(capability, !capability.enabled),
                      builder: (context, focused) => ExcludeFocus(
                        child: IgnorePointer(
                          child: Checkbox(
                            value: capability.enabled,
                            onChanged: (value) {
                              if (value != null) {
                                onEnabledChanged(capability, value);
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                DataCell(Text(capability.codec)),
                DataCell(Text(capability.profile)),
                DataCell(
                  Text(
                    _statusLabel(capability.status),
                    style: TextStyle(color: _statusColor(capability.status)),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static String _statusLabel(DiagnosticCapabilityStatus status) =>
      switch (status) {
        DiagnosticCapabilityStatus.supported => 'Supported',
        DiagnosticCapabilityStatus.unsupported => 'Unsupported',
        DiagnosticCapabilityStatus.unknown => 'Unknown',
      };

  static Color _statusColor(DiagnosticCapabilityStatus status) =>
      switch (status) {
        DiagnosticCapabilityStatus.supported => const Color(0xFF7BD88F),
        DiagnosticCapabilityStatus.unsupported => const Color(0xFFFF9B9B),
        DiagnosticCapabilityStatus.unknown => const Color(0xFFFFC046),
      };
}

class DiagnosticsActionPanel extends StatelessWidget {
  const DiagnosticsActionPanel({required this.actions, super.key, this.status});

  final List<MoonlightDialogAction> actions;
  final String? status;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (status != null) ...[
          Semantics(
            liveRegion: true,
            child: Text(status!, style: Theme.of(context).textTheme.bodyMedium),
          ),
          const SizedBox(height: 12),
        ],
        TvFocusTraversalGroup(
          child: Wrap(
            spacing: 14,
            runSpacing: 12,
            children: [
              for (final action in actions)
                SizedBox(
                  width: 280,
                  child: TvActionButton(
                    label: action.label,
                    icon: action.icon,
                    enabled: action.enabled,
                    autofocus: action.autofocus,
                    destructive: action.destructive,
                    onPressed: action.onPressed,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class LogExportDialog extends StatelessWidget {
  const LogExportDialog({
    required this.url,
    required this.status,
    required this.onClose,
    super.key,
    this.qrCode,
    this.onShare,
    this.onStop,
  });

  final String url;
  final String status;
  final Widget? qrCode;
  final VoidCallback? onShare;
  final VoidCallback? onStop;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return MoonlightDialog(
      title: 'Diagnostic Log Export',
      icon: Icons.file_download_outlined,
      maxWidth: 900,
      // ignore: sort_child_properties_last
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (qrCode != null)
            Center(
              child: Container(
                width: 260,
                height: 260,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: qrCode,
              ),
            ),
          const SizedBox(height: 16),
          Semantics(liveRegion: true, child: Text(status)),
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: MoonlightColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(url),
          ),
        ],
      ),
      actions: [
        if (onShare != null)
          MoonlightDialogAction(
            label: 'Share',
            icon: Icons.share,
            onPressed: onShare!,
          ),
        if (onStop != null)
          MoonlightDialogAction(
            label: 'Stop export',
            icon: Icons.stop,
            destructive: true,
            onPressed: onStop!,
          ),
        MoonlightDialogAction(
          label: 'Close',
          onPressed: onClose,
          autofocus: true,
        ),
      ],
    );
  }
}

class StreamStatusOverlay extends StatelessWidget {
  const StreamStatusOverlay({
    super.key,
    this.warning,
    this.statistics,
    this.message,
  });

  final String? warning;
  final String? statistics;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (statistics != null)
            Positioned(
              top: 10,
              left: 10,
              child: Text(
                statistics!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                  shadows: [Shadow(color: Colors.black, blurRadius: 5)],
                ),
              ),
            ),
          if (warning != null)
            Positioned(
              top: 10,
              right: 10,
              child: Text(
                warning!,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  shadows: [Shadow(color: Colors.black, blurRadius: 5)],
                ),
              ),
            ),
          if (message != null)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xCC000000),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  message!,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
