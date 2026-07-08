#!/usr/bin/env node
import { createServer } from 'node:http';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';

const DEFAULT_HOST = '0.0.0.0';
const DEFAULT_PORT = 49321;
const MAX_BODY_BYTES = 1024 * 1024;
const MAX_LOGS = 5000;
const MAX_RESULTS = 1000;
const MAX_COMMANDS_PER_CLIENT = 200;
const ALLOWED_COMMAND_TYPES = new Set(['nav', 'click', 'setValue', 'addHost', 'getState', 'localStorage', 'reload']);

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type,X-Debug-Token',
  'Access-Control-Max-Age': '600',
};

function usage() {
  return `Usage: node tools/debug-bridge-server.mjs [options]

Options:
  --host <host>              Host to bind. Default: ${DEFAULT_HOST}
  --port <port>              Port to bind. Default: ${DEFAULT_PORT}
  --token <token>            Shared API token. Default: generated random token
  --public-url <url>         URL the Tizen app should call. Default: http://127.0.0.1:<port>
  --write-config <path>      Write an enabled debug_bridge_config.js for staged WGT builds
  --client-name <name>       Client name written to generated config. Default: tizen-emulator
  --help                     Show this help

Environment overrides:
  DEBUG_BRIDGE_HOST, DEBUG_BRIDGE_PORT, DEBUG_BRIDGE_TOKEN,
  DEBUG_BRIDGE_PUBLIC_URL, DEBUG_BRIDGE_WRITE_CONFIG,
  DEBUG_BRIDGE_CLIENT_NAME`;
}

function parseArgs(argv) {
  const options = {
    host: process.env.DEBUG_BRIDGE_HOST || DEFAULT_HOST,
    port: Number(process.env.DEBUG_BRIDGE_PORT || DEFAULT_PORT),
    token: process.env.DEBUG_BRIDGE_TOKEN || '',
    publicUrl: process.env.DEBUG_BRIDGE_PUBLIC_URL || '',
    writeConfig: process.env.DEBUG_BRIDGE_WRITE_CONFIG || '',
    clientName: process.env.DEBUG_BRIDGE_CLIENT_NAME || 'tizen-emulator',
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--help' || arg === '-h') {
      console.log(usage());
      process.exit(0);
    }

    const next = argv[i + 1];
    if (arg === '--host') {
      options.host = requireValue(arg, next);
      i += 1;
    } else if (arg === '--port') {
      options.port = Number(requireValue(arg, next));
      i += 1;
    } else if (arg === '--token') {
      options.token = requireValue(arg, next);
      i += 1;
    } else if (arg === '--public-url') {
      options.publicUrl = requireValue(arg, next);
      i += 1;
    } else if (arg === '--write-config') {
      options.writeConfig = requireValue(arg, next);
      i += 1;
    } else if (arg === '--client-name') {
      options.clientName = requireValue(arg, next);
      i += 1;
    } else {
      throw new Error(`Unknown option: ${arg}\n\n${usage()}`);
    }
  }

  if (!Number.isInteger(options.port) || options.port < 1 || options.port > 65535) {
    throw new Error(`Invalid port: ${options.port}`);
  }

  if (!options.token) {
    options.token = randomBytes(24).toString('hex');
  }

  if (!options.publicUrl) {
    const urlHost = options.host === '0.0.0.0' || options.host === '::' ? '127.0.0.1' : options.host;
    options.publicUrl = `http://${urlHost}:${options.port}`;
  }

  return options;
}

function requireValue(arg, value) {
  if (!value || value.startsWith('--')) {
    throw new Error(`Missing value for ${arg}`);
  }
  return value;
}

function sendJson(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    ...corsHeaders,
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(payload),
    'Cache-Control': 'no-store',
  });
  res.end(payload);
}

function sendNoContent(res) {
  res.writeHead(204, corsHeaders);
  res.end();
}

function truncateString(value, maxLength) {
  const text = String(value);
  if (text.length <= maxLength) {
    return text;
  }
  return `${text.slice(0, maxLength)}...[truncated]`;
}

