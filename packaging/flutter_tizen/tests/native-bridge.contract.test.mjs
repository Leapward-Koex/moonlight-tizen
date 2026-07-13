import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const workspace = path.resolve(testDirectory, '..', '..', '..');
const bridgePath = path.join(workspace, 'flutter_ui', 'web', 'native', 'moonlight_native.js');
let browserKeyDownListener;

// Every native helper must be safe to evaluate in an ordinary browser where
// neither `tizen` nor Samsung's `webapis` globals exist.
const browserContext = vm.createContext({
  console,
  setTimeout,
  clearTimeout,
  Promise,
  Uint8Array,
  TextEncoder,
  navigator: { getGamepads: () => [] },
  screen: { width: 1280, height: 720 },
  location: { reload() {} },
  document: {
    addEventListener(type, listener) {
      if (type === 'keydown') browserKeyDownListener = listener;
    },
    getElementById() { return null; }
  },
  requestAnimationFrame() { return 1; },
  cancelAnimationFrame() {},
  dispatchEvent() { return true; },
  CustomEvent: class CustomEvent {},
  MouseEvent: class MouseEvent {}
});
browserContext.window = browserContext;
for (const filename of ['audio.js', 'tizen_platform.js', 'input.js']) {
  const filenamePath = path.join(workspace, 'flutter_ui', 'web', 'native', filename);
  vm.runInContext(fs.readFileSync(filenamePath, 'utf8'), browserContext, { filename: filenamePath });
}
assert.equal(browserContext.MoonlightTizenPlatform.isTizen(), false);
assert.equal(browserContext.MoonlightTizenPlatform.getPlatformInfo().supportsNativeStreaming, false);
assert.equal(browserContext.MoonlightTizenPlatform.getPlatformInfo().supportsNativeAudio, false);
assert.equal(browserContext.MoonlightAudio.unlock(), false);
assert.equal(browserContext.MoonlightInput.setMode('ui'), 'ui');
assert.equal(typeof browserKeyDownListener, 'function');

const browserInputEvents = [];
browserContext.MoonlightInput.setSink((event) => browserInputEvents.push(event));
function browserKeyEvent(key, keyCode) {
  return {
    key,
    keyCode,
    which: keyCode,
    repeat: false,
    preventDefaultCalled: false,
    stopImmediatePropagationCalled: false,
    preventDefault() { this.preventDefaultCalled = true; },
    stopImmediatePropagation() { this.stopImmediatePropagationCalled = true; }
  };
}
for (const [key, keyCode] of [
  ['ArrowUp', 38],
  ['ArrowDown', 40],
  ['ArrowLeft', 37],
  ['ArrowRight', 39],
  ['Enter', 13]
]) {
  const event = browserKeyEvent(key, keyCode);
  browserKeyDownListener(event);
  assert.equal(event.preventDefaultCalled, false, `${key} must reach Flutter focus navigation`);
}
assert.equal(browserInputEvents.length, 0, 'remote navigation keys must not bypass Flutter focus');
const backEvent = browserKeyEvent('XF86Back', 10009);
browserKeyDownListener(backEvent);
assert.equal(backEvent.preventDefaultCalled, true, 'Tizen Back remains a normalized action');
assert.equal(browserInputEvents.at(-1).action, 'back');

class FakeElement {
  constructor(id = '') {
    this.id = id;
    this.hidden = false;
    this.textContent = '';
    this.dataset = {};
    this.style = {};
    this.children = [];
    this.focused = false;
  }

  focus() { this.focused = true; }
  blur() { this.focused = false; }
  appendChild(child) { this.children.push(child); }
  dispatchEvent() { return true; }
}

const elementIds = [
  'wasm_module',
  'stream-loading',
  'stream-progress',
  'stream-warning',
  'stream-statistics',
  'stream-transient',
  'stream-fatal',
  'stream-fatal-message',
  'stream-fatal-back'
];
const elements = Object.fromEntries(elementIds.map((id) => [id, new FakeElement(id)]));
const documentElement = new FakeElement('html');
const document = {
  baseURI: 'https://moonlight.invalid/',
  documentElement,
  body: new FakeElement('body'),
  getElementById(id) { return elements[id] || null; },
  createElement() { return new FakeElement(); }
};

