import 'json_utils.dart';
import 'platform_capabilities.dart';

final class CodecCapabilityEntry {
  const CodecCapabilityEntry({
    required this.key,
    this.enabled = true,
    this.codec = VideoCodec.h264,
    this.hdr = false,
    this.videoFormat = 0,
    this.profile = '',
    this.mimeType = '',
    this.supported,
    this.attempts = 0,
    this.lastTriedAt,
    this.lastSkippedAt,
    this.lastSkipReason = '',
    this.lastSelected = false,
    this.lastWidth = 0,
    this.lastHeight = 0,
    this.lastFps = 0,
    this.lastRequestedCodec = '',
    this.lastRequestedHdrMode = false,
    this.lastUserChangedAt,
    this.source = '',
  });

  final String key;
  final bool enabled;
  final VideoCodec codec;
  final bool hdr;
  final int videoFormat;
  final String profile;
  final String mimeType;
  final bool? supported;
  final int attempts;
  final DateTime? lastTriedAt;
  final DateTime? lastSkippedAt;
  final String lastSkipReason;
  final bool lastSelected;
  final int lastWidth;
  final int lastHeight;
  final int lastFps;
  final String lastRequestedCodec;
  final bool lastRequestedHdrMode;
  final DateTime? lastUserChangedAt;
  final String source;

  factory CodecCapabilityEntry.fromJson(
    String mapKey,
    Map<String, Object?> json,
  ) => CodecCapabilityEntry(
    key: jsonString(json['key'], mapKey),
    enabled: jsonBool(json['enabled'], true),
    codec:
        VideoCodec.fromWireName(jsonString(json['codec'], 'H264')) ??
        VideoCodec.h264,
    hdr: jsonBool(json['hdr']),
    videoFormat: jsonInt(json['videoFormat']),
    profile: jsonString(json['profile']),
    mimeType: jsonString(json['mimeType'], mapKey),
    supported: json['supported'] is bool ? json['supported'] as bool : null,
    attempts: jsonInt(json['attempts']),
    lastTriedAt: jsonDateTime(json['lastTriedAt']),
    lastSkippedAt: jsonDateTime(json['lastSkippedAt']),
    lastSkipReason: jsonString(json['lastSkipReason']),
    lastSelected: jsonBool(json['lastSelected']),
    lastWidth: jsonInt(json['lastWidth']),
    lastHeight: jsonInt(json['lastHeight']),
    lastFps: jsonInt(json['lastFps']),
    lastRequestedCodec: jsonString(json['lastRequestedCodec']),
    lastRequestedHdrMode: jsonBool(json['lastRequestedHdrMode']),
    lastUserChangedAt: jsonDateTime(json['lastUserChangedAt']),
    source: jsonString(json['source']),
  );

  Map<String, Object?> toJson() => {
    'key': key,
    'enabled': enabled,
    'codec': codec.wireName,
    'hdr': hdr,
    'videoFormat': videoFormat,
    'profile': profile,
    'mimeType': mimeType.isEmpty ? key : mimeType,
    'supported': supported,
    'attempts': attempts,
    'lastTriedAt': lastTriedAt?.millisecondsSinceEpoch,
    'lastSkippedAt': lastSkippedAt?.millisecondsSinceEpoch,
    'lastSkipReason': lastSkipReason,
    'lastSelected': lastSelected,
    'lastWidth': lastWidth,
    'lastHeight': lastHeight,
    'lastFps': lastFps,
    'lastRequestedCodec': lastRequestedCodec,
    'lastRequestedHdrMode': lastRequestedHdrMode,
    'lastUserChangedAt': lastUserChangedAt?.millisecondsSinceEpoch,
    'source': source,
  };
}

final class CodecCapabilityCache {
  static const int currentSchemaVersion = 2;

  const CodecCapabilityCache({
    this.schemaVersion = currentSchemaVersion,
    this.entries = const <String, CodecCapabilityEntry>{},
  });

  final int schemaVersion;
  final Map<String, CodecCapabilityEntry> entries;

  Iterable<String> get disabledMimeTypes => entries.values
      .where((entry) => !entry.enabled && entry.mimeType.isNotEmpty)
      .map((entry) => entry.mimeType);

  factory CodecCapabilityCache.fromJson(Map<String, Object?> json) {
    if (jsonInt(json['schemaVersion'] ?? json['version']) !=
        currentSchemaVersion) {
      return const CodecCapabilityCache();
    }
    final rawEntries = jsonMap(json['entries']);
    final entries = <String, CodecCapabilityEntry>{};
    for (final item in rawEntries.entries) {
      final value = jsonMap(item.value);
      if (value.isEmpty) continue;
      final entry = CodecCapabilityEntry.fromJson(item.key, value);
      if (entry.key.isNotEmpty) entries[entry.key] = entry;
    }
    return CodecCapabilityCache(entries: Map.unmodifiable(entries));
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': currentSchemaVersion,
    'entries': entries.map((key, value) => MapEntry(key, value.toJson())),
  };

  CodecCapabilityCache setEnabled(String key, bool enabled, DateTime now) {
    final current = entries[key];
    if (current == null) return this;
    final replacement = CodecCapabilityEntry(
      key: current.key,
      enabled: enabled,
      codec: current.codec,
      hdr: current.hdr,
      videoFormat: current.videoFormat,
      profile: current.profile,
      mimeType: current.mimeType,
      supported: current.supported,
      attempts: current.attempts,
      lastTriedAt: current.lastTriedAt,
      lastSkippedAt: current.lastSkippedAt,
      lastSkipReason: current.lastSkipReason,
      lastSelected: current.lastSelected,
      lastWidth: current.lastWidth,
      lastHeight: current.lastHeight,
      lastFps: current.lastFps,
      lastRequestedCodec: current.lastRequestedCodec,
      lastRequestedHdrMode: current.lastRequestedHdrMode,
      lastUserChangedAt: now,
      source: current.source,
    );
    return CodecCapabilityCache(
      entries: Map.unmodifiable({...entries, key: replacement}),
    );
  }
}
