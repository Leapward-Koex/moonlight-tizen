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
            child: DataTable(
              headingRowHeight: 64,
              dataRowMinHeight: 64,
              dataRowMaxHeight: 88,
              columns: const [
                DataColumn(label: Text('Action')),
                DataColumn(label: Text('Remote')),
                DataColumn(label: Text('Keyboard')),
                DataColumn(label: Text('Gamepad')),
              ],
              rows: [
                for (final binding in bindings)
                  DataRow(
                    cells: [
                      DataCell(Text(binding.action)),
                      DataCell(Text(binding.remote)),
                      DataCell(Text(binding.keyboard)),
                      DataCell(Text(binding.gamepad)),
                    ],
                  ),
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

class _GuideLegend extends StatelessWidget {
  const _GuideLegend();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [
        Chip(avatar: Icon(Icons.tv), label: Text('Remote')),
        Chip(avatar: Icon(Icons.keyboard), label: Text('Keyboard')),
        Chip(avatar: Icon(Icons.gamepad), label: Text('Gamepad')),
      ],
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
