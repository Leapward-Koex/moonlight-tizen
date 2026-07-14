/* global AudioWorkletProcessor, registerProcessor, sampleRate */
'use strict';

const WRITE_FRAME = 0;
const READ_FRAME = 1;
const GENERATION = 2;
const TARGET_FRAMES = 3;
const MAXIMUM_TARGET_FRAMES = 4;
const MINIMUM_TARGET_FRAMES = 5;
const PACKET_FRAMES = 6;
const UNDERRUNS = 7;
const SKIPPED_FRAMES = 9;
const ACTIVE = 11;
const RENDERED_FRAMES = 12;
const SILENT_FRAMES = 13;
const RESTARTS = 14;
const PROCESS_CALLS = 15;
const CONTROL_LENGTH = 16;

class MoonlightPcmSink extends AudioWorkletProcessor {
  constructor(options) {
    super();
    const config = options.processorOptions;
    this.control = new Int32Array(config.sharedBuffer, config.controlByteOffset, CONTROL_LENGTH);
    this.capacityFrames = config.capacityFrames;
    this.channels = config.channels;
    this.pcm = new Int16Array(
      config.sharedBuffer,
      config.pcmByteOffset,
      this.capacityFrames * this.channels
    );
    this.generation = Atomics.load(this.control, GENERATION);
    this.streamSampleRate = config.streamSampleRate || sampleRate;
    this.started = false;
    this.starved = false;
    this.fadeFrames = Math.max(1, Math.round(this.streamSampleRate * 0.003));
    this.fadeInRemaining = this.fadeFrames;
    this.lastOutput = new Float32Array(Math.max(this.channels, 8));
  }

  resetForGeneration(generation) {
    this.generation = generation;
    this.started = false;
    this.starved = false;
    this.fadeInRemaining = this.fadeFrames;
    this.lastOutput.fill(0);
  }

  process(inputs, outputs) {
    const output = outputs[0];
    if (!output || output.length === 0) return true;
    const outputFrames = output[0].length;
    for (let channel = 0; channel < output.length; channel += 1) {
      output[channel].fill(0);
    }
    const generation = Atomics.load(this.control, GENERATION);
    if (generation !== this.generation) this.resetForGeneration(generation);
    if (Atomics.load(this.control, ACTIVE) === 0) {
      this.started = false;
      return true;
    }
    Atomics.add(this.control, PROCESS_CALLS, 1);

    let writeFrame = Atomics.load(this.control, WRITE_FRAME);
    let readFrame = Atomics.load(this.control, READ_FRAME);
    let availableFrames = Math.max(0, writeFrame - readFrame);
    const targetFrames = Math.max(outputFrames, Atomics.load(this.control, TARGET_FRAMES));
    const maximumTargetFrames = Math.max(targetFrames, Atomics.load(this.control, MAXIMUM_TARGET_FRAMES));
    const packetFrames = Math.max(1, Atomics.load(this.control, PACKET_FRAMES));

    // Decoder callbacks can arrive in short bursts. Do not interpret a normal
    // burst as stale audio: the old target-sized cap caused arbitrary PCM
    // splices on nearly every burst. Only recover when backlog exceeds the
    // chosen target by at least 50 ms (or four complete Opus packets), and keep
    // packet alignment when moving to the live edge.
    const recoveryMargin = Math.max(packetFrames * 4, Math.round(this.streamSampleRate * 0.05));
    const liveEdgeLimit = maximumTargetFrames + recoveryMargin;
    if (availableFrames > liveEdgeLimit + outputFrames) {
      const excessFrames = availableFrames - targetFrames;
      const framesToSkip = Math.floor(excessFrames / packetFrames) * packetFrames;
      readFrame += framesToSkip;
      availableFrames -= framesToSkip;
      Atomics.store(this.control, READ_FRAME, readFrame);
      Atomics.add(this.control, SKIPPED_FRAMES, framesToSkip);
      this.fadeInRemaining = this.fadeFrames;
    }

    if (!this.started) {
      if (availableFrames < Math.max(outputFrames, targetFrames)) return true;
      this.started = true;
      if (this.starved) {
        this.starved = false;
        this.fadeInRemaining = this.fadeFrames;
      }
    }

    // Never consume half a render quantum. The previous implementation copied
    // whatever remained and then switched to silence mid-buffer, creating a
    // sharp discontinuity. Fade the last sample to silence and restart only
    // after the configured target has accumulated again.
    if (availableFrames < outputFrames) {
      Atomics.add(this.control, UNDERRUNS, 1);
      Atomics.add(this.control, RESTARTS, 1);
      Atomics.add(this.control, SILENT_FRAMES, outputFrames);
      const fadeOutFrames = Math.min(outputFrames, this.fadeFrames);
      for (let frame = 0; frame < fadeOutFrames; frame += 1) {
        const gain = 1 - ((frame + 1) / fadeOutFrames);
        for (let channel = 0; channel < output.length; channel += 1) {
          output[channel][frame] = this.lastOutput[channel] * Math.max(0, gain);
        }
      }
      this.lastOutput.fill(0);
      this.started = false;
      this.starved = true;
      this.fadeInRemaining = this.fadeFrames;
      return true;
    }

    const crossfadeFrom = this.lastOutput.slice();
    let fadeRemaining = this.fadeInRemaining;
    for (let frame = 0; frame < outputFrames; frame += 1) {
      const ringFrame = (readFrame + frame) % this.capacityFrames;
      const pcmOffset = ringFrame * this.channels;
      const fadeGain = fadeRemaining > 0
        ? (this.fadeFrames - fadeRemaining + 1) / this.fadeFrames
        : 1;
      for (let channel = 0; channel < output.length; channel += 1) {
        const sample = channel < this.channels
          ? this.pcm[pcmOffset + channel] / 32768
          : 0;
        output[channel][frame] = fadeRemaining > 0
          ? (sample * fadeGain) + (crossfadeFrom[channel] * (1 - fadeGain))
          : sample;
      }
      if (fadeRemaining > 0) fadeRemaining -= 1;
    }
    this.fadeInRemaining = fadeRemaining;
    for (let channel = 0; channel < output.length; channel += 1) {
      this.lastOutput[channel] = output[channel][outputFrames - 1];
    }
    readFrame += outputFrames;
    Atomics.store(this.control, READ_FRAME, readFrame);
    Atomics.add(this.control, RENDERED_FRAMES, outputFrames);
    return true;
  }
}

registerProcessor('moonlight-pcm-sink', MoonlightPcmSink);