globalThis.window = globalThis;
globalThis.document = document;
globalThis.CustomEvent = class CustomEvent {
  constructor(type, init) { this.type = type; this.detail = init && init.detail; }
};
globalThis.dispatchEvent = () => true;
Object.defineProperty(globalThis, 'navigator', {
  configurable: true,
  value: { getGamepads: () => [] }
});
globalThis.location = { reload() {} };
const requestedInputActions = [];
globalThis.MoonlightInput = {
  mode: 'ui',
  setMode(mode) { this.mode = mode; return mode; },
  setSink() {},
  requestAction(action, source) {
    requestedInputActions.push({ action, source });
    return true;
  },
  connectedGamepadMask() { return 5; }
};
globalThis.MoonlightAudio = {
  unlock() { return true; },
  start() {},
  stop() {}
};
globalThis.MoonlightTizenPlatform = {
  getPlatformInfo() { return { isTizen: false, supportsNativeStreaming: false }; },
  registerKeys() { return { available: false, registered: [], failed: [] }; },
  setVolume() { return false; },
  restartApp() { return true; },
  exitApp() { return false; }
};

const source = fs.readFileSync(bridgePath, 'utf8');
vm.runInThisContext(source, { filename: bridgePath });

const bridge = globalThis.MoonlightNative;
assert.ok(bridge, 'MoonlightNative facade must be installed');
for (const method of [
  'initialize',
  'makeCertificate',
  'httpInit',
  'openText',
  'openBinary',
  'pair',
  'stun',
  'wakeOnLan',
  'scanLocalSubnet',
  'startStream',
  'stopStream',
  'startSyntheticAudioTest',
  'playSyntheticAudioClick',
  'stopSyntheticAudioTest',
  'recoverStreamSurface',
  'toggleStats',
  'probeVideoCodecSupport',
  'unlockAudio',
  'setInputMode',
  'connectedGamepadMask',
  'restartApp',
  'exitApp',
  'setEventSink',
  'logDiagnostic',
  'getDiagnosticLogStatus',
  'getDiagnosticLogs',
  'clearDiagnosticLogs',
  'getDiagnosticQrSvg'
]) {
  assert.equal(typeof bridge[method], 'function', `${method} must be public`);
}

const request = {
  hostAddress: '192.0.2.10',
  hostHttpPort: 47989,
  width: 1920,
  height: 1080,
  frameRate: 120,
  bitrateKbps: 30000,
  remoteInputKey: 'key',
  remoteInputKeyId: -12,
  appVersion: '7.1.0',
  gfeVersion: '3.27',
  sessionUrl: 'rtsp://session',
  serverCodecModeSupport: 7,
  framePacing: true,
  optimizeGameSettings: true,
  rumbleFeedback: true,
  mouseEmulation: true,
  flipAbButtons: true,
  flipXyButtons: true,
  audioBackend: 'emss',
  audioConfiguration: '51Surround',
  audioPacketDurationMs: 5,
  audioJitterBufferMs: 125,
  playAudioOnHost: true,
  videoCodec: 'HEVC',
  hdr: true,
  fullColorRange: true,
  gameMode: false,
  disableConnectionWarnings: true,
  showPerformanceStats: true,
  disabledCodecMimeTypes: ['video/av1', 'video/hevc'],
  inputConfiguration: {
    controllerLayout: 'nintendo',
    controllerProfiles: { '89abcdef': 'xbox', '01234567': 'playstation' },
    stickDeadzone: 0.18,
    triggerThreshold: 0.1,
    controllerSensitivity: 1.25,
    invertControllerYAxis: true,
    mouseEmulationSpeed: 1.5,
    mouseAcceleration: 1.2,
    mouseScrollSpeed: 2,
    mouseActivationButton: 'rightStick',
    physicalMouseSensitivity: 0.8,
    invertMouseScroll: true,
    keyboardCaptureWithoutPointerLock: false,
    pointerCaptureMode: 'streamStart',
    stopControllerShortcut: 'simplified',
    statsControllerShortcut: 'disabled',
    stopKeyboardShortcut: 'compact',
    statsKeyboardShortcut: 'disabled'
  }
};
const mapped = bridge.__testing.streamRequestToArgs(request);
assert.equal(mapped.length, 30, 'native startStream ABI must remain 30 positional arguments');
assert.deepEqual(mapped.slice(0, 6), ['192.0.2.10', 47989, '1920', '1080', '120', '30000']);
assert.deepEqual(mapped.slice(6, 12), ['key', '-12', '7.1.0', '3.27', 'rtsp://session', 7]);
for (const index of [0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 18, 19, 23, 29]) {
  assert.equal(typeof mapped[index], 'string', `native startStream argument ${index} must be a string`);
}
assert.equal(mapped[18], 'emss');
assert.equal(mapped[29], 'video/av1\nvideo/hevc');
assert.equal(
  bridge.__testing.inputConfigurationToWire(request.inputConfiguration),
  'v1|nintendo|0.18|0.1|1.25|1|1.5|1.2|2|rightStick|0.8|1|0|streamStart|simplified|disabled|compact|disabled|01234567:playstation,89abcdef:xbox'
);

