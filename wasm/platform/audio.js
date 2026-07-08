// Event-driven Web Audio scheduler for decoded Moonlight PCM frames.
//
// auddec.cpp decodes Opus packets and posts each frame to _audReceiveFrame()
// on the main thread. Scheduling on frame arrival avoids timer throttling from
// Tizen TV overlays and removes the EMSS audio-track path.

var _audNextTime = 0.0;
var _audStarted = false;

function _audReceiveFrame(ptr, samplesPerFrame, channels, sampleRate) {
  var ctx = window._mlAudioCtx;
  if (!ctx) {
    return;
  }

  if (ctx.state === 'closed') {
    return;
  }

  if (ctx.state === 'suspended') {
    try {
      var resumePromise = ctx.resume();
      if (resumePromise && typeof resumePromise.catch === 'function') {
        resumePromise.catch(function() {});
      }
    } catch (e) {}
  }

  var now = ctx.currentTime;
  var targetSeconds = (window._mlAudioTargetMs || 100) / 1000.0;
  var frameSeconds = samplesPerFrame / sampleRate;

  if (!_audStarted) {
    _audNextTime = now + Math.max(0, targetSeconds - frameSeconds);
    _audStarted = true;
  } else if (_audNextTime < now) {
    _audNextTime = now + Math.min(targetSeconds, Math.max(frameSeconds, 0.02));
  }

  if (_audNextTime > now + targetSeconds + frameSeconds) {
    return;
  }

  var audioBuffer = ctx.createBuffer(channels, samplesPerFrame, sampleRate);
  var heapBase = ptr >> 1;
  for (var channel = 0; channel < channels; channel++) {
    var channelData = audioBuffer.getChannelData(channel);
    for (var sample = 0; sample < samplesPerFrame; sample++) {
      channelData[sample] = Module.HEAP16[heapBase + sample * channels + channel] * (1.0 / 32768.0);
    }
  }

  var source = ctx.createBufferSource();
  source.buffer = audioBuffer;
  source.connect(ctx.destination);
  source.start(_audNextTime);
  _audNextTime += audioBuffer.duration;
}

function startAudioScheduler() {
  _audNextTime = 0.0;
  _audStarted = false;
}

function stopAudioScheduler() {
  _audNextTime = 0.0;
  _audStarted = false;
}
