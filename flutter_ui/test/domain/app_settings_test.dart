import 'package:flutter_test/flutter_test.dart';
import 'package:moonlight_tizen_flutter/domain/domain.dart';

void main() {
  group('AppSettings', () {
    test('uses Tizen 10 parity defaults', () {
      final settings = AppSettings.defaultsFor(PlatformCapabilities.tizen10());

      expect(settings.resolution, StreamResolution.hd720);
      expect(settings.frameRate, 60);
      expect(settings.bitrateMbps, 10);
      expect(settings.audioConfiguration, AudioConfiguration.stereo);
      expect(settings.audioBackend, AudioBackend.webAudio);
      expect(settings.audioPacketDurationMs, 0);
      expect(settings.audioJitterBufferMs, 100);
      expect(settings.videoCodec, VideoCodec.h264);
      expect(settings.gameMode, isTrue);
      expect(settings.hdr, isFalse);
    });

    test(
      'normalizes invalid persisted values and cross-setting constraints',
      () {
        final settings = AppSettings.fromJson({
          'resolution': '3840:2160',
          'frameRate': '144',
          'unlockAllFps': false,
          'bitrate': 999,
          'audioPacketDuration': 17,
          'audioJitterMs': 511,
          'videoCodec': 'H264',
          'hdrMode': true,
          'rumbleFeedback': true,
          'gameMode': true,
        }).normalized(const PlatformCapabilities());

        expect(settings.frameRate, 60);
        expect(settings.bitrateMbps, 150);
        expect(settings.audioPacketDurationMs, 0);
        expect(settings.audioJitterBufferMs, 500);
        expect(settings.hdr, isFalse);
        expect(settings.rumbleFeedback, isFalse);
        expect(settings.gameMode, isFalse);
      },
    );

    test('disabling unlocked FPS resets a high rate to 60', () {
      final capabilities = PlatformCapabilities.tizen10();
      final settings = const AppSettings(
        frameRate: 120,
        unlockAllFrameRates: false,
      ).normalized(capabilities);

      expect(settings.frameRate, 60);
    });

    test('H.264 selection disables HDR', () {
      final capabilities = PlatformCapabilities.tizen10();
      final settings = const AppSettings(videoCodec: VideoCodec.hevc, hdr: true)
          .withPresetInputs(
            videoCodec: VideoCodec.h264,
            capabilities: capabilities,
          );

      expect(settings.videoCodec, VideoCodec.h264);
      expect(settings.hdr, isFalse);
    });

    test('standard presets preserve the legacy table', () {
      expect(BitratePolicy.standardMbps(StreamResolution.sd480, 30), 2);
      expect(BitratePolicy.standardMbps(StreamResolution.hd720, 60), 10);
      expect(BitratePolicy.standardMbps(StreamResolution.hd1080, 120), 30);
      expect(BitratePolicy.standardMbps(StreamResolution.uhd4k, 144), 140);
    });

    test('round-trips the versioned JSON schema', () {
      final source = const AppSettings(
        resolution: StreamResolution.qhd1440,
        frameRate: 90,
        bitrateMbps: 50,
        unlockAllFrameRates: true,
        videoCodec: VideoCodec.hevc,
        hdr: true,
        audioBackend: AudioBackend.nativeEmss,
        controllerLayout: ControllerLayout.nintendo,
        controllerProfiles: {'deadbeef': ControllerLayout.xbox},
        stickDeadzone: .2,
        triggerThreshold: .15,
        controllerSensitivity: 1.4,
        mouseEmulationSpeed: 1.6,
        pointerCaptureMode: PointerCaptureMode.streamStart,
        stopKeyboardShortcut: KeyboardShortcutPreset.compact,
      );
      final restored = AppSettings.fromJson(
        source.toJson(),
      ).normalized(PlatformCapabilities.tizen10());

      expect(restored.resolution, source.resolution);
      expect(restored.frameRate, source.frameRate);
      expect(restored.bitrateMbps, source.bitrateMbps);
      expect(restored.videoCodec, source.videoCodec);
      expect(restored.audioBackend, AudioBackend.nativeEmss);
      expect(restored.toJson()['schemaVersion'], 3);
      expect(restored.hdr, isTrue);
      expect(restored.controllerLayout, ControllerLayout.nintendo);
      expect(restored.controllerProfiles['deadbeef'], ControllerLayout.xbox);
      expect(restored.stickDeadzone, .2);
      expect(restored.triggerThreshold, .15);
      expect(restored.controllerSensitivity, 1.4);
      expect(restored.mouseEmulationSpeed, 1.6);
      expect(restored.pointerCaptureMode, PointerCaptureMode.streamStart);
      expect(restored.stopKeyboardShortcut, KeyboardShortcutPreset.compact);
    });

    test('normalizes input calibration ranges', () {
      final settings = const AppSettings(
        stickDeadzone: 2,
        triggerThreshold: -1,
        controllerSensitivity: 4,
        mouseEmulationSpeed: 9,
        mouseAcceleration: .1,
        mouseScrollSpeed: 10,
        physicalMouseSensitivity: 0,
      ).normalized(PlatformCapabilities.tizen10());

      expect(settings.stickDeadzone, .5);
      expect(settings.triggerThreshold, 0);
      expect(settings.controllerSensitivity, 2);
      expect(settings.mouseEmulationSpeed, 3);
      expect(settings.mouseAcceleration, .5);
      expect(settings.mouseScrollSpeed, 5);
      expect(settings.physicalMouseSensitivity, .25);
    });

    test('resetting input preserves unrelated streaming settings', () {
      final settings = const AppSettings(
        bitrateMbps: 42,
        mouseEmulation: true,
        controllerLayout: ControllerLayout.nintendo,
        controllerProfiles: {'deadbeef': ControllerLayout.xbox},
        stickDeadzone: .3,
      ).withDefaultInputSettings();

      expect(settings.bitrateMbps, 42);
      expect(settings.mouseEmulation, isFalse);
      expect(settings.controllerLayout, ControllerLayout.automatic);
      expect(settings.controllerProfiles, isEmpty);
      expect(settings.stickDeadzone, .12);
    });

    test(
      'falls back from native audio when the platform cannot provide it',
      () {
        final settings = const AppSettings(
          audioBackend: AudioBackend.nativeEmss,
        ).normalized(const PlatformCapabilities());

        expect(settings.audioBackend, AudioBackend.webAudio);
      },
    );
  });
}
