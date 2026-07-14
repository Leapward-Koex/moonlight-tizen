import 'dart:math' as math;

import 'build_variant.dart';
import 'json_utils.dart';
import 'platform_capabilities.dart';

enum AudioConfiguration {
  stereo('Stereo'),
  surround51('51Surround'),
  surround71('71Surround');

  const AudioConfiguration(this.wireName);
  final String wireName;

  static AudioConfiguration fromWireName(String value) => values.firstWhere(
    (item) => item.wireName.toLowerCase() == value.toLowerCase(),
    orElse: () => stereo,
  );
}

enum AudioBackend {
  webAudio('webaudio'),
  nativeEmss('emss');

  const AudioBackend(this.wireName);
  final String wireName;

  static AudioBackend fromWireName(String value) => values.firstWhere(
    (item) => item.wireName.toLowerCase() == value.toLowerCase(),
    orElse: () => webAudio,
  );
}

enum DiagnosticLogLevel { off, error, warning, info, debug }

enum ControllerLayout {
  automatic('automatic'),
  xbox('xbox'),
  nintendo('nintendo'),
  playStation('playstation'),
  custom('custom');

  const ControllerLayout(this.wireName);
  final String wireName;

  static ControllerLayout fromWireName(String value) => values.firstWhere(
    (item) => item.wireName == value.toLowerCase(),
    orElse: () => automatic,
  );
}

enum MouseActivationButton {
  start('start'),
  back('back'),
  leftStick('leftStick'),
  rightStick('rightStick');

  const MouseActivationButton(this.wireName);
  final String wireName;

  static MouseActivationButton fromWireName(String value) => values.firstWhere(
    (item) => item.wireName.toLowerCase() == value.toLowerCase(),
    orElse: () => start,
  );
}

enum PointerCaptureMode {
  firstClick('firstClick'),
  streamStart('streamStart'),
  disabled('disabled');

  const PointerCaptureMode(this.wireName);
  final String wireName;

  static PointerCaptureMode fromWireName(String value) => values.firstWhere(
    (item) => item.wireName.toLowerCase() == value.toLowerCase(),
    orElse: () => firstClick,
  );
}

enum ControllerShortcutPreset {
  standard('standard'),
  simplified('simplified'),
  disabled('disabled');

  const ControllerShortcutPreset(this.wireName);
  final String wireName;

  static ControllerShortcutPreset fromWireName(String value) =>
      values.firstWhere(
        (item) => item.wireName.toLowerCase() == value.toLowerCase(),
        orElse: () => standard,
      );
}

enum KeyboardShortcutPreset {
  full('full'),
  compact('compact'),
  disabled('disabled');

  const KeyboardShortcutPreset(this.wireName);
  final String wireName;

  static KeyboardShortcutPreset fromWireName(String value) => values.firstWhere(
    (item) => item.wireName.toLowerCase() == value.toLowerCase(),
    orElse: () => full,
  );
}

final class StreamResolution {
  const StreamResolution(this.width, this.height);

  final int width;
  final int height;

  String get wireName => '$width:$height';
  String get modePrefix => '${width}x$height';

  static const sd480 = StreamResolution(854, 480);
  static const hd720 = StreamResolution(1280, 720);
  static const hd1080 = StreamResolution(1920, 1080);
  static const qhd1440 = StreamResolution(2560, 1440);
  static const uhd4k = StreamResolution(3840, 2160);
  static const known = [sd480, hd720, hd1080, qhd1440, uhd4k];

  factory StreamResolution.fromJson(Object? json) {
    if (json is Map) {
      return StreamResolution(
        jsonInt(json['width'], 1280),
        jsonInt(json['height'], 720),
      );
    }
    final parts = jsonString(json, '1280:720').split(RegExp('[:xX]'));
    if (parts.length != 2) return hd720;
    return StreamResolution(
      int.tryParse(parts[0]) ?? 1280,
      int.tryParse(parts[1]) ?? 720,
    );
  }

  Map<String, Object?> toJson() => {'width': width, 'height': height};

  @override
  bool operator ==(Object other) =>
      other is StreamResolution &&
      width == other.width &&
      height == other.height;

  @override
  int get hashCode => Object.hash(width, height);
}

