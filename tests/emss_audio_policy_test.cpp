#include "emss_audio_policy.hpp"

#ifdef NDEBUG
#undef NDEBUG
#endif
#include <cassert>
#include <cmath>
#include <iostream>

static void Near(double actual, double expected) {
  assert(std::fabs(actual - expected) < 0.01);
}

int main() {
  EmssAudioPolicy policy;
  policy.Reset();

  // Steady 20 ms source timestamps and first-audio video anchoring.
  Near(policy.Video(1000, true, 100, 0).ptsMs, 0);
  Near(policy.Video(1020, false, 120, 20).ptsMs, 20);
  Near(policy.Audio(0, true, false, 5300, 20).ptsMs, 20);
  Near(policy.Audio(20, true, false, 5320, 40).ptsMs, 40);

  // A 5.3 second late audio start at timestamp zero joins the live video edge.
  policy.Reset();
  policy.Video(5000, true, 0, 0);
  Near(policy.Video(10300, false, 5300, 5300).ptsMs, 5300);
  Near(policy.Audio(0, true, false, 5300, 5300).ptsMs, 5300);

  // PLC/reordering stays strictly increasing and temporarily widens the cap.
  auto plc1 = policy.Audio(20, true, true, 5320, 5320);
  auto plc2 = policy.Audio(40, true, true, 5340, 5340);
  assert(plc2.ptsMs > plc1.ptsMs);
  assert(policy.BacklogLimitMs(5340) == 60);
  assert(policy.BacklogLimitMs(15341) == 40);
  auto reordered = policy.Audio(20, true, false, 5360, 5360);
  assert(reordered.rebased && reordered.ptsMs > plc2.ptsMs);

  // Twenty second gaps preserve advancing timestamps and rebase restarted ones.
  policy.Reset();
  policy.Video(0, true, 1, 0);
  policy.Audio(0, true, false, 1, 0);
  Near(policy.Audio(20000, true, false, 20001, 20000).ptsMs, 20000);
  auto restarted = policy.Audio(0, true, false, 40001, 40000);
  assert(restarted.rebased && restarted.ptsMs > 20000);

  // Dropped frames at 120 fps advance by capture time, not frame count.
  policy.Reset();
  policy.Video(100, true, 0, 0);
  Near(policy.Video(125, false, 25, 25).ptsMs, 25);

  // 32-bit rollover unwraps; invalid timestamps re-anchor monotonically.
  policy.Reset();
  policy.Video(0xfffffff0u, true, 0, 0);
  Near(policy.Video(0x00000004u, false, 20, 20).ptsMs, 20);
  policy.Audio(10, true, false, 20, 20);
  auto invalid = policy.Audio(0, false, false, 40, 40);
  assert(invalid.rebased && invalid.ptsMs >= 40);

  // Backlog hysteresis drains to 20 ms before appending resumes.
  assert(!policy.ShouldAppendForBacklog(61, 50));
  assert(!policy.ShouldAppendForBacklog(40, 60));
  assert(policy.ShouldAppendForBacklog(20, 70));

  // Resync cooldown, degraded warning threshold, and failed IDR escalation.
  policy.Reset();
  auto first = policy.BeginResync(1000, 20);
  assert(first.started && !first.degraded);
  assert(policy.TickRecovery(3000).requestAnotherIdr);
  assert(policy.TickRecovery(6000).restartRequired);
  assert(!policy.Video(8990, true, 6050, 20).append);
  policy.MarkResyncFlushed();
  auto idr = policy.Video(9000, true, 6100, 20);
  assert(idr.append && idr.recovered);
  assert(!policy.BeginResync(9000, 40).started);
  policy.BeginResync(12000, 40);
  policy.MarkResyncFlushed();
  policy.Video(10000, true, 12010, 40);
  auto third = policy.BeginResync(23000, 60);
  assert(third.started && third.degraded);

  std::cout << "EMSS audio policy tests passed\n";
  return 0;
}
