import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const workspace = path.resolve(testDirectory, '..', '..', '..');
const sourcePath = path.join(workspace, 'flutter_ui', 'web', 'native', 'audio.js');
const workletSourcePath = path.join(workspace, 'flutter_ui', 'web', 'native', 'audio-worklet.js');
const decoderSourcePath = path.join(workspace, 'wasm', 'auddec.cpp');
const starts = [];
const loadedModules = [];
let constructedNode;

class FakeSource {
  connect() {}
  start(when) { starts.push(when); }
  stop() {}
}

class FakeContext {
  constructor(options) {
    this.options = options;
    this.state = 'running';
    this.sampleRate = 48000;
    this.currentTime = 1;
    this.destination = {};
    this.audioWorklet = {
      addModule: async (url) => { loadedModules.push(String(url)); }
    };
  }
  createBuffer(channels, frames, rate) {
    return {
      duration: frames / rate,
      getChannelData: () => new Float32Array(frames)
    };
  }
  createBufferSource() { return new FakeSource(); }
  resume() { return Promise.resolve(); }
}

class FakeWorkletNode {
  constructor(context, name, options) {
    constructedNode = { context, name, options };
  }
  connect() {}
  disconnect() {}
}

const memory = new SharedArrayBuffer(4096);
const context = vm.createContext({
  console,
  Promise,
  Date,
  URL,
  SharedArrayBuffer,
  Atomics,
  Int16Array,
  Int32Array,
  Float32Array,
  AudioContext: FakeContext,
  AudioWorkletNode: FakeWorkletNode,
  Module: { HEAP16: new Int16Array(memory) },
  document: { baseURI: 'https://moonlight.invalid/' },
  performance: { now: () => 1000 }
});
context.window = context;
vm.runInContext(fs.readFileSync(sourcePath, 'utf8'), context, { filename: sourcePath });

await context.MoonlightAudio.start(100);
assert.equal(loadedModules.length, 1);
assert.match(loadedModules[0], /native\/audio-worklet\.js$/);
assert.equal(context._mlAudioCtx.options.latencyHint, 'interactive');

const controlPointer = 0;
const pcmPointer = 64;
assert.equal(context.MoonlightAudio.attachSharedRing(controlPointer, pcmPointer, 256, 2, 48000), true);
assert.equal(constructedNode.name, 'moonlight-pcm-sink');
assert.deepEqual(Array.from(constructedNode.options.outputChannelCount), [2]);

const control = new Int32Array(memory, controlPointer, 16);
Atomics.store(control, 11, 1);
context.MoonlightAudio.stop();
assert.equal(Atomics.load(control, 11), 0);

// The BufferSource fallback honors the configured startup target too. Without
// this lead it repeatedly resynchronized to a single packet after small gaps.
await context.MoonlightAudio.start(100);
context.MoonlightAudio.receiveFrame(256, 480, 2, 48000, 995);
assert.ok(Math.abs(starts.at(-1) - 1.1) < 0.0001, `fallback lead was ${starts.at(-1) - 1}s`);
assert.equal(context.MoonlightAudio.getStats().lastProxyDelayMs, 5);

// Exercise the processor itself, including interleaved PCM conversion and an
// underrun. A short quantum must not be partially consumed because that would
// splice PCM to silence in the middle of an output buffer.
let WorkletProcessor;
const workletContext = vm.createContext({
  SharedArrayBuffer,
  Atomics,
  Int16Array,
  Int32Array,
  Float32Array,
  sampleRate: 48000,
  AudioWorkletProcessor: class {},
  registerProcessor: (name, processor) => {
    assert.equal(name, 'moonlight-pcm-sink');
    WorkletProcessor = processor;
  }
});
vm.runInContext(fs.readFileSync(workletSourcePath, 'utf8'), workletContext, {
  filename: workletSourcePath
});

const workletMemory = new SharedArrayBuffer(4096);
const workletControl = new Int32Array(workletMemory, 0, 16);
const workletPcm = new Int16Array(workletMemory, 128, 512 * 2);
for (let frame = 0; frame < 384; frame += 1) {
  workletPcm[frame * 2] = 1000 + frame;
  workletPcm[frame * 2 + 1] = -1000 - frame;
}
Atomics.store(workletControl, 0, 384); // write frame
Atomics.store(workletControl, 3, 256); // selected target
Atomics.store(workletControl, 4, 256); // maximum target
Atomics.store(workletControl, 5, 128); // minimum target (diagnostic)
Atomics.store(workletControl, 6, 128); // packet frames
Atomics.store(workletControl, 11, 1); // active

const processor = new WorkletProcessor({
  processorOptions: {
    sharedBuffer: workletMemory,
    controlByteOffset: 0,
    pcmByteOffset: 128,
    capacityFrames: 512,
    channels: 2,
    streamSampleRate: 48000
  }
});
processor.fadeInRemaining = 0;
let output = [[new Float32Array(128), new Float32Array(128)]];
assert.equal(processor.process([], output), true);
assert.equal(Atomics.load(workletControl, 1), 128);
assert.ok(Math.abs(output[0][0][0] - (1000 / 32768)) < 1e-7);
assert.ok(Math.abs(output[0][1][0] - (-1000 / 32768)) < 1e-7);
assert.equal(Atomics.load(workletControl, 12), 128); // rendered frames
assert.equal(Atomics.load(workletControl, 7), 0); // underruns

Atomics.store(workletControl, 1, 320);
const readBeforeUnderrun = Atomics.load(workletControl, 1);
output = [[new Float32Array(128), new Float32Array(128)]];
assert.equal(processor.process([], output), true);
assert.equal(Atomics.load(workletControl, 1), readBeforeUnderrun);
assert.equal(Atomics.load(workletControl, 7), 1);
assert.equal(Atomics.load(workletControl, 14), 1); // restarts
assert.equal(output[0][0][127], 0);

const decoderSource = fs.readFileSync(decoderSourcePath, 'utf8');
assert.match(decoderSource, /AtomicStore\(kTargetFrames, requestedFrames\)/);
assert.doesNotMatch(decoderSource, /AtomicStore\(kTargetFrames, minimumFrames\)/);

console.log('Moonlight audio contract tests passed.');
