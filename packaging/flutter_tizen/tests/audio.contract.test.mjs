import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const workspace = path.resolve(testDirectory, '..', '..', '..');
const sourcePath = path.join(workspace, 'flutter_ui', 'web', 'native', 'audio.js');
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

const control = new Int32Array(memory, controlPointer, 12);
Atomics.store(control, 11, 1);
context.MoonlightAudio.stop();
assert.equal(Atomics.load(control, 11), 0);

// The BufferSource fallback treats the configured value as a maximum and
// starts at one packet of lead instead of intentionally adding 100 ms.
await context.MoonlightAudio.start(100);
context.MoonlightAudio.receiveFrame(256, 480, 2, 48000, 995);
assert.ok(starts.at(-1) <= 1.011, `fallback lead was ${starts.at(-1) - 1}s`);
assert.equal(context.MoonlightAudio.getStats().lastProxyDelayMs, 5);

console.log('Moonlight audio contract tests passed.');
