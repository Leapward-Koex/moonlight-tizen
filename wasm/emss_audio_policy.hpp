#pragma once

#include <cstdint>
#include <deque>

// Pure timestamp/recovery policy used by the EMSS renderer. It deliberately
// has no Samsung or Emscripten dependencies so its edge cases can be tested
// deterministically.
class EmssAudioPolicy {
 public:
  struct TimestampDecision {
    bool append = false;
    bool rebased = false;
    bool recovered = false;
    double ptsMs = 0.0;
    const char* reason = "none";
  };

  struct ResyncDecision {
    bool started = false;
    bool degraded = false;
    uint32_t count = 0;
  };

  struct RecoveryTick {
    bool requestAnotherIdr = false;
    bool restartRequired = false;
  };

  void Reset();
  TimestampDecision Video(uint32_t rawPtsMs, bool isIdr, uint64_t nowMs,
                          double mediaTimeMs);
  TimestampDecision Audio(uint32_t rawPtsMs, bool timestampValid, bool plc,
                          uint64_t nowMs, double mediaTimeMs);

  int BacklogLimitMs(uint64_t nowMs) const;
  void ObservePlc(uint64_t nowMs);
  bool ShouldAppendForBacklog(int pendingMs, uint64_t nowMs);

  ResyncDecision BeginResync(uint64_t nowMs, double anchorMs);
  void MarkResyncFlushed();
  RecoveryTick TickRecovery(uint64_t nowMs);
  bool IsResyncing() const { return resyncing_; }

  bool HasVideoPts() const { return videoReady_; }
  bool HasAudioPts() const { return audio_.hasPts; }
  double LastVideoPtsMs() const { return video_.lastPtsMs; }
  double LastAudioPtsMs() const { return audio_.lastPtsMs; }
  uint32_t TimestampRebases() const { return timestampRebases_; }
  uint32_t ResyncCount() const { return resyncCount_; }

 private:
  struct TrackClock {
    bool hasRaw = false;
    bool hasPts = false;
    uint32_t lastRaw = 0;
    int64_t unwrappedMs = 0;
    double offsetMs = 0.0;
    double lastPtsMs = 0.0;
    uint64_t lastArrivalMs = 0;
  };

  static double ClampMediaTime(double mediaTimeMs);
  TimestampDecision Rebase(TrackClock& clock, uint32_t rawPtsMs,
                           double anchorMs, uint64_t nowMs,
                           const char* reason);
  TimestampDecision Advance(TrackClock& clock, uint32_t rawPtsMs,
                            uint64_t nowMs, double minimumStepMs,
                            const char* backwardReason);

  TrackClock video_;
  TrackClock audio_;
  bool videoReady_ = false;
  uint64_t firstAudioArrivalMs_ = 0;
  uint64_t plcWindowStartMs_ = 0;
  uint32_t plcInWindow_ = 0;
  uint64_t recoveryCapUntilMs_ = 0;
  bool droppingForBacklog_ = false;
  bool resyncing_ = false;
  bool resyncFlushReady_ = false;
  double resyncAnchorMs_ = 0.0;
  double nextAudioAnchorMs_ = -1.0;
  uint64_t resyncStartedMs_ = 0;
  uint64_t lastResyncMs_ = 0;
  bool repeatedIdrRequested_ = false;
  bool restartReported_ = false;
  uint32_t timestampRebases_ = 0;
  uint32_t resyncCount_ = 0;
  std::deque<uint64_t> recentResyncs_;
};
