#include "emss_audio_policy.hpp"

#include <algorithm>
#include <cmath>

namespace {
constexpr double kAudioStepMs = 20.0;
constexpr uint64_t kFirstVideoWaitMs = 500;
constexpr uint64_t kNetworkSilenceMs = 250;
constexpr int kNormalBacklogMs = 40;
constexpr int kRecoveryBacklogMs = 60;
constexpr uint64_t kRecoveryCapDurationMs = 10000;
constexpr uint64_t kResyncCooldownMs = 10000;
constexpr uint64_t kResyncWindowMs = 60000;
}  // namespace

void EmssAudioPolicy::Reset() {
  video_ = {};
  audio_ = {};
  videoReady_ = false;
  firstAudioArrivalMs_ = 0;
  plcWindowStartMs_ = 0;
  plcInWindow_ = 0;
  recoveryCapUntilMs_ = 0;
  droppingForBacklog_ = false;
  resyncing_ = false;
  resyncFlushReady_ = false;
  resyncAnchorMs_ = 0.0;
  nextAudioAnchorMs_ = -1.0;
  resyncStartedMs_ = 0;
  lastResyncMs_ = 0;
  repeatedIdrRequested_ = false;
  restartReported_ = false;
  timestampRebases_ = 0;
  resyncCount_ = 0;
  recentResyncs_.clear();
}

double EmssAudioPolicy::ClampMediaTime(double mediaTimeMs) {
  return std::isfinite(mediaTimeMs) && mediaTimeMs >= 0.0 ? mediaTimeMs : 0.0;
}

EmssAudioPolicy::TimestampDecision EmssAudioPolicy::Rebase(
    TrackClock& clock, uint32_t rawPtsMs, double anchorMs, uint64_t nowMs,
    const char* reason) {
  clock.hasRaw = true;
  clock.lastRaw = rawPtsMs;
  clock.unwrappedMs = rawPtsMs;
  clock.offsetMs = anchorMs - static_cast<double>(clock.unwrappedMs);
  clock.lastPtsMs = anchorMs;
  clock.hasPts = true;
  clock.lastArrivalMs = nowMs;
  timestampRebases_++;
  return {true, true, false, anchorMs, reason};
}

EmssAudioPolicy::TimestampDecision EmssAudioPolicy::Advance(
    TrackClock& clock, uint32_t rawPtsMs, uint64_t nowMs,
    double minimumStepMs, const char* backwardReason) {
  const int32_t rawDelta = static_cast<int32_t>(rawPtsMs - clock.lastRaw);
  if (rawDelta <= 0) {
    return Rebase(clock, rawPtsMs, clock.lastPtsMs + minimumStepMs, nowMs,
                  backwardReason);
  }

  const uint64_t arrivalDelta = nowMs - clock.lastArrivalMs;
  if (arrivalDelta > kNetworkSilenceMs &&
      (rawDelta + 120 < static_cast<int64_t>(arrivalDelta) ||
       rawDelta > static_cast<int64_t>(arrivalDelta) + 2000)) {
    return Rebase(clock, rawPtsMs, clock.lastPtsMs + minimumStepMs, nowMs,
                  "invalid-resume-jump");
  }

  clock.unwrappedMs += rawDelta;
  clock.lastRaw = rawPtsMs;
  double ptsMs = static_cast<double>(clock.unwrappedMs) + clock.offsetMs;
  bool clamped = false;
  if (ptsMs <= clock.lastPtsMs) {
    ptsMs = clock.lastPtsMs + minimumStepMs;
    clock.offsetMs = ptsMs - static_cast<double>(clock.unwrappedMs);
    timestampRebases_++;
    clamped = true;
  }
  clock.lastPtsMs = ptsMs;
  clock.lastArrivalMs = nowMs;
  return {true, clamped, false, ptsMs,
          clamped ? "monotonic-clamp" : "source-timestamp"};
}

EmssAudioPolicy::TimestampDecision EmssAudioPolicy::Video(
    uint32_t rawPtsMs, bool isIdr, uint64_t nowMs, double mediaTimeMs) {
  if (resyncing_) {
    if (!resyncFlushReady_) {
      return {false, false, false, video_.lastPtsMs, "resync-wait-flush"};
    }
    if (!isIdr) {
      return {false, false, false, video_.lastPtsMs, "resync-wait-idr"};
    }
    auto decision = Rebase(video_, rawPtsMs, resyncAnchorMs_, nowMs,
                           "resync-idr-anchor");
    decision.recovered = true;
    videoReady_ = true;
    resyncing_ = false;
    // The next audio frame must be explicitly tied to this new video anchor.
    audio_.hasRaw = false;
    audio_.hasPts = false;
    nextAudioAnchorMs_ = decision.ptsMs;
    firstAudioArrivalMs_ = 0;
    return decision;
  }

  if (!video_.hasRaw) {
    auto decision = Rebase(video_, rawPtsMs, ClampMediaTime(mediaTimeMs), nowMs,
                           "first-video-anchor");
    videoReady_ = true;
    return decision;
  }

  auto decision = Advance(video_, rawPtsMs, nowMs, 0.001,
                          "video-backward-jump");
  videoReady_ = true;
  return decision;
}

