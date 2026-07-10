import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/moonlight_theme.dart';
import '../view_models.dart';
import 'tv_focusable.dart';

Future<T?> showMoonlightDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = false,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: const Color(0xA6000000),
    builder: builder,
  );
}

@immutable
class MoonlightDialogAction {
  const MoonlightDialogAction({
    required this.label,
    required this.onPressed,
    this.icon,
    this.enabled = true,
    this.autofocus = false,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool enabled;
  final bool autofocus;
  final bool destructive;
}

class MoonlightDialog extends StatelessWidget {
  const MoonlightDialog({
    required this.title,
    required this.child,
    super.key,
    this.actions = const [],
    this.maxWidth = 720,
    this.maxHeightFactor = .84,
    this.icon,
  });

  final String title;
  final Widget child;
  final List<MoonlightDialogAction> actions;
  final double maxWidth;
  final double maxHeightFactor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(48),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: screen.height * maxHeightFactor,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 26, 26, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 38, color: MoonlightColors.textMuted),
                    const SizedBox(width: 18),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
                  child: DefaultTextStyle.merge(
                    style: Theme.of(context).textTheme.bodyLarge,
                    child: child,
                  ),
                ),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 20),
                TvFocusTraversalGroup(
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 14,
                    runSpacing: 12,
                    children: [
                      for (final action in actions)
                        ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 160),
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
            ],
          ),
        ),
      ),
    );
  }
}

class ConfirmationDialog extends StatelessWidget {
  const ConfirmationDialog({
    required this.title,
    required this.message,
    required this.onConfirm,
    required this.onCancel,
    super.key,
    this.confirmLabel = 'Continue',
    this.cancelLabel = 'Cancel',
    this.destructive = false,
    this.icon,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final bool destructive;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return MoonlightDialog(
      title: title,
      icon: icon,
      // ignore: sort_child_properties_last
      child: Text(message),
      actions: [
        MoonlightDialogAction(
          label: cancelLabel,
          onPressed: onCancel,
          autofocus: true,
        ),
        MoonlightDialogAction(
          label: confirmLabel,
          onPressed: onConfirm,
          destructive: destructive,
        ),
      ],
    );
  }
}

class AddHostDialog extends StatefulWidget {
  const AddHostDialog({
    required this.onSubmit,
    required this.onCancel,
    super.key,
    this.initialAddress = '',
    this.numericInput = false,
    this.busy = false,
    this.error,
  });

  final String initialAddress;
  final bool numericInput;
  final bool busy;
  final String? error;
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;

  @override
  State<AddHostDialog> createState() => _AddHostDialogState();
}

class _AddHostDialogState extends State<AddHostDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialAddress);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final address = _controller.text.trim();
    if (!widget.busy && address.isNotEmpty) widget.onSubmit(address);
  }

  @override
  Widget build(BuildContext context) {
    return MoonlightDialog(
      title: 'Add Host',
      icon: Icons.add_to_queue,
      // ignore: sort_child_properties_last
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Enter the IP address or hostname of a PC running Sunshine.',
          ),
          const SizedBox(height: 22),
          TextField(
            key: const ValueKey('add-host-address'),
            controller: _controller,
            autofocus: true,
            enabled: !widget.busy,
            keyboardType: widget.numericInput
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.url,
            inputFormatters: widget.numericInput
                ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.:]'))]
                : null,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Host address',
              hintText: '192.168.1.100',
              errorText: widget.error,
              suffixIcon: widget.busy
                  ? const Padding(
                      padding: EdgeInsets.all(13),
                      child: CircularProgressIndicator(strokeWidth: 3),
                    )
                  : null,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        MoonlightDialogAction(label: 'Cancel', onPressed: widget.onCancel),
        MoonlightDialogAction(
          label: widget.busy ? 'Connecting…' : 'Continue',
          onPressed: _submit,
          enabled: !widget.busy,
        ),
      ],
    );
  }
}

class PairingDialog extends StatelessWidget {
  const PairingDialog({
    required this.pin,
    required this.onCancel,
    super.key,
    this.hostName,
    this.message,
  });

  final String pin;
  final String? hostName;
  final String? message;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return MoonlightDialog(
      title: 'Pairing${hostName == null ? '' : ' with $hostName'}',
      icon: Icons.link,
      maxWidth: 620,
      // ignore: sort_child_properties_last
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
            decoration: BoxDecoration(
              color: MoonlightColors.cyan.withValues(alpha: .18),
              border: Border.all(color: MoonlightColors.cyan, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                const Text(
                  'ENTER THIS PIN ON YOUR HOST',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xE0FFFFFF),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                SelectableText(
                  pin,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 86,
                    height: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            message ?? 'Waiting for the host to confirm pairing…',
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        MoonlightDialogAction(
          label: 'Cancel pairing',
          onPressed: onCancel,
          autofocus: true,
        ),
      ],
    );
  }
}

class HostMenuDialog extends StatelessWidget {
  const HostMenuDialog({
    required this.host,
    required this.onWake,
    required this.onDetails,
    required this.onDelete,
    required this.onClose,
    super.key,
    this.wakeEnabled = true,
  });

  final HostTileViewModel host;
  final VoidCallback onWake;
  final VoidCallback onDetails;
  final VoidCallback onDelete;
  final VoidCallback onClose;
  final bool wakeEnabled;

  @override
  Widget build(BuildContext context) {
    return MoonlightDialog(
      title: host.name,
      icon: Icons.tv,
      // ignore: sort_child_properties_last
      child: TvFocusTraversalGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TvActionButton(
              label: 'Wake host',
              icon: Icons.power_settings_new,
              enabled: wakeEnabled,
              autofocus: true,
              onPressed: onWake,
            ),
            const SizedBox(height: 12),
            TvActionButton(
              label: 'Host details',
              icon: Icons.info_outline,
              onPressed: onDetails,
            ),
            const SizedBox(height: 12),
            TvActionButton(
              label: 'Remove host',
              icon: Icons.remove_circle_outline,
              destructive: true,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
      actions: [MoonlightDialogAction(label: 'Close', onPressed: onClose)],
    );
  }
}

class HostDetailsDialog extends StatelessWidget {
  const HostDetailsDialog({
    required this.hostName,
    required this.details,
    required this.onClose,
    super.key,
  });

  final String hostName;
  final List<SystemInfoEntry> details;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return MoonlightDialog(
      title: '$hostName details',
      icon: Icons.info_outline,
      maxWidth: 900,
      // ignore: sort_child_properties_last
      child: Column(
        children: [
          for (final detail in details)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 240,
                    child: Text(
                      detail.label,
                      style: const TextStyle(
                        color: MoonlightColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(child: SelectableText(detail.value)),
                ],
              ),
            ),
        ],
      ),
      actions: [
        MoonlightDialogAction(
          label: 'Close',
          onPressed: onClose,
          autofocus: true,
        ),
      ],
    );
  }
}
