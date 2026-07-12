import 'json_utils.dart';

/// Runtime capabilities that can affect settings defaults or option visibility.
final class PlatformCapabilities {
  static const int currentSchemaVersion = 1;

  const PlatformCapabilities({
    this.schemaVersion = currentSchemaVersion,
    this.platform = 'browser',
    this.platformVersion = '',
    this.maxWidth = 3840,
    this.maxHeight = 2160,
    this.supportsHdr = false,
    this.supportsGameMode = false,
    this.supportsRumble = false,
    this.supportsPointerLock = true,
    this.supportsRestart = false,
    this.supportsNativeAudio = false,
    this.supportedCodecs = const <VideoCodec>{VideoCodec.h264},
  });

  final int schemaVersion;
  final String platform;
  final String platformVersion;
  final int maxWidth;
  final int maxHeight;
  final bool supportsHdr;
  final bool supportsGameMode;
  final bool supportsRumble;
  final bool supportsPointerLock;
  final bool supportsRestart;
  final bool supportsNativeAudio;
  final Set<VideoCodec> supportedCodecs;

  bool get isTizen => platform.toLowerCase() == 'tizen';

  double? get tizenVersion => isTizen ? double.tryParse(platformVersion) : null;

  /// Mirrors the legacy UI: Game Mode is on where available, except on Tizen
  /// 5.5 and 9.0 where it is disabled for compatibility.
  bool get defaultGameMode {
    if (!supportsGameMode) return false;
    final version = tizenVersion;
    return version != 5.5 && version != 9.0;
  }

  factory PlatformCapabilities.tizen10({
    int maxWidth = 3840,
    int maxHeight = 2160,
    bool supportsHdr = true,
    bool supportsRumble = true,
  }) => PlatformCapabilities(
    platform: 'tizen',
    platformVersion: '10.0',
    maxWidth: maxWidth,
    maxHeight: maxHeight,
    supportsHdr: supportsHdr,
    supportsGameMode: true,
    supportsRumble: supportsRumble,
    supportsPointerLock: true,
    supportsRestart: true,
    supportsNativeAudio: true,
    supportedCodecs: const {VideoCodec.h264, VideoCodec.hevc, VideoCodec.av1},
  );

  factory PlatformCapabilities.fromJson(Map<String, Object?> json) {
    final codecs = jsonList(json['supportedCodecs'])
        .map((value) => VideoCodec.fromWireName(jsonString(value)))
        .whereType<VideoCodec>()
        .toSet();
    return PlatformCapabilities(
      schemaVersion: jsonInt(json['schemaVersion'], currentSchemaVersion),
      platform: jsonString(json['platform'], 'browser'),
      platformVersion: jsonString(json['platformVersion']),
      maxWidth: jsonInt(json['maxWidth'], 3840),
      maxHeight: jsonInt(json['maxHeight'], 2160),
      supportsHdr: jsonBool(json['supportsHdr']),
      supportsGameMode: jsonBool(json['supportsGameMode']),
      supportsRumble: jsonBool(json['supportsRumble']),
      supportsPointerLock: jsonBool(json['supportsPointerLock'], true),
      supportsRestart: jsonBool(json['supportsRestart']),
      supportsNativeAudio: jsonBool(json['supportsNativeAudio']),
      supportedCodecs: codecs.isEmpty ? const {VideoCodec.h264} : codecs,
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'platform': platform,
    'platformVersion': platformVersion,
    'maxWidth': maxWidth,
    'maxHeight': maxHeight,
    'supportsHdr': supportsHdr,
    'supportsGameMode': supportsGameMode,
    'supportsRumble': supportsRumble,
    'supportsPointerLock': supportsPointerLock,
    'supportsRestart': supportsRestart,
    'supportsNativeAudio': supportsNativeAudio,
    'supportedCodecs': supportedCodecs.map((codec) => codec.wireName).toList(),
  };
}

enum VideoCodec {
  h264('H264'),
  hevc('HEVC'),
  av1('AV1');

  const VideoCodec(this.wireName);
  final String wireName;

  static VideoCodec? fromWireName(String value) {
    final normalized = value.toUpperCase().replaceAll('.', '');
    for (final codec in values) {
      if (codec.wireName == normalized) return codec;
    }
    return null;
  }
}
