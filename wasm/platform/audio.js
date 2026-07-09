// Event-driven Web Audio scheduler for decoded Moonlight PCM frames.
//
// auddec.cpp decodes Opus packets and posts each frame to _audReceiveFrame()
// on the main thread. Scheduling on frame arrival avoids timer throttling from
// Tizen TV overlays and removes the EMSS audio-track path.

var _audNextTime = 0.0;
var _audStarted = false;
var _audSchedulerStartMs = 0;
var _audFirstFrameMs = 0;
var _audFirstScheduleMs = 0;
var _audLastContextState = '';
var _audLastResumeAttemptMs = 0;
var _audStats = {
  receivedFrames: 0,
  scheduledFrames: 0,
  droppedFrames: 0,
  droppedNoContext: 0,
  droppedClosedContext: 0,
  lateResyncs: 0,
  startErrors: 0,
  maxLeadMs: 0,
  lastLeadMs: 0
};

function _audNowMs() {
  if (typeof performance !== 'undefined' && typeof performance.now === 'function') {
    return Math.round(performance.now());
  }
  return Date.now();
}

function _audLog(level, eventName, details) {
  if (typeof window.moonlightDebugLog === 'function') {
    window.moonlightDebugLog(level, eventName, Object.assign({
      source: 'audio.js'
    }, details || {}));
  }
}

function _audContextSnapshot(ctx) {
  if (!ctx) {
    return null;
  }
  return {
    state: ctx.state,
    sampleRate: ctx.sampleRate,
    currentTime: ctx.currentTime,
    baseLatency: typeof ctx.baseLatency === 'number' ? ctx.baseLatency : null,
    outputLatency: typeof ctx.outputLatency === 'number' ? ctx.outputLatency : null
  };
}

function _audUpdateStats(leadSeconds) {
  if (leadSeconds > 0) {
    _audStats.maxLeadMs = Math.max(_audStats.maxLeadMs, Math.round(leadSeconds * 1000));
  }
  _audStats.lastLeadMs = Math.round(leadSeconds * 1000);
  window._mlAudioStats = _audStats;
}