assert.deepEqual(
  bridge.__testing.parseLifecycle('streamStartFailed: 4:-200:renderer failed'),
  { name: 'streamStartFailed', attemptId: 4, errorCode: -200, reason: 'renderer failed' }
);
assert.deepEqual(
  bridge.__testing.parseLifecycle('streamTerminated: -101'),
  { name: 'streamTerminated', attemptId: null, errorCode: -101, legacy: true }
);

const calls = [];
const fakeModule = {
  makeCert() { return { type: 'resolve', ret: { cert: 'certificate', privateKey: 'private-key' } }; },
  httpInit(...args) { calls.push(['httpInit', ...args]); return { type: 'resolve', ret: undefined }; },
  openUrl(id, ...args) {
    calls.push(['openUrl', id, ...args]);
    queueMicrotask(() => globalThis.handlePromiseMessage(
      id,
      'resolve',
      args[2] ? new Uint8Array([1, 2, 3]) : '<root/>'
    ));
  },
  pair(id, ...args) {
    calls.push(['pair', id, ...args]);
    queueMicrotask(() => globalThis.handlePromiseMessage(id, 'resolve', 'pin-key'));
  },
  stun(id) {
    calls.push(['stun', id]);
    queueMicrotask(() => globalThis.handlePromiseMessage(id, 'resolve', '198.51.100.4'));
  },
  wakeOnLan(...args) { calls.push(['wakeOnLan', ...args]); },
  configureInput(value) { calls.push(['configureInput', value]); },
  startStream(...args) {
    calls.push(['startStream', ...args]);
    queueMicrotask(() => globalThis.handleMessage('streamStarted: 42'));
    return { type: 'resolve', ret: 42 };
  },
  stopStream() { calls.push(['stopStream']); return { type: 'resolve', ret: undefined }; },
  startSyntheticAudioTest(...args) {
    calls.push(['startSyntheticAudioTest', ...args]);
    return { type: 'resolve', ret: undefined };
  },
  playSyntheticAudioClick(...args) {
    calls.push(['playSyntheticAudioClick', ...args]);
    return { type: 'resolve', ret: 3 };
  },
  stopSyntheticAudioTest() {
    calls.push(['stopSyntheticAudioTest']);
    return { type: 'resolve', ret: undefined };
  },
  toggleStats() { calls.push(['toggleStats']); },
  probeVideoCodecSupport(id, ...args) {
    calls.push(['probeVideoCodecSupport', id, ...args]);
    queueMicrotask(() => globalThis.handlePromiseMessage(
      id,
      'resolve',
      JSON.stringify({ selectedMimeType: 'video/hevc' })
    ));
  },
  startLogExportServer() { return { type: 'resolve', ret: { port: 48100 } }; },
  stopLogExportServer() { return { type: 'resolve', ret: undefined }; },
  sendKeyboardEvent(...args) { calls.push(['sendKeyboardEvent', ...args]); }
};
bridge.__testing.useReadyModule(fakeModule);

assert.deepEqual(await bridge.makeCertificate(), { cert: 'certificate', privateKey: 'private-key' });
await bridge.httpInit('cert', 'key', 'unique-id');
assert.equal(await bridge.openText('https://host/serverinfo', null), '<root/>');
assert.deepEqual([...await bridge.openBinary('https://host/boxart', 'ppk')], [1, 2, 3]);
assert.equal(await bridge.pair('7', '192.0.2.10', 47989, '1234', 'unique-id'), 'pin-key');
assert.equal(await bridge.stun(), '198.51.100.4');
assert.equal(await bridge.wakeOnLan('00:11:22:33:44:55'), true);
await bridge.startSyntheticAudioTest(true);
assert.equal(await bridge.playSyntheticAudioClick('gamepad:2:button:12'), 3);
await bridge.stopSyntheticAudioTest();
assert.deepEqual(calls.find((call) => call[0] === 'startSyntheticAudioTest'), [
  'startSyntheticAudioTest',
  true
]);
assert.deepEqual(calls.find((call) => call[0] === 'playSyntheticAudioClick'), [
  'playSyntheticAudioClick',
  'gamepad:2:button:12'
]);

const originalFetch = globalThis.fetch;
globalThis.MoonlightTizenPlatform.getIpAddress = () => '192.0.2.25';
globalThis.fetch = async (url) => ({ ok: url === 'http://192.0.2.10:47989/serverinfo' });
assert.deepEqual(JSON.parse(await bridge.scanLocalSubnet(25)), ['192.0.2.10']);
globalThis.fetch = originalFetch;

const streamResult = await bridge.startStream(request);
assert.equal(streamResult.attemptId, 42);
assert.equal(documentElement.dataset.streamState, 'active');
assert.equal(MoonlightInput.mode, 'stream');
assert.equal(calls.find((call) => call[0] === 'startStream').length, 31);
assert.match(calls.find((call) => call[0] === 'configureInput')[1], /^v1\|nintendo\|/);

