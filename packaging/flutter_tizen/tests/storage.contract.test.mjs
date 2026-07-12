import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const workspace = path.resolve(testDirectory, '..', '..', '..');
const sourcePath = path.join(
  workspace,
  'flutter_ui',
  'web',
  'native',
  'tizen_platform.js'
);

const files = new Map();
const directories = new Set();

function notFound() {
  const error = new Error('Not found');
  error.name = 'NotFoundError';
  return error;
}

const context = vm.createContext({
  console,
  Promise,
  Uint8Array,
  screen: { width: 1920, height: 1080 },
  tizen: {
    filesystem: {
      openFile(filePath, mode) {
        if (mode === 'r' && !files.has(filePath)) throw notFound();
        const directory = filePath.slice(0, filePath.lastIndexOf('/'));
        directories.add(directory);
        return {
          readData() { return new Uint8Array(files.get(filePath)); },
          writeData(bytes) { files.set(filePath, new Uint8Array(bytes)); },
          readString() { return String(files.get(filePath)); },
          writeString(value) { files.set(filePath, String(value)); },
          close() {}
        };
      },
      deleteFile(filePath) {
        if (!files.delete(filePath)) throw notFound();
      },
      deleteDirectory(directoryPath, recursive) {
        if (!directories.has(directoryPath) &&
            ![...files].some(([filePath]) => filePath.startsWith(directoryPath + '/'))) {
          throw notFound();
        }
        assert.equal(recursive, true);
        for (const filePath of files.keys()) {
          if (filePath.startsWith(directoryPath + '/')) files.delete(filePath);
        }
        directories.delete(directoryPath);
      }
    }
  }
});
context.window = context;
vm.runInContext(fs.readFileSync(sourcePath, 'utf8'), context, {
  filename: sourcePath
});

const storage = context.MoonlightTizenPlatform;
assert.equal(storage.hasPrivateStateStorage(), true);
const statePath = 'wgt-private/state/c2V0dGluZ3M.json';
assert.equal(await storage.readPrivateTextFile(statePath), null);
await storage.writePrivateTextFile(statePath, '{"fps":60}');
assert.equal(
  await storage.readPrivateTextFile(statePath),
  '{"fps":60}'
);
await storage.deletePrivateFile(statePath);
assert.equal(await storage.readPrivateTextFile(statePath), null);

assert.equal(storage.hasPrivateFileStorage(), true);
const pathName = 'wgt-private/cache/boxart/cGM/7.img';
assert.equal(await storage.readPrivateFile(pathName), null);
await storage.writePrivateFile(pathName, new Uint8Array([0, 1, 254, 255]));
assert.deepEqual(
  [...await storage.readPrivateFile(pathName)],
  [0, 1, 254, 255]
);
await storage.deletePrivateDirectory('wgt-private/cache/boxart/cGM');
assert.equal(await storage.readPrivateFile(pathName), null);

await assert.rejects(
  storage.writePrivateFile('wgt-private/logs/not-box-art', new Uint8Array()),
  /outside the box-art root/
);

console.log('Tizen native storage contract tests passed.');
