import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const directory = path.dirname(fileURLToPath(import.meta.url));
const workspace = path.resolve(directory, '..', '..', '..');
const bridgePath = path.join(workspace, 'flutter_ui', 'web', 'native', 'debug_bridge.js');
const source = fs.readFileSync(bridgePath, 'utf8');

function makeContext(enabled) {
  const requests = [];
  let sink;
  const logger = {
    addSink(value) { sink = value; },
    getStatusSync() {
      return { available: true, storage: 'tizen-private-file', sizeBytes: 2048 };
    },
    getExportText() { return Promise.resolve('{"message":"safe"}\n'); },
    setLevel(level) { return level; },
    clear() { return Promise.resolve(true); },
    redactValue(value) {
      const text = JSON.stringify(value).replaceAll('SECRET', '[redacted]');
      return JSON.parse(text);
    }
  };
  const context = vm.createContext({
    console,
    Promise,
    setTimeout() { return 1; },
    clearTimeout() {},
    location: { origin: 'file://', pathname: '/index.html' },
    document: {
      readyState: 'complete',
      title: 'Moonlight Flutter',
      visibilityState: 'visible',
      querySelector() { return {}; }
    },
    navigator: { onLine: true, getGamepads() { return []; } },
    localStorage: {
      getItem() { return null; },
      setItem() {}
    },
    MoonlightLogger: logger,
    MOONLIGHT_DEBUG_BRIDGE: enabled ? {
      enabled: true,
      serverUrl: 'http://192.0.2.1:49321',
      token: 'SECRET',
      clientName: 'contract-test'
    } : { enabled: false },
    fetch(url, options) {
      requests.push({ url, options });
      return Promise.resolve({
        ok: true,
        text() { return Promise.resolve('{"commands":[]}'); }
      });
    }
  });
  context.window = context;
  vm.runInContext(source, context, { filename: bridgePath });
  return { context, logger, requests, emit: (entry) => sink && sink(entry) };
}

const disabled = makeContext(false);
assert.equal(disabled.context.MoonlightDebugBridge.enabled, false);

const enabled = makeContext(true);
assert.equal(enabled.context.MoonlightDebugBridge.enabled, true);
const state = enabled.context.MoonlightDebugBridge.getState();
assert.equal(state.logger.storage, 'tizen-private-file');
assert.equal(state.capabilities.flutter, true);

enabled.emit({ level: 'error', message: 'failure SECRET', meta: { pin: 'SECRET' } });
await enabled.context.MoonlightDebugBridge.flush();
assert.ok(enabled.requests.some((request) => request.url.endsWith('/api/logs')));
const bodies = enabled.requests.map((request) => request.options.body || '').join('\n');
assert.doesNotMatch(bodies, /SECRET/);
assert.match(bodies, /\[redacted\]/);

const diagnostics = await enabled.context.MoonlightDebugBridge.executeCommand({
  type: 'getDiagnostics'
});
assert.match(diagnostics.logs, /safe/);
assert.equal(diagnostics.status.available, true);

console.log('Moonlight Flutter debug bridge contract tests passed.');
