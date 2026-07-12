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
      );
      final restored = AppSettings.fromJson(
        source.toJson(),
      ).normalized(PlatformCapabilities.tizen10());

      expect(restored.resolution, source.resolution);
      expect(restored.frameRate, source.frameRate);
      expect(restored.bitrateMbps, source.bitrateMbps);
      expect(restored.videoCodec, source.videoCodec);
      expect(restored.audioBackend, AudioBackend.nativeEmss);
      expect(restored.toJson()['schemaVersion'], 2);
      expect(restored.hdr, isTrue);
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