function _audReceiveFrame(ptr, samplesPerFrame, channels, sampleRate) {
  var ctx = window._mlAudioCtx;
  var receiveMs = _audNowMs();
  _audStats.receivedFrames++;

  if (!ctx) {
    _audStats.droppedNoContext++;
    if (_audStats.droppedNoContext <= 3 || (_audStats.droppedNoContext % 100) === 0) {
      _audLog('warn', 'audio frame dropped without AudioContext', {
        droppedNoContext: _audStats.droppedNoContext,
        receivedFrames: _audStats.receivedFrames,
        schedulerStartedMsAgo: _audSchedulerStartMs ? receiveMs - _audSchedulerStartMs : null
      });
    }
    return;
  }

  if (ctx.state === 'closed') {
    _audStats.droppedClosedContext++;
    if (_audStats.droppedClosedContext <= 3 || (_audStats.droppedClosedContext % 100) === 0) {
      _audLog('error', 'audio frame dropped because AudioContext is closed', {
        droppedClosedContext: _audStats.droppedClosedContext,
        receivedFrames: _audStats.receivedFrames,
        context: _audContextSnapshot(ctx)
      });
    }
    return;
  }

  if (_audLastContextState !== ctx.state) {
    _audLog(ctx.state === 'running' ? 'info' : 'warn', 'audio context state observed', {
      previousState: _audLastContextState || null,
      currentState: ctx.state,
      context: _audContextSnapshot(ctx)
    });
    _audLastContextState = ctx.state;
  }

  if (ctx.state === 'suspended') {
    try {
      if (receiveMs - _audLastResumeAttemptMs >= 1000) {
        _audLastResumeAttemptMs = receiveMs;
        _audLog('warn', 'audio context suspended while audio frames are arriving; requesting resume', {
          receivedFrames: _audStats.receivedFrames,
          context: _audContextSnapshot(ctx)
        });
      }
      var resumePromise = ctx.resume();
      if (resumePromise && typeof resumePromise.catch === 'function') {
        resumePromise.then(function() {
          _audLog('info', 'audio context resume resolved from frame receiver', {
            context: _audContextSnapshot(ctx)
          });
        }).catch(function(error) {
          _audLog('error', 'audio context resume rejected from frame receiver', {
            error: error && error.message ? error.message : String(error),
            context: _audContextSnapshot(ctx)
          });
        });
      }
    } catch (e) {
      _audLog('error', 'audio context resume threw from frame receiver', {
        error: e && e.message ? e.message : String(e),
        context: _audContextSnapshot(ctx)
      });
    }
  }

  var now = ctx.currentTime;
  var targetSeconds = (window._mlAudioTargetMs || 100) / 1000.0;
  var frameSeconds = samplesPerFrame / sampleRate;
  var minScheduleLead = Math.max(frameSeconds, 0.01);
  var maxScheduleLead = targetSeconds + Math.max(0.05, frameSeconds * 4);

  if (!_audFirstFrameMs) {
    _audFirstFrameMs = receiveMs;
    _audLog('info', 'first audio frame received by scheduler', {
      schedulerStartedMsAgo: _audSchedulerStartMs ? receiveMs - _audSchedulerStartMs : null,
      samplesPerFrame: samplesPerFrame,
      channels: channels,
      sampleRate: sampleRate,
      frameDurationMs: Math.round(frameSeconds * 1000),
      targetJitterMs: Math.round(targetSeconds * 1000),
      context: _audContextSnapshot(ctx)
    });
  }

  if (!_audStarted) {
    _audNextTime = now + Math.max(0, targetSeconds - frameSeconds);
    _audStarted = true;
    _audLog('info', 'audio scheduler primed', {
      contextCurrentTime: now,
      firstScheduledTime: _audNextTime,
      initialLeadMs: Math.round((_audNextTime - now) * 1000),
      targetJitterMs: Math.round(targetSeconds * 1000),
      frameDurationMs: Math.round(frameSeconds * 1000)
    });
  } else if (_audNextTime < now) {
    var nextTimeBeforeResync = _audNextTime;
    _audStats.lateResyncs++;
    _audNextTime = now + Math.min(targetSeconds, minScheduleLead);
    if (_audStats.lateResyncs <= 5 || (_audStats.lateResyncs % 100) === 0) {
      _audLog('warn', 'audio scheduler late resync', {
        lateResyncs: _audStats.lateResyncs,
        contextCurrentTime: now,
        nextTimeBeforeResync: nextTimeBeforeResync,
        targetJitterMs: Math.round(targetSeconds * 1000),
        minScheduleLeadMs: Math.round(minScheduleLead * 1000),
        receivedFrames: _audStats.receivedFrames,
        scheduledFrames: _audStats.scheduledFrames
      });
    }
  }

  var leadSeconds = _audNextTime - now;
  _audUpdateStats(leadSeconds);

  if (leadSeconds > maxScheduleLead) {
    _audStats.droppedFrames++;
    if (_audStats.droppedFrames <= 5 || (_audStats.droppedFrames % 100) === 0) {
      _audLog('warn', 'audio frame dropped because schedule lead is too large', {
        droppedFrames: _audStats.droppedFrames,
        leadMs: Math.round(leadSeconds * 1000),
        maxLeadMs: Math.round(maxScheduleLead * 1000),
        targetJitterMs: Math.round(targetSeconds * 1000),
        receivedFrames: _audStats.receivedFrames,
        scheduledFrames: _audStats.scheduledFrames
      });
    }
    return;
  }

  try {
    var audioBuffer = ctx.createBuffer(channels, samplesPerFrame, sampleRate);
    var heapBase = ptr >> 1;
    for (var channel = 0; channel < channels; channel++) {
      var channelData = audioBuffer.getChannelData(channel);
      for (var sample = 0; sample < samplesPerFrame; sample++) {
        channelData[sample] = Module.HEAP16[heapBase + sample * channels + channel] * (1.0 / 32768.0);
      }
    }

    var scheduledTime = _audNextTime;
    var source = ctx.createBufferSource();
    source.buffer = audioBuffer;
    source.connect(ctx.destination);
    source.start(scheduledTime);
    _audNextTime += audioBuffer.duration;
    _audStats.scheduledFrames++;

    if (!_audFirstScheduleMs) {
      _audFirstScheduleMs = _audNowMs();
      _audLog('info', 'first audio buffer scheduled', {
        schedulerStartedMsAgo: _audSchedulerStartMs ? _audFirstScheduleMs - _audSchedulerStartMs : null,
        firstFrameReceivedMsAgo: _audFirstFrameMs ? _audFirstScheduleMs - _audFirstFrameMs : null,
        scheduledStartTime: scheduledTime,
        contextCurrentTime: now,
        leadMs: Math.round((scheduledTime - now) * 1000),
        durationMs: Math.round(audioBuffer.duration * 1000),
        context: _audContextSnapshot(ctx)
      });
    }
  } catch (e) {
    _audStats.startErrors++;
    if (_audStats.startErrors <= 5 || (_audStats.startErrors % 100) === 0) {
      _audLog('error', 'audio buffer schedule failed', {
        startErrors: _audStats.startErrors,
        error: e && e.message ? e.message : String(e),
        samplesPerFrame: samplesPerFrame,
        channels: channels,
        sampleRate: sampleRate,
        context: _audContextSnapshot(ctx)
      });
    }
  }
}

function startAudioScheduler() {
  _audNextTime = 0.0;
  _audStarted = false;
  _audSchedulerStartMs = _audNowMs();
  _audFirstFrameMs = 0;
  _audFirstScheduleMs = 0;
  _audLastContextState = window._mlAudioCtx ? window._mlAudioCtx.state : '';
  _audLastResumeAttemptMs = 0;
  _audStats.receivedFrames = 0;
  _audStats.scheduledFrames = 0;
  _audStats.droppedFrames = 0;
  _audStats.droppedNoContext = 0;
  _audStats.droppedClosedContext = 0;
  _audStats.lateResyncs = 0;
  _audStats.startErrors = 0;
  _audStats.maxLeadMs = 0;
  _audStats.lastLeadMs = 0;
  window._mlAudioStats = _audStats;
  _audLog('info', 'audio scheduler started', {
    targetJitterMs: window._mlAudioTargetMs || 100,
    context: _audContextSnapshot(window._mlAudioCtx)
  });
}

function stopAudioScheduler() {
  _audLog('info', 'audio scheduler stopped', {
    lifetimeMs: _audSchedulerStartMs ? _audNowMs() - _audSchedulerStartMs : null,
    firstFrameDelayMs: _audFirstFrameMs && _audSchedulerStartMs ? _audFirstFrameMs - _audSchedulerStartMs : null,
    firstScheduleDelayMs: _audFirstScheduleMs && _audSchedulerStartMs ? _audFirstScheduleMs - _audSchedulerStartMs : null,
    stats: Object.assign({}, _audStats),
    context: _audContextSnapshot(window._mlAudioCtx)
  });
  _audNextTime = 0.0;
  _audStarted = false;
}