EmssAudioPolicy::TimestampDecision EmssAudioPolicy::Audio(
    uint32_t rawPtsMs, bool timestampValid, bool plc, uint64_t nowMs,
    double mediaTimeMs) {
  if (resyncing_) {
    return {false, false, false, audio_.lastPtsMs, "resyncing"};
  }
  if (plc) {
    ObservePlc(nowMs);
  }

  if (!audio_.hasRaw) {
    if (firstAudioArrivalMs_ == 0) {
      firstAudioArrivalMs_ = nowMs;
    }
    if (!videoReady_ && nowMs - firstAudioArrivalMs_ < kFirstVideoWaitMs) {
      return {false, false, false, 0.0, "waiting-for-first-video"};
    }
    const double anchorMs = nextAudioAnchorMs_ >= 0.0
      ? nextAudioAnchorMs_
      : std::max({
          videoReady_ ? video_.lastPtsMs : 0.0,
          ClampMediaTime(mediaTimeMs),
          audio_.hasPts ? audio_.lastPtsMs + kAudioStepMs : 0.0});
    nextAudioAnchorMs_ = -1.0;
    if (!timestampValid) {
      rawPtsMs = 0;
    }
    return Rebase(audio_, rawPtsMs, anchorMs, nowMs,
                  videoReady_ ? "first-audio-to-video" : "first-audio-to-media");
  }

  if (!timestampValid) {
    const double anchorMs = std::max({audio_.lastPtsMs + kAudioStepMs,
                                      videoReady_ ? video_.lastPtsMs : 0.0,
                                      ClampMediaTime(mediaTimeMs)});
    return Rebase(audio_, rawPtsMs, anchorMs, nowMs,
                  "invalid-audio-timestamp");
  }

  return Advance(audio_, rawPtsMs, nowMs, kAudioStepMs,
                 "audio-backward-jump");
}

int EmssAudioPolicy::BacklogLimitMs(uint64_t nowMs) const {
  return nowMs < recoveryCapUntilMs_ ? kRecoveryBacklogMs : kNormalBacklogMs;
}

void EmssAudioPolicy::ObservePlc(uint64_t nowMs) {
  if (plcWindowStartMs_ == 0 || nowMs - plcWindowStartMs_ > 1000) {
    plcWindowStartMs_ = nowMs;
    plcInWindow_ = 0;
  }
  plcInWindow_++;
  if (plcInWindow_ >= 2) {
    recoveryCapUntilMs_ = nowMs + kRecoveryCapDurationMs;
  }
}

bool EmssAudioPolicy::ShouldAppendForBacklog(int pendingMs,
                                             uint64_t nowMs) {
  // Once the live-edge cap is crossed, decoding continues but appends remain
  // gated until the encoded queue has drained to one 20 ms packet.
  if (pendingMs > BacklogLimitMs(nowMs)) {
    droppingForBacklog_ = true;
  }
  else if (pendingMs <= 20) {
    droppingForBacklog_ = false;
  }
  return !droppingForBacklog_;
}

EmssAudioPolicy::ResyncDecision EmssAudioPolicy::BeginResync(
    uint64_t nowMs, double anchorMs) {
  if (resyncing_ || (lastResyncMs_ != 0 && nowMs - lastResyncMs_ < kResyncCooldownMs)) {
    return {false, recentResyncs_.size() >= 3, resyncCount_};
  }
  while (!recentResyncs_.empty() && nowMs - recentResyncs_.front() > kResyncWindowMs) {
    recentResyncs_.pop_front();
  }
  recentResyncs_.push_back(nowMs);
  resyncing_ = true;
  resyncFlushReady_ = false;
  resyncAnchorMs_ = anchorMs;
  resyncStartedMs_ = nowMs;
  lastResyncMs_ = nowMs;
  repeatedIdrRequested_ = false;
  restartReported_ = false;
  resyncCount_++;
  return {true, recentResyncs_.size() >= 3, resyncCount_};
}

void EmssAudioPolicy::MarkResyncFlushed() {
  if (resyncing_) {
    resyncFlushReady_ = true;
  }
}

EmssAudioPolicy::RecoveryTick EmssAudioPolicy::TickRecovery(uint64_t nowMs) {
  RecoveryTick tick;
  if (!resyncing_) {
    return tick;
  }
  const uint64_t elapsed = nowMs - resyncStartedMs_;
  if (elapsed >= 2000 && !repeatedIdrRequested_) {
    repeatedIdrRequested_ = true;
    tick.requestAnotherIdr = true;
  }
  if (elapsed >= 5000 && !restartReported_) {
    restartReported_ = true;
    tick.restartRequired = true;
  }
  return tick;
}