/// All user-selectable behavior in one immutable, versioned value object.
///
/// Use [normalized] after restoring persisted JSON or applying a UI change. It
/// enforces the same cross-setting constraints as the legacy web UI.
final class AppSettings {
  static const int currentSchemaVersion = 3;
  static const List<int> normalFrameRates = [30, 60];
  static const List<int> unlockedFrameRates = [30, 60, 90, 120, 144];
  static const List<int> packetDurationsMs = [0, 5, 10, 20];

  const AppSettings({
    this.schemaVersion = currentSchemaVersion,
    this.resolution = StreamResolution.hd720,
    this.frameRate = 60,
    this.bitrateMbps = 10,
    this.framePacing = false,
    this.showIpAddressField = false,
    this.sortApps = false,
    this.optimizeGameSettings = false,
    this.rumbleFeedback = false,
    this.mouseEmulation = false,
    this.flipAbButtons = false,
    this.flipXyButtons = false,
    this.controllerLayout = ControllerLayout.automatic,
    this.controllerProfiles = const <String, ControllerLayout>{},
    this.stickDeadzone = .12,
    this.triggerThreshold = .05,
    this.controllerSensitivity = 1,
    this.invertControllerYAxis = false,
    this.mouseEmulationSpeed = 1,
    this.mouseAcceleration = 1,
    this.mouseScrollSpeed = 1,
    this.mouseActivationButton = MouseActivationButton.start,
    this.physicalMouseSensitivity = 1,
    this.invertMouseScroll = false,
    this.keyboardCaptureWithoutPointerLock = true,
    this.pointerCaptureMode = PointerCaptureMode.firstClick,
    this.stopControllerShortcut = ControllerShortcutPreset.standard,
    this.statsControllerShortcut = ControllerShortcutPreset.standard,
    this.stopKeyboardShortcut = KeyboardShortcutPreset.full,
    this.statsKeyboardShortcut = KeyboardShortcutPreset.full,
    this.audioBackend = AudioBackend.webAudio,
    this.audioConfiguration = AudioConfiguration.stereo,
    this.audioPacketDurationMs = 0,
    this.audioJitterBufferMs = 100,
    this.playAudioOnHost = false,
    this.videoCodec = VideoCodec.h264,
    this.hdr = false,
    this.fullColorRange = false,
    this.gameMode = false,
    this.unlockAllFrameRates = false,
    this.optimizeBitrate = false,
    this.disableConnectionWarnings = false,
    this.showPerformanceStats = false,
    this.diagnosticLogLevel = DiagnosticLogLevel.info,
  });

  final int schemaVersion;
  final StreamResolution resolution;
  final int frameRate;
  final double bitrateMbps;
  final bool framePacing;
  final bool showIpAddressField;
  final bool sortApps;
  final bool optimizeGameSettings;
  final bool rumbleFeedback;
  final bool mouseEmulation;
  final bool flipAbButtons;
  final bool flipXyButtons;
  final ControllerLayout controllerLayout;
  final Map<String, ControllerLayout> controllerProfiles;
  final double stickDeadzone;
  final double triggerThreshold;
  final double controllerSensitivity;
  final bool invertControllerYAxis;
  final double mouseEmulationSpeed;
  final double mouseAcceleration;
  final double mouseScrollSpeed;
  final MouseActivationButton mouseActivationButton;
  final double physicalMouseSensitivity;
  final bool invertMouseScroll;
  final bool keyboardCaptureWithoutPointerLock;
  final PointerCaptureMode pointerCaptureMode;
  final ControllerShortcutPreset stopControllerShortcut;
  final ControllerShortcutPreset statsControllerShortcut;
  final KeyboardShortcutPreset stopKeyboardShortcut;
  final KeyboardShortcutPreset statsKeyboardShortcut;
  final AudioBackend audioBackend;
  final AudioConfiguration audioConfiguration;
  final int audioPacketDurationMs;
  final int audioJitterBufferMs;
  final bool playAudioOnHost;
  final VideoCodec videoCodec;
  final bool hdr;
  final bool fullColorRange;
  final bool gameMode;
  final bool unlockAllFrameRates;
  final bool optimizeBitrate;
  final bool disableConnectionWarnings;
  final bool showPerformanceStats;
  final DiagnosticLogLevel diagnosticLogLevel;