await bridge.toggleStats();
assert.deepEqual(await bridge.probeVideoCodecSupport(request), { selectedMimeType: 'video/hevc' });
assert.equal(
  calls.find((call) => call[0] === 'probeVideoCodecSupport').length,
  9,
  'codec probe ABI must include a callback ID plus 7 probe arguments'
);
assert.equal(bridge.sendEscape(), true);
assert.deepEqual(
  calls.filter((call) => call[0] === 'sendKeyboardEvent').map((call) => call.slice(2)),
  [[0x03, 0], [0x04, 0]]
);
assert.equal(bridge.connectedGamepadMask(), 5);
assert.equal(bridge.restartApp(), true);
assert.equal(bridge.exitApp(), false);

const events = [];
bridge.setEventSink((event) => events.push(event));
globalThis.handleMessage('WarningMsg: Network is slow');
globalThis.handleMessage('StatMsg: 59.9 FPS');
globalThis.handleMessage('CodecProfileResult: {"supported":true}');
assert.equal(elements['stream-warning'].textContent, 'Network is slow');
assert.equal(elements['stream-statistics'].textContent, '59.9 FPS');
assert.ok(events.some((event) => event.type === 'warning' && event.visible));
assert.ok(events.some((event) => event.type === 'statistics' && event.visible));
assert.ok(events.some((event) => event.type === 'codec-profile' && event.data.supported));

globalThis.handleMessage('streamStartFailed: 42:-200:renderer failed');
assert.equal(documentElement.dataset.streamState, 'error');
assert.equal(elements['stream-fatal'].hidden, false);
assert.equal(elements['stream-fatal-back'].focused, true);
assert.equal(typeof elements['stream-fatal-back'].onclick, 'function');
elements['stream-fatal-back'].onclick();
assert.equal(documentElement.dataset.streamState, 'inactive');
assert.equal(elements['stream-fatal'].hidden, true);
assert.deepEqual(requestedInputActions.at(-1), {
  action: 'back',
  source: 'stream-fatal'
});

const singleton = globalThis.MoonlightNative;
vm.runInThisContext(source, { filename: bridgePath });
assert.equal(globalThis.MoonlightNative, singleton, 'bridge installation must be singleton');

const index = fs.readFileSync(path.join(workspace, 'flutter_ui', 'web', 'index.html'), 'utf8');
assert.match(index, /<video id="wasm_module" autoplay tabindex="-1"/);
assert.match(index, /<button id="stream-fatal-back" type="button">Back to games<\/button>/);
assert.ok(
  index.indexOf('$WEBAPIS/webapis/webapis.js') < index.indexOf('native/moonlight_native.js'),
  'Samsung web APIs must load before the native runtime bridge'
);
assert.ok(
  index.indexOf('native/diagnostics.js') < index.indexOf('native/debug_bridge.js'),
  'The durable logger must load before the authenticated debug bridge'
);
assert.ok(
  index.indexOf('native/debug_bridge_config.js') < index.indexOf('native/debug_bridge.js'),
  'The debug bridge configuration must load before the bridge'
);
assert.match(
  fs.readFileSync(path.join(workspace, 'flutter_ui', 'web', 'native', 'audio-worklet.js'), 'utf8'),
  /registerProcessor\('moonlight-pcm-sink'/
);

const bootstrap = fs.readFileSync(
  path.join(workspace, 'flutter_ui', 'web', 'flutter_bootstrap.js'),
  'utf8'
);
assert.match(bootstrap, /config:\s*\{[\s\S]*renderer:\s*'canvaskit'/);
assert.match(bootstrap, /initializeEngine\(\{\s*hostElement:\s*host\s*\}\)/);

const standardConfig = fs.readFileSync(
  path.join(workspace, 'packaging', 'flutter_tizen', 'config.xml'),
  'utf8'
);
const forceGameModeConfig = fs.readFileSync(
  path.join(workspace, 'packaging', 'flutter_tizen', 'config.force-game-mode.xml'),
  'utf8'
);
for (const config of [standardConfig, forceGameModeConfig]) {
  assert.match(config, /id="MLFlutter1\.MoonlightFlutter"/);
  assert.match(config, /package="MLFlutter1"/);
  assert.match(config, /required_version="10\.0"/);
  assert.match(config, /id="http:\/\/samsung\.tv\/MoonlightFlutter"/);
  assert.match(config, /http:\/\/developer\.samsung\.com\/privilege\/network\.public/);
}
assert.doesNotMatch(standardConfig, /metadata\/use\.game\.mode/);
assert.match(forceGameModeConfig, /metadata\/use\.game\.mode" value="true"/);

console.log('Moonlight native bridge contract tests passed.');
