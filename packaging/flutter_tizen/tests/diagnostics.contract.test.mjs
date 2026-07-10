import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const workspace = path.resolve(testDirectory, '..', '..', '..');
const loggerPath = path.join(
  workspace,
  'flutter_ui',
  'web',
  'native',
  'diagnostics.js'
);
const source = fs.readFileSync(loggerPath, 'utf8');

function createStorage() {
  const values = new Map();
  return {
    getItem(key) { return values.has(key) ? values.get(key) : null; },
    setItem(key, value) { values.set(key, String(value)); },
    removeItem(key) { values.delete(key); }
  };
}

function createContext({ withTizenFile = false } = {}) {
  const listeners = {};
  const localStorage = createStorage();
  let fileText = '';
  const context = vm.createContext({
    console: { log() {}, info() {}, warn() {}, error() {}, debug() {} },
    localStorage,
    setTimeout,
    clearTimeout,
    TextEncoder,
    FileReader: undefined,
    addEventListener(type, listener) { listeners[type] = listener; }
  });
  context.window = context;
  if (withTizenFile) {
    context.tizen = {
      filesystem: {
        openFile(filePath, mode) {
          assert.equal(filePath, 'wgt-private/logs/moonlight-flutter-log.ndjson');
          return {
            readString() { return fileText; },
            writeString(value) {
              fileText = mode === 'a' ? fileText + value : String(value);
            },
            close() {}
          };
        },
        deleteFile() { fileText = ''; }
      }
    };
  }
  vm.runInContext(source, context, { filename: loggerPath });
  return { context, listeners, readFile: () => fileText };
}

async function exerciseLogger(fixture, expectedStorage) {
  const { context, listeners } = fixture;
  const logger = context.MoonlightLogger;
  assert.ok(logger);
  assert.equal(logger.getLevel(), 'info', 'new installs must collect useful logs');

  const privateKey = '-----BEGIN PRIVATE KEY-----\nTOP-SECRET\n-----END PRIVATE KEY-----';
  logger.log('info', ['launch', privateKey, 'rtsp://secret/session'], {
    source: 'test',
    pin: '1234',
    rikey: '001122',
    sessionUrl: 'rtsp://secret/session',
    nested: { certificate: 'CERTIFICATE-SECRET' }
  });
  listeners.error({
    message: 'boom',
    filename: 'main.dart.js',
    lineno: 10,
    colno: 4,
    error: new Error('failure')
  });
  await logger.flush();

  const exported = await logger.getExportText();
  assert.match(exported, /launch/);
  assert.match(exported, /window error|boom/);
  assert.doesNotMatch(exported, /TOP-SECRET|001122|CERTIFICATE-SECRET|1234|rtsp:\/\/secret/);
  assert.match(exported, /\[redacted/);

  const status = await logger.getStatus();
  assert.equal(status.storage, expectedStorage);
  assert.equal(status.available, true);
  assert.ok(status.sizeBytes > 0);
  assert.match(logger.makeQrSvg('http://192.0.2.1:48100/log?token=redacted'), /^<svg/);

  await logger.clear();
  assert.equal(await logger.getExportText(), '');
}

await exerciseLogger(createContext(), 'localStorage');
const tizenFixture = createContext({ withTizenFile: true });
await exerciseLogger(tizenFixture, 'tizen-private-file');
assert.equal(tizenFixture.readFile(), '');

console.log('Moonlight diagnostics contract tests passed.');