function readJson(req) {
  return new Promise((resolveRead, rejectRead) => {
    const chunks = [];
    let total = 0;

    req.on('data', (chunk) => {
      total += chunk.length;
      if (total > MAX_BODY_BYTES) {
        rejectRead(Object.assign(new Error('Request body too large'), { statusCode: 413 }));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });

    req.on('end', () => {
      const raw = Buffer.concat(chunks).toString('utf8').trim();
      if (!raw) {
        resolveRead({});
        return;
      }

      try {
        resolveRead(JSON.parse(raw));
      } catch (error) {
        rejectRead(Object.assign(new Error(`Invalid JSON body: ${error.message}`), { statusCode: 400 }));
      }
    });

    req.on('error', rejectRead);
  });
}

function tokenMatches(expected, provided) {
  if (!provided) {
    return false;
  }

  const expectedBuffer = Buffer.from(expected);
  const providedBuffer = Buffer.from(provided);
  if (expectedBuffer.length !== providedBuffer.length) {
    return false;
  }

  return timingSafeEqual(expectedBuffer, providedBuffer);
}

function requireAuth(req, url, token) {
  const headerToken = req.headers['x-debug-token'];
  const provided = Array.isArray(headerToken) ? headerToken[0] : headerToken || url.searchParams.get('token') || '';
  return tokenMatches(token, provided);
}

function safeJsonValue(value, maxStringLength = 8000) {
  if (value == null) {
    return value;
  }

  if (typeof value === 'string') {
    return truncateString(value, maxStringLength);
  }

  if (typeof value === 'number' || typeof value === 'boolean') {
    return value;
  }

  if (Array.isArray(value)) {
    return value.slice(0, 50).map((item) => safeJsonValue(item, maxStringLength));
  }

  if (typeof value === 'object') {
    const output = {};
    for (const [key, item] of Object.entries(value).slice(0, 100)) {
      output[truncateString(key, 80)] = safeJsonValue(item, maxStringLength);
    }
    return output;
  }

  return truncateString(value, maxStringLength);
}

function normalizeId(value, fallback) {
  const text = typeof value === 'string' ? value.trim() : '';
  return text ? truncateString(text, 160) : fallback;
}

function parseTail(url, defaultTail, maxTail) {
  const raw = Number(url.searchParams.get('tail') || defaultTail);
  if (!Number.isFinite(raw)) {
    return defaultTail;
  }
  return Math.max(1, Math.min(Math.floor(raw), maxTail));
}

function prune(array, max) {
  if (array.length > max) {
    array.splice(0, array.length - max);
  }
}

function makeServer(options) {
  const clients = new Map();
  const commandQueues = new Map();
  const logs = [];
  const results = [];
  let logSeq = 0;
  let commandSeq = 0;
  let resultSeq = 0;

  function touchClient(clientId, req, patch = {}) {
    const now = new Date().toISOString();
    const existing = clients.get(clientId) || {
      clientId,
      firstSeenAt: now,
      lastSeenAt: now,
      clientName: '',
      userAgent: '',
      logCount: 0,
      commandCount: 0,
      resultCount: 0,
    };

    existing.lastSeenAt = now;
    if (patch.clientName) {
      existing.clientName = truncateString(patch.clientName, 120);
    }
    if (req.headers['user-agent']) {
      existing.userAgent = truncateString(req.headers['user-agent'], 240);
    }
    Object.assign(existing, patch);
    clients.set(clientId, existing);
    return existing;
  }

  function queueCommand(body, req) {
    const clientId = normalizeId(body.clientId, '');
    const type = normalizeId(body.type || (body.command && body.command.type), '');
    const args = body.args != null ? body.args : body.command && body.command.args;

    if (!clientId) {
      return { status: 400, body: { ok: false, error: 'clientId is required' } };
    }
    if (!type) {
      return { status: 400, body: { ok: false, error: 'type is required' } };
    }
    if (!ALLOWED_COMMAND_TYPES.has(type)) {
      return { status: 400, body: { ok: false, error: `Unsupported command type: ${type}` } };
    }

    const command = {
      id: normalizeId(body.id, `cmd-${Date.now().toString(36)}-${(commandSeq += 1).toString(36)}`),
      clientId,
      type,
      args: safeJsonValue(args || {}),
      createdAt: new Date().toISOString(),
    };

    const queue = commandQueues.get(clientId) || [];
    queue.push(command);
    prune(queue, MAX_COMMANDS_PER_CLIENT);
    commandQueues.set(clientId, queue);

    const client = touchClient(clientId, req);
    client.commandCount += 1;
    client.lastCommandAt = command.createdAt;

    return { status: 200, body: { ok: true, command } };
  }

  function storeLogs(body, req) {
    const clientId = normalizeId(body.clientId, 'unknown');
    const clientName = typeof body.clientName === 'string' ? body.clientName : '';
    const entries = Array.isArray(body.entries) ? body.entries : [body];
    const client = touchClient(clientId, req, { clientName });
    const stored = [];

    for (const entry of entries) {
      const normalized = {
        id: `log-${(logSeq += 1).toString(36)}`,
        serverTime: new Date().toISOString(),
        clientId,
        clientName: truncateString(clientName || client.clientName || '', 120),
        level: truncateString(entry && entry.level ? entry.level : body.level || 'log', 20),
        time: entry && (entry.time || entry.timestamp) ? truncateString(entry.time || entry.timestamp, 80) : '',
        message: truncateString(entry && entry.message != null ? entry.message : '', 12000),
        args: safeJsonValue(entry && entry.args != null ? entry.args : []),
        meta: safeJsonValue(entry && entry.meta != null ? entry.meta : {}),
      };
      logs.push(normalized);
      stored.push(normalized);
    }

    prune(logs, MAX_LOGS);
    client.logCount += stored.length;
    client.lastLogAt = stored.length ? stored[stored.length - 1].serverTime : client.lastLogAt;

    return { ok: true, stored: stored.length };
  }

  function storeResult(commandId, body, req) {
    const clientId = normalizeId(body.clientId, 'unknown');
    const result = {
      id: `result-${(resultSeq += 1).toString(36)}`,
      serverTime: new Date().toISOString(),
      clientId,
      commandId: normalizeId(body.commandId || commandId, commandId),
      ok: body.ok === true,
      result: safeJsonValue(body.result || {}),
      error: body.error ? safeJsonValue(body.error) : null,
    };

    results.push(result);
    prune(results, MAX_RESULTS);

    const client = touchClient(clientId, req);
    client.resultCount += 1;
    client.lastResultAt = result.serverTime;

    return { ok: true, result };
  }

  return createServer(async (req, res) => {
    const url = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);

    if (req.method === 'OPTIONS') {
      sendNoContent(res);
      return;
    }

    if (!url.pathname.startsWith('/api/')) {
      sendJson(res, 404, { ok: false, error: 'Not found' });
      return;
    }

    if (!requireAuth(req, url, options.token)) {
      sendJson(res, 401, { ok: false, error: 'Missing or invalid debug bridge token' });
      return;
    }

    try {
      if (req.method === 'GET' && url.pathname === '/api/health') {
        sendJson(res, 200, { ok: true, clients: clients.size, logs: logs.length, queuedCommands: commandQueues.size });
        return;
      }

      if (req.method === 'POST' && url.pathname === '/api/logs') {
        const body = await readJson(req);
        sendJson(res, 200, storeLogs(body, req));
        return;
      }

      if (req.method === 'GET' && url.pathname === '/api/logs') {
        const tail = parseTail(url, 200, MAX_LOGS);
        const clientId = url.searchParams.get('clientId');
        const filtered = clientId ? logs.filter((entry) => entry.clientId === clientId) : logs;
        sendJson(res, 200, { ok: true, logs: filtered.slice(-tail) });
        return;
      }

      if (req.method === 'GET' && url.pathname === '/api/clients') {
        sendJson(res, 200, { ok: true, clients: Array.from(clients.values()) });
        return;
      }

      if (req.method === 'POST' && url.pathname === '/api/commands') {
        const body = await readJson(req);
        const result = queueCommand(body, req);
        sendJson(res, result.status, result.body);
        return;
      }

      if (req.method === 'GET' && url.pathname === '/api/commands') {
        const clientId = normalizeId(url.searchParams.get('clientId'), '');
        if (!clientId) {
          sendJson(res, 400, { ok: false, error: 'clientId query parameter is required' });
          return;
        }

        const queue = commandQueues.get(clientId) || [];
        commandQueues.set(clientId, []);
        touchClient(clientId, req);
        sendJson(res, 200, { ok: true, clientId, commands: queue });
        return;
      }

      const resultMatch = url.pathname.match(/^\/api\/commands\/([^/]+)\/result$/);
      if (req.method === 'POST' && resultMatch) {
        const body = await readJson(req);
        sendJson(res, 200, storeResult(decodeURIComponent(resultMatch[1]), body, req));
        return;
      }

      if (req.method === 'GET' && url.pathname === '/api/results') {
        const tail = parseTail(url, 100, MAX_RESULTS);
        const clientId = url.searchParams.get('clientId');
        const filtered = clientId ? results.filter((entry) => entry.clientId === clientId) : results;
        sendJson(res, 200, { ok: true, results: filtered.slice(-tail) });
        return;
      }

      sendJson(res, 404, { ok: false, error: 'Not found' });
    } catch (error) {
      const status = error.statusCode || 500;
      sendJson(res, status, { ok: false, error: error.message });
    }
  });
}

