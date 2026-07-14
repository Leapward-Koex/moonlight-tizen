/* Low-latency Web Audio sink with an AudioWorklet/shared-memory fast path. */
(function installMoonlightAudio(root) {
  'use strict';

  if (root.MoonlightAudio) return;

  var CONTROL_LENGTH = 16;
  var WRITE_FRAME = 0;
  var READ_FRAME = 1;
  var GENERATION = 2;
  var TARGET_FRAMES = 3;
  var MAXIMUM_TARGET_FRAMES = 4;
  var MINIMUM_TARGET_FRAMES = 5;
  var PACKET_FRAMES = 6;
  var UNDERRUNS = 7;
  var OVERRUNS = 8;
  var SKIPPED_FRAMES = 9;
  var DECODED_FRAMES = 10;
  var ACTIVE = 11;
  var RENDERED_FRAMES = 12;
  var SILENT_FRAMES = 13;
  var RESTARTS = 14;
  var PROCESS_CALLS = 15;

  var nextTime = 0;
  var started = false;
  var schedulerStartedAt = 0;
  var lastResumeAttemptAt = 0;
  var scheduledSources = [];
  var workletLoadPromise = null;
  var workletReady = false;
  var workletNode = null;
  var sharedControl = null;
  var stats = {
    receivedFrames: 0,
    scheduledFrames: 0,
    droppedFrames: 0,
    droppedNoContext: 0,
    droppedClosedContext: 0,
    lateResyncs: 0,
    scheduleErrors: 0,
    maxLeadMs: 0,
    lastLeadMs: 0,
    maxProxyDelayMs: 0,
    lastProxyDelayMs: 0
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
    if (!context) return null;
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
    if (!AudioContextType) return null;
    if (!root._mlAudioCtx || root._mlAudioCtx.state === 'closed') {
      try {
        root._mlAudioCtx = new AudioContextType({ latencyHint: 'interactive', sampleRate: 48000 });
      } catch (_) {
        root._mlAudioCtx = new AudioContextType();
      }
    }
    return root._mlAudioCtx;
  }

  // Called synchronously from the Launch/Resume gesture so Tizen permits audio.
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
    Object.keys(stats).forEach(function(key) { stats[key] = 0; });
    root._mlAudioStats = stats;
  }

  function resolveWorkletUrl() {
    try {
      return new root.URL('native/audio-worklet.js', root.document.baseURI).toString();
    } catch (_) {
      return 'native/audio-worklet.js';
    }
  }

  function prepareWorklet(context) {
    if (workletReady) return Promise.resolve(true);
    if (workletLoadPromise) return workletLoadPromise;
    if (!context || !context.audioWorklet || typeof context.audioWorklet.addModule !== 'function' ||
        typeof root.AudioWorkletNode !== 'function' || typeof root.SharedArrayBuffer !== 'function' ||
        typeof root.Atomics !== 'object') {
      return Promise.resolve(false);
    }
    workletLoadPromise = context.audioWorklet.addModule(resolveWorkletUrl()).then(function() {
      workletReady = true;
      log('info', 'audio worklet module loaded', { context: snapshot(context) });
      return true;
    }).catch(function(error) {
      workletLoadPromise = null;
      log('warn', 'audio worklet unavailable; using BufferSource fallback', {
        error: error && error.message ? error.message : String(error),
        context: snapshot(context)
      });
      return false;
    });
    return workletLoadPromise;
  }

  function start(targetJitterMs) {
    if (typeof targetJitterMs === 'number' && isFinite(targetJitterMs)) {
      root._mlAudioTargetMs = Math.max(10, targetJitterMs);
    } else if (typeof root._mlAudioTargetMs !== 'number') {
      root._mlAudioTargetMs = 100;
    }
    nextTime = 0;
    started = false;
    schedulerStartedAt = nowMs();
    lastResumeAttemptAt = 0;
    resetStats();
    var context = createContext();
    log('info', 'audio scheduler started', {
      targetBufferMs: root._mlAudioTargetMs,
      context: snapshot(context)
    });
    return prepareWorklet(context);
  }

  function detachSharedRing() {
    if (sharedControl && typeof root.Atomics === 'object') {
      root.Atomics.store(sharedControl, ACTIVE, 0);
      root.Atomics.add(sharedControl, GENERATION, 1);
    }
    if (workletNode) {
      try { workletNode.disconnect(); } catch (_) {}
      workletNode = null;
    }
    sharedControl = null;
  }

  function stop() {
    detachSharedRing();
    scheduledSources.splice(0).forEach(function(source) {
      try { source.stop(0); } catch (_) {}
    });
    log('info', 'audio scheduler stopped', {
      lifetimeMs: schedulerStartedAt ? nowMs() - schedulerStartedAt : null,
      stats: getStats(),
      context: snapshot(root._mlAudioCtx)
    });
    nextTime = 0;
    started = false;
  }

  function attachSharedRing(controlPointer, pcmPointer, capacityFrames, channels, sampleRate) {
    var context = root._mlAudioCtx;
    var module = root.Module;
    if (!workletReady || !context || !module || !module.HEAP16 ||
        typeof root.SharedArrayBuffer !== 'function' || context.sampleRate !== sampleRate ||
        !(module.HEAP16.buffer instanceof root.SharedArrayBuffer)) {
      return false;
    }
    try {
      detachSharedRing();
      sharedControl = new Int32Array(module.HEAP16.buffer, controlPointer, CONTROL_LENGTH);
      workletNode = new root.AudioWorkletNode(context, 'moonlight-pcm-sink', {
        numberOfInputs: 0,
        numberOfOutputs: 1,
        outputChannelCount: [channels],
        channelCount: channels,
        channelCountMode: 'explicit',
        processorOptions: {
          sharedBuffer: module.HEAP16.buffer,
          controlByteOffset: controlPointer,
          pcmByteOffset: pcmPointer,
          capacityFrames: capacityFrames,
          channels: channels,
          streamSampleRate: sampleRate
        }
      });
      workletNode.onprocessorerror = function() {
        log('error', 'audio worklet processor error', { stats: getStats() });
      };
      workletNode.connect(context.destination);
      log('info', 'audio shared ring attached', {
        capacityFrames: capacityFrames,
        channels: channels,
        sampleRate: sampleRate,
        context: snapshot(context)
      });
      return true;
    } catch (error) {
      detachSharedRing();
      log('warn', 'audio shared ring attach failed; using BufferSource fallback', {
        error: error && error.message ? error.message : String(error)
      });
      return false;
    }
  }

  function removeScheduledSource(source) {
    var index = scheduledSources.indexOf(source);
    if (index !== -1) scheduledSources.splice(index, 1);
  }

  function receiveFrame(pointer, samplesPerFrame, channels, sampleRate, postedAtMs) {
    var context = root._mlAudioCtx;
    var receivedAt = nowMs();
    stats.receivedFrames += 1;
    if (typeof postedAtMs === 'number') {
      stats.lastProxyDelayMs = Math.max(0, receivedAt - postedAtMs);
      stats.maxProxyDelayMs = Math.max(stats.maxProxyDelayMs, stats.lastProxyDelayMs);
    }
    if (!context) { stats.droppedNoContext += 1; return; }
    if (context.state === 'closed') { stats.droppedClosedContext += 1; return; }

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
    if (!module || !module.HEAP16) { stats.droppedFrames += 1; return; }
    var now = context.currentTime;
    var targetMs = typeof root._mlAudioTargetMs === 'number' ? root._mlAudioTargetMs : 100;
    var targetSeconds = targetMs / 1000;
    var frameSeconds = samplesPerFrame / sampleRate;
    var minimumLead = Math.max(frameSeconds, 0.01);
    var maximumLead = targetSeconds + Math.max(0.05, frameSeconds * 4);

    if (!started) {
      nextTime = now + Math.max(targetSeconds, minimumLead);
      started = true;
    } else if (nextTime < now) {
      stats.lateResyncs += 1;
      nextTime = now + Math.max(targetSeconds, minimumLead);
    }
    var leadSeconds = nextTime - now;
    stats.lastLeadMs = Math.round(leadSeconds * 1000);
    stats.maxLeadMs = Math.max(stats.maxLeadMs, stats.lastLeadMs);
    if (leadSeconds > maximumLead) { stats.droppedFrames += 1; return; }

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

  function getStats() {
    var result = Object.assign({}, stats, {
      mode: workletNode ? 'audio-worklet-shared-ring' : 'buffer-source-fallback'
    });
    if (sharedControl && typeof root.Atomics === 'object') {
      var writeFrame = root.Atomics.load(sharedControl, WRITE_FRAME);
      var readFrame = root.Atomics.load(sharedControl, READ_FRAME);
      result.bufferedFrames = Math.max(0, writeFrame - readFrame);
      result.targetFrames = root.Atomics.load(sharedControl, TARGET_FRAMES);
      result.maximumTargetFrames = root.Atomics.load(sharedControl, MAXIMUM_TARGET_FRAMES);
      result.minimumTargetFrames = root.Atomics.load(sharedControl, MINIMUM_TARGET_FRAMES);
      result.packetFrames = root.Atomics.load(sharedControl, PACKET_FRAMES);
      result.underruns = root.Atomics.load(sharedControl, UNDERRUNS);
      result.overruns = root.Atomics.load(sharedControl, OVERRUNS);
      result.skippedFrames = root.Atomics.load(sharedControl, SKIPPED_FRAMES);
      result.decodedFrames = root.Atomics.load(sharedControl, DECODED_FRAMES);
      result.renderedFrames = root.Atomics.load(sharedControl, RENDERED_FRAMES);
      result.silentFrames = root.Atomics.load(sharedControl, SILENT_FRAMES);
      result.restarts = root.Atomics.load(sharedControl, RESTARTS);
      result.processCalls = root.Atomics.load(sharedControl, PROCESS_CALLS);
      if (root._mlAudioCtx && root._mlAudioCtx.sampleRate) {
        result.bufferedMs = Math.round(result.bufferedFrames * 10000 / root._mlAudioCtx.sampleRate) / 10;
        result.targetMs = Math.round(result.targetFrames * 10000 / root._mlAudioCtx.sampleRate) / 10;
      }
    }
    return result;
  }

  root._audReceiveFrame = receiveFrame;
  root.startAudioScheduler = start;
  root.stopAudioScheduler = stop;
  root.MoonlightAudio = Object.freeze({
    unlock: unlock,
    start: start,
    stop: stop,
    attachSharedRing: attachSharedRing,
    detachSharedRing: detachSharedRing,
    receiveFrame: receiveFrame,
    getStats: getStats,
    getContextSnapshot: function() { return snapshot(root._mlAudioCtx); }
  });
})(window);
