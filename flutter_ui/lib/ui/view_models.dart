import 'package:flutter/material.dart';

enum HostAvailability { online, offline, connecting, unknown }

@immutable
class HostTileViewModel {
  const HostTileViewModel({
    required this.id,
    required this.name,
    this.address,
    this.availability = HostAvailability.unknown,
    this.isPaired = false,
    this.pairingStatusKnown = true,
    this.subtitle,
  });

  final String id;
  final String name;
  final String? address;
  final HostAvailability availability;
  final bool isPaired;
  final bool pairingStatusKnown;
  final String? subtitle;

  bool get isOnline => availability == HostAvailability.online;
}

@immutable
class AppTileViewModel {
  const AppTileViewModel({
    required this.id,
    required this.title,
    this.artwork,
    this.isRunning = false,
    this.isLoading = false,
    this.enabled = true,
  });

  final String id;
  final String title;
  final ImageProvider<Object>? artwork;
  final bool isRunning;
  final bool isLoading;
  final bool enabled;
}

@immutable
class HeaderActionViewModel {
  const HeaderActionViewModel({
    required this.id,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.enabled = true,
    this.badge,
    this.autofocus = false,
  });

  final String id;
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool enabled;
  final String? badge;
  final bool autofocus;
}

@immutable
class SettingsCategoryViewModel {
  const SettingsCategoryViewModel({
    required this.id,
    required this.label,
    required this.icon,
    required this.options,
  });

  final String id;
  final String label;
  final IconData icon;
  final List<Widget> options;
}

@immutable
class ChoiceItem<T> {
  const ChoiceItem({
    required this.value,
    required this.label,
    this.enabled = true,
  });

  final T value;
  final String label;
  final bool enabled;
}

enum DiagnosticCapabilityStatus { supported, unsupported, unknown }

@immutable
class CodecCapabilityViewModel {
  const CodecCapabilityViewModel({
    required this.id,
    required this.codec,
    required this.profile,
    required this.status,
    required this.enabled,
  });

  final String id;
  final String codec;
  final String profile;
  final DiagnosticCapabilityStatus status;
  final bool enabled;
}

@immutable
class NavigationBindingViewModel {
  const NavigationBindingViewModel({
    required this.action,
    required this.remote,
    required this.keyboard,
    required this.gamepad,
  });

  final String action;
  final String remote;
  final String keyboard;
  final String gamepad;
}

@immutable
class SystemInfoEntry {
  const SystemInfoEntry(this.label, this.value);

  final String label;
  final String value;
}
