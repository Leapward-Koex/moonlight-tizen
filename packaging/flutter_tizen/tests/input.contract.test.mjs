import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const workspace = path.resolve(testDirectory, '..', '..', '..');
const source = fs.readFileSync(
  path.join(workspace, 'flutter_ui', 'web', 'native', 'input.js'),
  'utf8'
);

let gamepads = [];
let animationFrame;
let pointerLockRequests = 0;
const listeners = {};
const video = {
  focus() {},
  requestPointerLock() {
    pointerLockRequests += 1;
    return Promise.resolve();
  }
};
const context = vm.createContext({
  console,
  navigator: { getGamepads: () => gamepads },
  document: {
    addEventListener(type, listener) { listeners[type] = listener; },
    getElementById(id) { return id === 'wasm_module' ? video : null; }
  },
  requestAnimationFrame(callback) {
    animationFrame = callback;
    return 1;
  },
  cancelAnimationFrame() {},
  setTimeout,
  clearTimeout,
  dispatchEvent() { return true; },
  CustomEvent: class CustomEvent {},
  MouseEvent: class MouseEvent {}
});
context.window = context;
vm.runInContext(source, context, { filename: 'input.js' });

const input = context.MoonlightInput;
assert.equal(input.connectedGamepadMask(), 0);

const rumbleCalls = [];
gamepads = [
  {
    index: 0,
    connected: true,
    timestamp: 0,
    id: 'Tizen phantom',
    mapping: '',
    buttons: [],
    axes: []
  },
  null,
  {
    index: 2,
    connected: true,
    timestamp: 12,
    id: 'Example Controller',
    mapping: 'standard',
    buttons: Array.from({ length: 17 }, () => ({ pressed: false })),
    axes: [0, 0, 0, 0],
    vibrationActuator: {
      playEffect(type, options) {
        rumbleCalls.push({ type, options });
        return Promise.resolve();
      }
    }
  }
];

assert.equal(input.connectedGamepadMask(), 1, 'phantom slots are excluded and real pads are compacted');
const devices = input.inputDevices();
assert.equal(devices.length, 1);
assert.equal(devices[0].slot, 0);
assert.equal(devices[0].browserIndex, 2);
assert.equal(devices[0].mapping, 'standard');
assert.match(devices[0].fingerprint, /^[0-9a-f]{8}$/);
assert.equal(devices[0].supportsRumble, true);
assert.equal(input.testRumble(2), true);
assert.equal(rumbleCalls.length, 1);
assert.equal(rumbleCalls[0].options.duration, 350);

const events = [];
input.setSink((event) => events.push(event));
animationFrame(); // Capture initial connected state.
gamepads[2].buttons[0] = { pressed: true };
animationFrame();
assert.equal(events.at(-1).action, 'accept');
assert.equal(events.at(-1).gamepadIndex, 2);

input.setConfiguration({ pointerCaptureMode: 'streamStart' });
input.setMode('stream');
assert.equal(pointerLockRequests, 1);
input.setMode('ui');

gamepads = [];
animationFrame();
assert.equal(events.at(-1).type, 'gamepad-disconnected');
assert.equal(events.at(-1).connectedMask, 0);

input.stop();
console.log('Moonlight input contract tests passed.');
