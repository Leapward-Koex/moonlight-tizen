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
const CONTROL_LENGTH = 12;

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
    this.started = false;
    this.stableFrames = 0;
    this.reduceAfterFrames = Math.max(config.streamSampleRate || sampleRate, 48000) * 2;
  }

  resetForGeneration(generation) {
    this.generation = generation;
    this.started = false;
    this.stableFrames = 0;
  }

  process(inputs, outputs) {
    const output = outputs[0];
    if (!output || output.length === 0) return true;
    const outputFrames = output[0].length;
    const generation = Atomics.load(this.control, GENERATION);
    if (generation !== this.generation) this.resetForGeneration(generation);
    if (Atomics.load(this.control, ACTIVE) === 0) {
      this.started = false;
      return true;
    }

    let writeFrame = Atomics.load(this.control, WRITE_FRAME);
    let readFrame = Atomics.load(this.control, READ_FRAME);
    let availableFrames = Math.max(0, writeFrame - readFrame);
    let targetFrames = Atomics.load(this.control, TARGET_FRAMES);
    const maximumTargetFrames = Atomics.load(this.control, MAXIMUM_TARGET_FRAMES);
    const minimumTargetFrames = Atomics.load(this.control, MINIMUM_TARGET_FRAMES);
    const packetFrames = Math.max(1, Atomics.load(this.control, PACKET_FRAMES));

    // If producer backlog grows, discard old PCM and stay close to the live edge.
    const liveEdgeLimit = Math.max(targetFrames + packetFrames, maximumTargetFrames);
    if (availableFrames > liveEdgeLimit + outputFrames) {
      const framesToSkip = availableFrames - liveEdgeLimit;
      readFrame += framesToSkip;
      availableFrames -= framesToSkip;
      Atomics.store(this.control, READ_FRAME, readFrame);
      Atomics.add(this.control, SKIPPED_FRAMES, framesToSkip);
    }

    if (!this.started) {
      if (availableFrames < Math.max(outputFrames, targetFrames)) return true;
      this.started = true;
    }

    const framesToCopy = Math.min(outputFrames, availableFrames);
    for (let frame = 0; frame < framesToCopy; frame += 1) {
      const ringFrame = (readFrame + frame) % this.capacityFrames;
      const pcmOffset = ringFrame * this.channels;
      for (let channel = 0; channel < output.length; channel += 1) {
        output[channel][frame] = channel < this.channels
          ? this.pcm[pcmOffset + channel] / 32768
          : 0;
      }
    }
    readFrame += framesToCopy;
    Atomics.store(this.control, READ_FRAME, readFrame);

    if (framesToCopy < outputFrames) {
      Atomics.add(this.control, UNDERRUNS, 1);
      this.started = false;
      this.stableFrames = 0;
      targetFrames = Math.min(maximumTargetFrames, targetFrames + packetFrames);
      Atomics.store(this.control, TARGET_FRAMES, targetFrames);
    } else {
      this.stableFrames += outputFrames;
      if (this.stableFrames >= this.reduceAfterFrames && targetFrames > minimumTargetFrames) {
        Atomics.store(
          this.control,
          TARGET_FRAMES,
          Math.max(minimumTargetFrames, targetFrames - packetFrames)
        );
        this.stableFrames = 0;
      }
    }
    return true;
  }
}

registerProcessor('moonlight-pcm-sink', MoonlightPcmSink);
