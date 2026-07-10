/*
 * Event-driven Web Audio scheduler for Moonlight's decoded PCM frames.
 *
 * auddec.cpp invokes the global _audReceiveFrame() on the browser main thread
 * and frees the source buffer as soon as that function returns. The PCM copy
 * below must therefore remain synchronous and in JavaScript.
 */
(function installMoonlightAudio(root) {
  'use strict';

  if (root.MoonlightAudio) {
    return;
  }

  var nextTime = 0;
  var started = false;
  var schedulerStartedAt = 0;
  var lastResumeAttemptAt = 0;
  var scheduledSources = [];
  var stats = {
    receivedFrames: 0,
    scheduledFrames: 0,
    droppedFrames: 0,
    droppedNoContext: 0,
    droppedClosedContext: 0,
    lateResyncs: 0,
    scheduleErrors: 0,
    maxLeadMs: 0,
    lastLeadMs: 0
  };

  function nowMs() {
    return root.performance && typeof root.performance.now === 'function'
      ? Math.round(root.performance.now())
      : Date.now();
  }

  function log(level, eventName, details) {
    if (typeof root.moonlightDebugLog === 'function') {
      root.moonlightDebugLog(level, eventName, Object.assign({ source: 'native/audio.js' }, details || {}));
    }
  }

  function snapshot(context) {
    if (!context) {
      return null;
    }
    return {
      state: context.state,
      sampleRate: context.sampleRate,
      currentTime: context.currentTime,
      baseLatency: typeof context.baseLatency === 'number' ? context.baseLatency : null,
      outputLatency: typeof context.outputLatency === 'number' ? context.outputLatency : null
    };
  }

  function createContext() {
    var AudioContextType = root.AudioContext || root.webkitAudioContext;
    if (!AudioContextType) {
      return null;
    }
    if (!root._mlAudioCtx || root._mlAudioCtx.state === 'closed') {
      root._mlAudioCtx = new AudioContextType();
    }
    return root._mlAudioCtx;
  }

  // Must be invoked directly from the user's Launch/Resume gesture. This
  // function intentionally starts resume() and a silent buffer synchronously.
  function unlock() {
    var context;
    try {
      context = createContext();
      if (!context) {
        log('warn', 'Web Audio is unavailable');
        return false;
      }

      var silentBuffer = context.createBuffer(1, 1, context.sampleRate || 48000);
      var source = context.createBufferSource();
      source.buffer = silentBuffer;
      source.connect(context.destination);
      source.start(0);

      if (context.state === 'suspended' && typeof context.resume === 'function') {
        var resumeResult = context.resume();
        if (resumeResult && typeof resumeResult.catch === 'function') {
          resumeResult.catch(function(error) {
            log('warn', 'audio unlock resume rejected', {
              error: error && error.message ? error.message : String(error),
              context: snapshot(context)
            });
          });
        }
      }
      log('info', 'audio unlock requested', { context: snapshot(context) });
      return true;
    } catch (error) {
      log('error', 'audio unlock failed', {
        error: error && error.message ? error.message : String(error),
        context: snapshot(context)
      });
      return false;
    }
  }

  function resetStats() {
    Object.keys(stats).forEach(function(key) {
      stats[key] = 0;
    });
    root._mlAudioStats = stats;
  }

  function start(targetJitterMs) {
    if (typeof targetJitterMs === 'number' && isFinite(targetJitterMs)) {
      root._mlAudioTargetMs = Math.max(0, targetJitterMs);
    } else if (typeof root._mlAudioTargetMs !== 'number') {
      root._mlAudioTargetMs = 100;
    }
    nextTime = 0;
    started = false;
    schedulerStartedAt = nowMs();
    lastResumeAttemptAt = 0;
    resetStats();
    log('info', 'audio scheduler started', {
      targetJitterMs: root._mlAudioTargetMs,
      context: snapshot(root._mlAudioCtx)
    });
  }

  function stop() {
    scheduledSources.splice(0).forEach(function(source) {
      try {
        source.stop(0);
      } catch (_) {
        // The source may already have completed.
      }
    });
    log('info', 'audio scheduler stopped', {
      lifetimeMs: schedulerStartedAt ? nowMs() - schedulerStartedAt : null,
      stats: Object.assign({}, stats),
      context: snapshot(root._mlAudioCtx)
    });
    nextTime = 0;
    started = false;
  }

  function removeScheduledSource(source) {
    var index = scheduledSources.indexOf(source);
    if (index !== -1) {
      scheduledSources.splice(index, 1);
    }
  }

  function receiveFrame(pointer, samplesPerFrame, channels, sampleRate) {
    var context = root._mlAudioCtx;
    var receivedAt = nowMs();
    stats.receivedFrames += 1;

    if (!context) {
      stats.droppedNoContext += 1;
      return;
    }
    if (context.state === 'closed') {
      stats.droppedClosedContext += 1;
      return;
    }

    if (context.state === 'suspended' && receivedAt - lastResumeAttemptAt >= 1000) {
      lastResumeAttemptAt = receivedAt;
      try {
        var resumeResult = context.resume();
        if (resumeResult && typeof resumeResult.catch === 'function') {
          resumeResult.catch(function(error) {
            log('warn', 'audio resume rejected while receiving frames', {
              error: error && error.message ? error.message : String(error)
            });
          });
        }
      } catch (resumeError) {
        log('warn', 'audio resume threw while receiving frames', {
          error: resumeError && resumeError.message ? resumeError.message : String(resumeError)
        });
      }
    }

    var module = root.Module;
    if (!module || !module.HEAP16) {
      stats.droppedFrames += 1;
      return;
    }

    var now = context.currentTime;
    var targetSeconds = (root._mlAudioTargetMs || 100) / 1000;
    var frameSeconds = samplesPerFrame / sampleRate;
    var minimumLead = Math.max(frameSeconds, 0.01);
    var maximumLead = targetSeconds + Math.max(0.05, frameSeconds * 4);

    if (!started) {
      nextTime = now + Math.max(0, targetSeconds - frameSeconds);
      started = true;
    } else if (nextTime < now) {
      stats.lateResyncs += 1;
      nextTime = now + Math.min(targetSeconds, minimumLead);
    }

    var leadSeconds = nextTime - now;
    stats.lastLeadMs = Math.round(leadSeconds * 1000);
    stats.maxLeadMs = Math.max(stats.maxLeadMs, stats.lastLeadMs);
    if (leadSeconds > maximumLead) {
      stats.droppedFrames += 1;
      return;
    }

    try {
      var audioBuffer = context.createBuffer(channels, samplesPerFrame, sampleRate);
      var heapBase = pointer >> 1;
      for (var channel = 0; channel < channels; channel += 1) {
        var channelData = audioBuffer.getChannelData(channel);
        for (var sample = 0; sample < samplesPerFrame; sample += 1) {
          channelData[sample] = module.HEAP16[heapBase + sample * channels + channel] / 32768;
        }
      }

      var source = context.createBufferSource();
      source.buffer = audioBuffer;
      source.connect(context.destination);
      source.onended = function() { removeScheduledSource(source); };
      scheduledSources.push(source);
      source.start(nextTime);
      nextTime += audioBuffer.duration;
      stats.scheduledFrames += 1;
    } catch (error) {
      stats.scheduleErrors += 1;
      log('error', 'audio frame scheduling failed', {
        error: error && error.message ? error.message : String(error),
        samplesPerFrame: samplesPerFrame,
        channels: channels,
        sampleRate: sampleRate,
        context: snapshot(context)
      });
    }
  }

  root._audReceiveFrame = receiveFrame;
  root.startAudioScheduler = start;
  root.stopAudioScheduler = stop;
  root.MoonlightAudio = Object.freeze({
    unlock: unlock,
    start: start,
    stop: stop,
    receiveFrame: receiveFrame,
    getStats: function() { return Object.assign({}, stats); },
    getContextSnapshot: function() { return snapshot(root._mlAudioCtx); }
  });
})(window);
