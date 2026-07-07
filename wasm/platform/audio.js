// Event-driven Web Audio scheduler for decoded Moonlight PCM frames.
//
// auddec.cpp decodes Opus packets and posts each frame to _audReceiveFrame()
// on the main thread. Scheduling on frame arrival avoids timer throttling from
// Tizen TV overlays and removes the EMSS audio-track path.

var _audNextTime = 0.0;

function _audReceiveFrame(ptr, samplesPerFrame, channels, sampleRate) {
  var ctx = window._mlAudioCtx;
  if (!ctx) {
    return;
  }

  if (ctx.state === 'suspended') {
    try {
      ctx.resume();
    } catch (e) {}
    return;
  }

  var now = ctx.currentTime;
  var targetSeconds = (window._mlAudioTargetMs || 100) / 1000.0;

  if (_audNextTime < now) {
    _audNextTime = now;
  }

  if (_audNextTime > now + targetSeconds) {
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
}

function stopAudioScheduler() {
  _audNextTime = 0.0;
}