  String get streamMode => '${resolution.modePrefix}x$frameRate';
  int get bitrateKbps => (bitrateMbps * 1000).round();
  bool get shouldWarnHighBitrate => bitrateMbps > 100;
  bool get shouldWarnResolutionFrameRate =>
      resolution.width > 1920 && resolution.height > 1080 && frameRate > 60;
  bool get shouldWarnSurround =>
      audioConfiguration != AudioConfiguration.stereo;
  bool get shouldWarnCodec => videoCodec == VideoCodec.av1;

  factory AppSettings.defaultsFor(PlatformCapabilities capabilities) =>
      AppSettings(
        gameMode: capabilities.defaultGameMode,
        audioBackend: capabilities.supportsNativeAudio
            ? AudioBackend.nativeEmss
            : AudioBackend.webAudio,
      ).normalized(capabilities);

  factory AppSettings.fromJson(Map<String, Object?> json) {
    final codec = VideoCodec.fromWireName(
      jsonString(json['videoCodec'], jsonString(json['codec'], 'H264')),
    );
    final resolutionJson =
        json['resolution'] ??
        '${jsonInt(json['width'], 1280)}:${jsonInt(json['height'], 720)}';
    return AppSettings(
      schemaVersion: jsonInt(json['schemaVersion'], currentSchemaVersion),
      resolution: StreamResolution.fromJson(resolutionJson),
      frameRate: jsonInt(json['frameRate'], 60),
      bitrateMbps: jsonDouble(json['bitrateMbps'] ?? json['bitrate'], 10),
      framePacing: jsonBool(json['framePacing']),
      showIpAddressField: jsonBool(
        json['showIpAddressField'] ?? json['ipAddressFieldMode'],
      ),
      sortApps: jsonBool(json['sortApps'] ?? json['sortAppsList']),
      optimizeGameSettings: jsonBool(
        json['optimizeGameSettings'] ?? json['optimizeGames'],
      ),
      rumbleFeedback: jsonBool(json['rumbleFeedback']),
      mouseEmulation: jsonBool(json['mouseEmulation']),
      flipAbButtons: jsonBool(
        json['flipAbButtons'] ?? json['flipABfaceButtons'],
      ),
      flipXyButtons: jsonBool(
        json['flipXyButtons'] ?? json['flipXYfaceButtons'],
      ),
      controllerLayout: ControllerLayout.fromWireName(
        jsonString(json['controllerLayout'], 'automatic'),
      ),
      controllerProfiles: Map.unmodifiable(
        jsonMap(json['controllerProfiles']).map(
          (key, value) => MapEntry(
            key,
            ControllerLayout.fromWireName(jsonString(value, 'automatic')),
          ),
        ),
      ),
      stickDeadzone: jsonDouble(json['stickDeadzone'], .12),
      triggerThreshold: jsonDouble(json['triggerThreshold'], .05),
      controllerSensitivity: jsonDouble(json['controllerSensitivity'], 1),
      invertControllerYAxis: jsonBool(json['invertControllerYAxis']),
      mouseEmulationSpeed: jsonDouble(json['mouseEmulationSpeed'], 1),
      mouseAcceleration: jsonDouble(json['mouseAcceleration'], 1),
      mouseScrollSpeed: jsonDouble(json['mouseScrollSpeed'], 1),
      mouseActivationButton: MouseActivationButton.fromWireName(
        jsonString(json['mouseActivationButton'], 'start'),
      ),
      physicalMouseSensitivity: jsonDouble(json['physicalMouseSensitivity'], 1),
      invertMouseScroll: jsonBool(json['invertMouseScroll']),
      keyboardCaptureWithoutPointerLock: jsonBool(
        json['keyboardCaptureWithoutPointerLock'],
        true,
      ),
      pointerCaptureMode: PointerCaptureMode.fromWireName(
        jsonString(json['pointerCaptureMode'], 'firstClick'),
      ),
      stopControllerShortcut: ControllerShortcutPreset.fromWireName(
        jsonString(json['stopControllerShortcut'], 'standard'),
      ),
      statsControllerShortcut: ControllerShortcutPreset.fromWireName(
        jsonString(json['statsControllerShortcut'], 'standard'),
      ),
      stopKeyboardShortcut: KeyboardShortcutPreset.fromWireName(
        jsonString(json['stopKeyboardShortcut'], 'full'),
      ),
      statsKeyboardShortcut: KeyboardShortcutPreset.fromWireName(
        jsonString(json['statsKeyboardShortcut'], 'full'),
      ),
      audioBackend: AudioBackend.fromWireName(
        jsonString(json['audioBackend'], AudioBackend.webAudio.wireName),
      ),
      audioConfiguration: AudioConfiguration.fromWireName(
        jsonString(json['audioConfiguration'] ?? json['audioConfig'], 'Stereo'),
      ),
      audioPacketDurationMs: jsonInt(
        json['audioPacketDurationMs'] ?? json['audioPacketDuration'],
      ),
      audioJitterBufferMs: jsonInt(
        json['audioJitterBufferMs'] ?? json['audioJitterMs'],
        100,
      ),
      playAudioOnHost: jsonBool(
        json['playAudioOnHost'] ?? json['playHostAudio'],
      ),
      videoCodec: codec ?? VideoCodec.h264,
      hdr: jsonBool(json['hdr'] ?? json['hdrMode']),
      fullColorRange: jsonBool(json['fullColorRange'] ?? json['fullRange']),
      gameMode: jsonBool(json['gameMode']),
      unlockAllFrameRates: jsonBool(
        json['unlockAllFrameRates'] ?? json['unlockAllFps'],
      ),
      optimizeBitrate: jsonBool(json['optimizeBitrate']),
      disableConnectionWarnings: jsonBool(
        json['disableConnectionWarnings'] ?? json['disableWarnings'],
      ),
      showPerformanceStats: jsonBool(
        json['showPerformanceStats'] ?? json['performanceStats'],
      ),
      diagnosticLogLevel: DiagnosticLogLevel.values.firstWhere(
        (level) =>
            level.name ==
            jsonString(json['diagnosticLogLevel'] ?? json['logLevel'], 'info'),
        orElse: () => DiagnosticLogLevel.info,
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': currentSchemaVersion,
    'resolution': resolution.toJson(),
    'frameRate': frameRate,
    'bitrateMbps': bitrateMbps,
    'framePacing': framePacing,
    'showIpAddressField': showIpAddressField,
    'sortApps': sortApps,
    'optimizeGameSettings': optimizeGameSettings,
    'rumbleFeedback': rumbleFeedback,
    'mouseEmulation': mouseEmulation,
    'flipAbButtons': flipAbButtons,
    'flipXyButtons': flipXyButtons,
    'controllerLayout': controllerLayout.wireName,
    'controllerProfiles': controllerProfiles.map(
      (key, value) => MapEntry(key, value.wireName),
    ),
    'stickDeadzone': stickDeadzone,
    'triggerThreshold': triggerThreshold,
    'controllerSensitivity': controllerSensitivity,
    'invertControllerYAxis': invertControllerYAxis,
    'mouseEmulationSpeed': mouseEmulationSpeed,
    'mouseAcceleration': mouseAcceleration,
    'mouseScrollSpeed': mouseScrollSpeed,
    'mouseActivationButton': mouseActivationButton.wireName,
    'physicalMouseSensitivity': physicalMouseSensitivity,
    'invertMouseScroll': invertMouseScroll,
    'keyboardCaptureWithoutPointerLock': keyboardCaptureWithoutPointerLock,
    'pointerCaptureMode': pointerCaptureMode.wireName,
    'stopControllerShortcut': stopControllerShortcut.wireName,
    'statsControllerShortcut': statsControllerShortcut.wireName,
    'stopKeyboardShortcut': stopKeyboardShortcut.wireName,
    'statsKeyboardShortcut': statsKeyboardShortcut.wireName,
    'audioBackend': audioBackend.wireName,
    'audioConfiguration': audioConfiguration.wireName,
    'audioPacketDurationMs': audioPacketDurationMs,
    'audioJitterBufferMs': audioJitterBufferMs,
    'playAudioOnHost': playAudioOnHost,
    'videoCodec': videoCodec.wireName,
    'hdr': hdr,
    'fullColorRange': fullColorRange,
    'gameMode': gameMode,
    'unlockAllFrameRates': unlockAllFrameRates,
    'optimizeBitrate': optimizeBitrate,
    'disableConnectionWarnings': disableConnectionWarnings,
    'showPerformanceStats': showPerformanceStats,
    'diagnosticLogLevel': diagnosticLogLevel.name,
  };

  Map<String, Object?> toInputConfigurationJson() => {
    'version': 1,
    'controllerLayout': controllerLayout.wireName,
    'controllerProfiles': controllerProfiles.map(
      (key, value) => MapEntry(key, value.wireName),
    ),
    'stickDeadzone': stickDeadzone,
    'triggerThreshold': triggerThreshold,
    'controllerSensitivity': controllerSensitivity,
    'invertControllerYAxis': invertControllerYAxis,
    'mouseEmulationSpeed': mouseEmulationSpeed,
    'mouseAcceleration': mouseAcceleration,
    'mouseScrollSpeed': mouseScrollSpeed,
    'mouseActivationButton': mouseActivationButton.wireName,
    'physicalMouseSensitivity': physicalMouseSensitivity,
    'invertMouseScroll': invertMouseScroll,
    'keyboardCaptureWithoutPointerLock': keyboardCaptureWithoutPointerLock,
    'pointerCaptureMode': pointerCaptureMode.wireName,
    'stopControllerShortcut': stopControllerShortcut.wireName,
    'statsControllerShortcut': statsControllerShortcut.wireName,
    'stopKeyboardShortcut': stopKeyboardShortcut.wireName,
    'statsKeyboardShortcut': statsKeyboardShortcut.wireName,
  };

  AppSettings normalized(PlatformCapabilities capabilities) {
    var normalizedResolution = resolution;
    if (resolution.width <= 0 ||
        resolution.height <= 0 ||
        resolution.width > capabilities.maxWidth ||
        resolution.height > capabilities.maxHeight) {
      normalizedResolution = StreamResolution.known.lastWhere(
        (candidate) =>
            candidate.width <= capabilities.maxWidth &&
            candidate.height <= capabilities.maxHeight,
        orElse: () => StreamResolution.hd720,
      );
    }

    final allowedRates = unlockAllFrameRates
        ? unlockedFrameRates
        : normalFrameRates;
    final normalizedRate = allowedRates.contains(frameRate) ? frameRate : 60;
    final normalizedCodec = capabilities.supportedCodecs.contains(videoCodec)
        ? videoCodec
        : VideoCodec.h264;
    final normalizedJitter =
        ((audioJitterBufferMs.clamp(10, 500) / 10).round() * 10).clamp(10, 500);
    final normalizedBitrate = ((bitrateMbps.clamp(0.5, 150.0) * 2).round() / 2)
        .toDouble();

    return copyWith(
      schemaVersion: currentSchemaVersion,
      resolution: normalizedResolution,
      frameRate: normalizedRate,
      bitrateMbps: normalizedBitrate,
      rumbleFeedback: rumbleFeedback && capabilities.supportsRumble,
      stickDeadzone: stickDeadzone.clamp(0.0, .5).toDouble(),
      triggerThreshold: triggerThreshold.clamp(0.0, .95).toDouble(),
      controllerSensitivity: controllerSensitivity.clamp(.5, 2.0).toDouble(),
      mouseEmulationSpeed: mouseEmulationSpeed.clamp(.25, 3.0).toDouble(),
      mouseAcceleration: mouseAcceleration.clamp(.5, 2.5).toDouble(),
      mouseScrollSpeed: mouseScrollSpeed.clamp(.25, 5.0).toDouble(),
      physicalMouseSensitivity: physicalMouseSensitivity
          .clamp(.25, 3.0)
          .toDouble(),
      audioBackend: capabilities.supportsNativeAudio
          ? audioBackend
          : AudioBackend.webAudio,
      audioPacketDurationMs: packetDurationsMs.contains(audioPacketDurationMs)
          ? audioPacketDurationMs
          : 0,
      audioJitterBufferMs: normalizedJitter,
      videoCodec: normalizedCodec,
      hdr:
          hdr && capabilities.supportsHdr && normalizedCodec != VideoCodec.h264,
      gameMode: capabilities.supportsGameMode && (kForceGameMode || gameMode),
    );
  }

  /// Applies a setting change that affects the bitrate preset. This is kept
  /// separate from [normalized] so restoring state never silently replaces a
  /// bitrate explicitly chosen by the user.
  AppSettings withPresetInputs({
    StreamResolution? resolution,
    int? frameRate,
    VideoCodec? videoCodec,
    bool? hdr,
    bool? optimizeBitrate,
    required PlatformCapabilities capabilities,
  }) {
    var next = copyWith(
      resolution: resolution,
      frameRate: frameRate,
      videoCodec: videoCodec,
      hdr: hdr,
      optimizeBitrate: optimizeBitrate,
    ).normalized(capabilities);
    next = next.copyWith(bitrateMbps: BitratePolicy.recommendedMbps(next));
    return next.normalized(capabilities);
  }

  AppSettings withDefaultInputSettings() => copyWith(
    rumbleFeedback: false,
    mouseEmulation: false,
    flipAbButtons: false,
    flipXyButtons: false,
    controllerLayout: ControllerLayout.automatic,
    controllerProfiles: const <String, ControllerLayout>{},
    stickDeadzone: .12,
    triggerThreshold: .05,
    controllerSensitivity: 1,
    invertControllerYAxis: false,
    mouseEmulationSpeed: 1,
    mouseAcceleration: 1,
    mouseScrollSpeed: 1,
    mouseActivationButton: MouseActivationButton.start,
    physicalMouseSensitivity: 1,
    invertMouseScroll: false,
    keyboardCaptureWithoutPointerLock: true,
    pointerCaptureMode: PointerCaptureMode.firstClick,
    stopControllerShortcut: ControllerShortcutPreset.standard,
    statsControllerShortcut: ControllerShortcutPreset.standard,
    stopKeyboardShortcut: KeyboardShortcutPreset.full,
    statsKeyboardShortcut: KeyboardShortcutPreset.full,
  );

  AppSettings copyWith({
    int? schemaVersion,
    StreamResolution? resolution,
    int? frameRate,
    double? bitrateMbps,
    bool? framePacing,
    bool? showIpAddressField,
    bool? sortApps,
    bool? optimizeGameSettings,
    bool? rumbleFeedback,
    bool? mouseEmulation,
    bool? flipAbButtons,
    bool? flipXyButtons,
    ControllerLayout? controllerLayout,
    Map<String, ControllerLayout>? controllerProfiles,
    double? stickDeadzone,
    double? triggerThreshold,
    double? controllerSensitivity,
    bool? invertControllerYAxis,
    double? mouseEmulationSpeed,
    double? mouseAcceleration,
    double? mouseScrollSpeed,
    MouseActivationButton? mouseActivationButton,
    double? physicalMouseSensitivity,
    bool? invertMouseScroll,
    bool? keyboardCaptureWithoutPointerLock,
    PointerCaptureMode? pointerCaptureMode,
    ControllerShortcutPreset? stopControllerShortcut,
    ControllerShortcutPreset? statsControllerShortcut,
    KeyboardShortcutPreset? stopKeyboardShortcut,
    KeyboardShortcutPreset? statsKeyboardShortcut,
    AudioBackend? audioBackend,
    AudioConfiguration? audioConfiguration,
    int? audioPacketDurationMs,
    int? audioJitterBufferMs,
    bool? playAudioOnHost,
    VideoCodec? videoCodec,
    bool? hdr,
    bool? fullColorRange,
    bool? gameMode,
    bool? unlockAllFrameRates,
    bool? optimizeBitrate,
    bool? disableConnectionWarnings,
    bool? showPerformanceStats,
    DiagnosticLogLevel? diagnosticLogLevel,
  }) => AppSettings(
    schemaVersion: schemaVersion ?? this.schemaVersion,
    resolution: resolution ?? this.resolution,
    frameRate: frameRate ?? this.frameRate,
    bitrateMbps: bitrateMbps ?? this.bitrateMbps,
    framePacing: framePacing ?? this.framePacing,
    showIpAddressField: showIpAddressField ?? this.showIpAddressField,
    sortApps: sortApps ?? this.sortApps,
    optimizeGameSettings: optimizeGameSettings ?? this.optimizeGameSettings,
    rumbleFeedback: rumbleFeedback ?? this.rumbleFeedback,
    mouseEmulation: mouseEmulation ?? this.mouseEmulation,
    flipAbButtons: flipAbButtons ?? this.flipAbButtons,
    flipXyButtons: flipXyButtons ?? this.flipXyButtons,
    controllerLayout: controllerLayout ?? this.controllerLayout,
    controllerProfiles: Map.unmodifiable(
      controllerProfiles ?? this.controllerProfiles,
    ),
    stickDeadzone: stickDeadzone ?? this.stickDeadzone,
    triggerThreshold: triggerThreshold ?? this.triggerThreshold,
    controllerSensitivity: controllerSensitivity ?? this.controllerSensitivity,
    invertControllerYAxis: invertControllerYAxis ?? this.invertControllerYAxis,
    mouseEmulationSpeed: mouseEmulationSpeed ?? this.mouseEmulationSpeed,
    mouseAcceleration: mouseAcceleration ?? this.mouseAcceleration,
    mouseScrollSpeed: mouseScrollSpeed ?? this.mouseScrollSpeed,
    mouseActivationButton: mouseActivationButton ?? this.mouseActivationButton,
    physicalMouseSensitivity:
        physicalMouseSensitivity ?? this.physicalMouseSensitivity,
    invertMouseScroll: invertMouseScroll ?? this.invertMouseScroll,
    keyboardCaptureWithoutPointerLock:
        keyboardCaptureWithoutPointerLock ??
        this.keyboardCaptureWithoutPointerLock,
    pointerCaptureMode: pointerCaptureMode ?? this.pointerCaptureMode,
    stopControllerShortcut:
        stopControllerShortcut ?? this.stopControllerShortcut,
    statsControllerShortcut:
        statsControllerShortcut ?? this.statsControllerShortcut,
    stopKeyboardShortcut: stopKeyboardShortcut ?? this.stopKeyboardShortcut,
    statsKeyboardShortcut: statsKeyboardShortcut ?? this.statsKeyboardShortcut,
    audioBackend: audioBackend ?? this.audioBackend,
    audioConfiguration: audioConfiguration ?? this.audioConfiguration,
    audioPacketDurationMs: audioPacketDurationMs ?? this.audioPacketDurationMs,
    audioJitterBufferMs: audioJitterBufferMs ?? this.audioJitterBufferMs,
    playAudioOnHost: playAudioOnHost ?? this.playAudioOnHost,
    videoCodec: videoCodec ?? this.videoCodec,
    hdr: hdr ?? this.hdr,
    fullColorRange: fullColorRange ?? this.fullColorRange,
    gameMode: gameMode ?? this.gameMode,
    unlockAllFrameRates: unlockAllFrameRates ?? this.unlockAllFrameRates,
    optimizeBitrate: optimizeBitrate ?? this.optimizeBitrate,
    disableConnectionWarnings:
        disableConnectionWarnings ?? this.disableConnectionWarnings,
    showPerformanceStats: showPerformanceStats ?? this.showPerformanceStats,
    diagnosticLogLevel: diagnosticLogLevel ?? this.diagnosticLogLevel,
  );
}

abstract final class BitratePolicy {
  static const Map<String, Map<int, double>> _standard = {
    '854:480': {30: 2, 60: 4, 90: 5, 120: 6, 144: 8},
    '1280:720': {30: 5, 60: 10, 90: 12, 120: 15, 144: 18},
    '1920:1080': {30: 10, 60: 20, 90: 25, 120: 30, 144: 35},
    '2560:1440': {30: 20, 60: 40, 90: 50, 120: 60, 144: 70},
    '3840:2160': {30: 40, 60: 80, 90: 100, 120: 120, 144: 140},
  };

  static double recommendedMbps(AppSettings settings) =>
      settings.optimizeBitrate
      ? optimizedMbps(
          resolution: settings.resolution,
          frameRate: settings.frameRate,
          codec: settings.videoCodec,
          hdr: settings.hdr,
        )
      : standardMbps(settings.resolution, settings.frameRate);

  static double standardMbps(StreamResolution resolution, int frameRate) =>
      _standard[resolution.wireName]?[frameRate] ?? 10;

  static double optimizedMbps({
    required StreamResolution resolution,
    required int frameRate,
    required VideoCodec codec,
    required bool hdr,
  }) {
    final codecMultiplier = switch (codec) {
      VideoCodec.h264 => 1.0,
      VideoCodec.hevc => 0.6,
      VideoCodec.av1 => 0.4,
    };
    final factor = hdr ? 6630.5 : 8309.0;
    final kbps = math.max(
      500,
      (resolution.width *
              resolution.height *
              frameRate /
              factor *
              codecMultiplier)
          .round(),
    );
    return ((kbps / 1000 * 2).round() / 2).clamp(0.5, 150.0);
  }
}
