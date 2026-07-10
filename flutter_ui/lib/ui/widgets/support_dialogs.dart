import 'package:flutter/material.dart';

import '../theme/moonlight_theme.dart';
import '../view_models.dart';
import 'moonlight_dialog.dart';

class SupportDialog extends StatelessWidget {
  const SupportDialog({
    required this.onClose,
    super.key,
    this.qrCode,
    this.supportUrl = 'https://github.com/OneLiberty/moonlight-chrome-tizen',
    this.version,
  });

  final Widget? qrCode;
  final String supportUrl;
  final String? version;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return MoonlightDialog(
      title: 'Moonlight Support',
      icon: Icons.help_outline,
      maxWidth: 760,
      // ignore: sort_child_properties_last
      child: Column(
        children: [
          const Text(
            'For help, troubleshooting, and release information, visit the '
            'Moonlight Tizen project page.',
            textAlign: TextAlign.center,
          ),
          if (qrCode != null) ...[
            const SizedBox(height: 24),
            Container(
              width: 270,
              height: 270,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Color(0x66000000), blurRadius: 6),
                ],
              ),
              child: qrCode,
            ),
          ],
          const SizedBox(height: 20),
          SelectableText(
            supportUrl,
            textAlign: TextAlign.center,
            style: const TextStyle(color: MoonlightColors.cyan, fontSize: 18),
          ),
          if (version != null) ...[
            const SizedBox(height: 12),
            Text(
              'Version $version',
              style: const TextStyle(color: MoonlightColors.textMuted),
            ),
          ],
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

class NavigationGuideDialog extends StatelessWidget {
  const NavigationGuideDialog({
    required this.bindings,
    required this.onClose,
    super.key,
  });

  final List<NavigationBindingViewModel> bindings;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return MoonlightDialog(
      title: 'Navigation Guide',
      icon: Icons.tv,
      maxWidth: 1500,
      maxHeightFactor: .9,
      // ignore: sort_child_properties_last
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _GuideLegend(),
          const SizedBox(height: 18),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 1100),
              child: Table(
                columnWidths: const {
                  0: FlexColumnWidth(1.4),
                  1: FlexColumnWidth(1.5),
                  2: FlexColumnWidth(1.5),
                  3: FlexColumnWidth(1.5),
                },
                border: const TableBorder(
                  horizontalInside: BorderSide(color: MoonlightColors.divider),
                ),
                children: [
                  const TableRow(
                    decoration: BoxDecoration(
                      color: MoonlightColors.background,
                    ),
                    children: [
                      _GuideCell('Action', header: true),
                      _GuideCell(
                        'Remote',
                        header: true,
                        color: MoonlightColors.cyan,
                      ),
                      _GuideCell(
                        'Keyboard',
                        header: true,
                        color: MoonlightColors.offline,
                      ),
                      _GuideCell(
                        'Gamepad',
                        header: true,
                        color: MoonlightColors.running,
                      ),
                    ],
                  ),
                  for (final binding in bindings)
                    TableRow(
                      children: [
                        _GuideCell(binding.action),
                        _GuideCell(binding.remote, color: MoonlightColors.cyan),
                        _GuideCell(
                          binding.keyboard,
                          color: MoonlightColors.offline,
                        ),
                        _GuideCell(
                          binding.gamepad,
                          color: MoonlightColors.running,
                        ),
                      ],
                    ),
                ],
              ),
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

class _GuideLegend extends StatelessWidget {
  const _GuideLegend();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      alignment: WrapAlignment.center,
      spacing: 30,
      runSpacing: 12,
      children: [
        _LegendItem('Remote', MoonlightColors.cyan),
        _LegendItem('Keyboard', MoonlightColors.offline),
        _LegendItem('Gamepad', MoonlightColors.running),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(color: Color(0x66000000), blurRadius: 4),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: MoonlightColors.textBody,
            fontSize: 18,
            letterSpacing: .5,
          ),
        ),
      ],
    );
  }
}

class _GuideCell extends StatelessWidget {
  const _GuideCell(this.text, {this.header = false, this.color});

  final String text;
  final bool header;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      child: Text(
        text,
        style: TextStyle(
          color: color ?? MoonlightColors.textBody,
          fontSize: header ? 19 : 17,
          fontWeight: header ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    );
  }
}

const defaultNavigationBindings = <NavigationBindingViewModel>[
  NavigationBindingViewModel(
    action: 'Navigate',
    remote: 'Directional pad',
    keyboard: 'Arrow keys',
    gamepad: 'D-pad or left stick',
  ),
  NavigationBindingViewModel(
    action: 'Select / left click',
    remote: 'Enter',
    keyboard: 'Enter or Space',
    gamepad: 'A / Cross',
  ),
  NavigationBindingViewModel(
    action: 'Back / right click',
    remote: 'Back',
    keyboard: 'Escape',
    gamepad: 'B / Circle',
  ),
  NavigationBindingViewModel(
    action: 'Host menu',
    remote: 'Tools / Menu',
    keyboard: 'M or context menu',
    gamepad: 'X / Square',
  ),
];
