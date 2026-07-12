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
    this.focusNode,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool enabled;
  final bool autofocus;
  final bool destructive;
  final FocusNode? focusNode;
}

class MoonlightDialog extends StatelessWidget {
  const MoonlightDialog({
    required this.title,
    required this.child,
    super.key,
    this.actions = const [],
    this.maxWidth = 840,
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
    return AlertDialog(
      insetPadding: const EdgeInsets.all(64),
      titlePadding: const EdgeInsets.fromLTRB(32, 28, 32, 16),
      contentPadding: const EdgeInsets.fromLTRB(32, 8, 32, 24),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      title: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 32, color: MoonlightColors.cyan),
            const SizedBox(width: 16),
          ],
          Expanded(child: Text(title)),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: screen.height * maxHeightFactor,
        ),
        child: SingleChildScrollView(
          child: DefaultTextStyle.merge(
            style: Theme.of(context).textTheme.bodyLarge,
            child: child,
          ),
        ),
      ),
      actions: [
        for (final action in actions) _TvDialogActionButton(action: action),
      ],
    );
  }
}

class _TvDialogActionButton extends StatelessWidget {
  const _TvDialogActionButton({required this.action});

  final MoonlightDialogAction action;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MoonlightMetrics.minHitTarget,
    child: TvFocusable(
      autofocus: action.autofocus,
      focusNode: action.focusNode,
      enabled: action.enabled,
      semanticLabel: action.label,
      focusColor: action.destructive
          ? const Color(0xFFFFB4AB)
          : MoonlightColors.cyan,
      onActivate: action.onPressed,
      builder: (context, focused) => ExcludeFocus(
        child: IgnorePointer(
          child: TextButton.icon(
            onPressed: action.enabled ? action.onPressed : null,
            style: action.destructive
                ? TextButton.styleFrom(foregroundColor: const Color(0xFFFFB4AB))
                : null,
            icon: action.icon == null
                ? const SizedBox.shrink()
                : Icon(action.icon),
            label: Text(action.label),
          ),
        ),
      ),
    ),
  );
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
  late final FocusNode _cancelFocus;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialAddress);
    _cancelFocus = FocusNode(debugLabel: 'Cancel');
  }

  @override
  void dispose() {
    _controller.dispose();
    _cancelFocus.dispose();
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
          CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowDown): () {
                _cancelFocus.requestFocus();
              },
            },
            child: TextField(
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
          ),
        ],
      ),
      actions: [
        MoonlightDialogAction(
          label: 'Cancel',
          onPressed: widget.onCancel,
          focusNode: _cancelFocus,
        ),
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
            _DialogListTile(
              icon: Icons.power_settings_new,
              label: 'Wake host',
              enabled: wakeEnabled,
              autofocus: true,
              onPressed: onWake,
            ),
            const Divider(height: 1),
            _DialogListTile(
              icon: Icons.info_outline,
              label: 'Host details',
              onPressed: onDetails,
            ),
            const Divider(height: 1),
            _DialogListTile(
              icon: Icons.remove_circle_outline,
              label: 'Remove host',
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
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(detail.label),
              subtitle: SelectableText(detail.value),
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

class _DialogListTile extends StatelessWidget {
  const _DialogListTile({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.enabled = true,
    this.autofocus = false,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool enabled;
  final bool autofocus;
  final bool destructive;

  @override
  Widget build(BuildContext context) => TvFocusable(
    autofocus: autofocus,
    enabled: enabled,
    semanticLabel: label,
    focusColor: destructive ? const Color(0xFFFFB4AB) : MoonlightColors.cyan,
    onActivate: onPressed,
    builder: (context, focused) => ExcludeFocus(
      child: IgnorePointer(
        child: ListTile(
          enabled: enabled,
          selected: focused,
          selectedTileColor: MoonlightColors.cyan.withValues(alpha: .10),
          leading: Icon(
            icon,
            color: destructive ? const Color(0xFFFFB4AB) : null,
          ),
          title: Text(
            label,
            style: destructive
                ? const TextStyle(color: Color(0xFFFFB4AB))
                : null,
          ),
          onTap: enabled ? onPressed : null,
        ),
      ),
    ),
  );
}