async function writeConfig(options) {
  if (!options.writeConfig) {
    return;
  }

  const outputPath = resolve(options.writeConfig);
  await mkdir(dirname(outputPath), { recursive: true });
  const contents = [
    '// Generated by tools/debug-bridge-server.mjs for a local debug build.',
    '// Do not commit enabled debug bridge configs or tokens.',
    'window.MOONLIGHT_DEBUG_BRIDGE = {',
    '  enabled: true,',
    `  serverUrl: ${JSON.stringify(options.publicUrl)},`,
    `  token: ${JSON.stringify(options.token)},`,
    `  clientName: ${JSON.stringify(options.clientName)}`,
    '};',
    '',
  ].join('\n');

  await writeFile(outputPath, contents, 'utf8');
  console.log(`[debug-bridge] wrote enabled app config: ${outputPath}`);
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  await writeConfig(options);

  const server = makeServer(options);
  server.listen(options.port, options.host, () => {
    console.log(`[debug-bridge] listening on http://${options.host}:${options.port}`);
    console.log(`[debug-bridge] app serverUrl: ${options.publicUrl}`);
    console.log(`[debug-bridge] token: ${options.token}`);
  });
}

main().catch((error) => {
  console.error(`[debug-bridge] ${error.message}`);
  process.exit(1);
});
