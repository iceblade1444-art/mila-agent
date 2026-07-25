import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import {RoomConfiguration} from '@livekit/protocol';
import {AccessToken} from 'livekit-server-sdk';

import {createAppDb} from './db.mjs';

const dirname = path.dirname(fileURLToPath(import.meta.url));

loadDotEnv(path.join(dirname, '.env'));

const config = {
  port: Number(process.env.PORT || 8787),
  publicBaseUrl: process.env.PUBLIC_BASE_URL || 'http://localhost:8787',
  allowedOrigin: process.env.ALLOWED_ORIGIN || '*',
  openAiApiKey: process.env.OPENAI_API_KEY || '',
  defaultModel: process.env.OPENAI_MODEL || 'gpt-5.5',
  geminiApiKey: process.env.GEMINI_API_KEY || '',
  geminiLiveModel:
    process.env.GEMINI_LIVE_MODEL || 'gemini-3.1-flash-live-preview',
  livekitUrl: process.env.LIVEKIT_URL || '',
  livekitApiKey: process.env.LIVEKIT_API_KEY || '',
  livekitApiSecret: process.env.LIVEKIT_API_SECRET || '',
  sessionSecret: process.env.SESSION_SECRET || 'dev-session-secret',
  dbPath: process.env.DB_PATH || path.join(dirname, 'data', 'mila.db'),
  downloadsDir: process.env.DOWNLOADS_DIR || path.join(dirname, 'downloads'),
  adminToken: process.env.ADMIN_TOKEN || '',
  agenticOsUrl: (process.env.AGENTIC_OS_URL || '').replace(/\/$/, ''),
  agenticOsToken: process.env.AGENTIC_OS_TOKEN || '',
  enableOpenAiAccount: process.env.ENABLE_OPENAI_ACCOUNT === 'true',
  requireActiveSubscription: process.env.REQUIRE_ACTIVE_SUBSCRIPTION === 'true',
};

const LIVE_VOICES = new Set([
  'Laomedeia',
  'Sulafat',
  'Achird',
  'Algieba',
  'Aoede',
]);
const THINKING_LEVELS = new Set(['minimal', 'low', 'medium', 'high']);
const MEDIA_RESOLUTIONS = new Set(['low', 'medium', 'high']);

function boundedInteger(value, fallback, min, max) {
  const parsed = Number.parseInt(value, 10);
  return Math.max(min, Math.min(Number.isFinite(parsed) ? parsed : fallback, max));
}

export function normalizeLiveProfile(value = {}) {
  const source = value && typeof value === 'object' && !Array.isArray(value)
    ? value
    : {};
  const contextTriggerTokens = boundedInteger(
    source.contextTriggerTokens,
    104857,
    65536,
    120000,
  );
  return {
    voiceName: LIVE_VOICES.has(source.voiceName) ? source.voiceName : 'Laomedeia',
    additionalInstructions: String(source.additionalInstructions || '').trim().slice(0, 12000),
    thinkingLevel: THINKING_LEVELS.has(source.thinkingLevel) ? source.thinkingLevel : 'low',
    mediaResolution: MEDIA_RESOLUTIONS.has(source.mediaResolution) ? source.mediaResolution : 'low',
    contextTriggerTokens,
    contextTargetTokens: boundedInteger(
      source.contextTargetTokens,
      52428,
      32768,
      contextTriggerTokens - 8192,
    ),
    functionCalling: source.functionCalling !== false,
  };
}

export function createMilaServer(options = {}) {
  const cfg = {...config, ...options.config};
  const fetchImpl = options.fetchImpl || globalThis.fetch;
  const db = options.db || createAppDb(cfg.dbPath);

  function send(res, status, body, headers = {}) {
    const payload = typeof body === 'string' ? body : JSON.stringify(body);
    res.writeHead(status, {
      'Access-Control-Allow-Origin': cfg.allowedOrigin,
      'Access-Control-Allow-Headers': 'authorization,content-type',
      'Access-Control-Allow-Methods': 'GET,POST,PATCH,DELETE,OPTIONS',
      'Content-Type': typeof body === 'string'
          ? 'text/html; charset=utf-8'
          : 'application/json; charset=utf-8',
      ...headers,
    });
    res.end(payload);
  }

  function sendJson(res, status, body) {
    send(res, status, body, {'Content-Type': 'application/json; charset=utf-8'});
  }

  function normalizeOwner(owner) {
    if (!owner || typeof owner !== 'object') return null;
    const clean = {
      id: String(owner.id || owner.email || owner.name || '').trim().slice(0, 120),
      email: String(owner.email || '').trim().slice(0, 180),
      name: String(owner.name || '').trim().slice(0, 120),
      role: String(owner.role || 'User').trim().slice(0, 40),
    };
    return clean.id || clean.email || clean.name ? clean : null;
  }

  function ownerFromJson(value) {
    try {
      const parsed = JSON.parse(value || 'null');
      return normalizeOwner(parsed);
    } catch {
      return null;
    }
  }

  function safeOwnerSlug(session) {
    const owner = ownerFromJson(session.ownerJson);
    const source = owner?.id || owner?.email || session.label || 'mobile-user';
    return String(source).replace(/[^a-zA-Z0-9_-]/g, '-').slice(0, 100) || 'mobile-user';
  }

  function publicSession(session) {
    const owner = ownerFromJson(session.ownerJson);
    return {
      label: session.label,
      owner: owner || {
        id: '',
        email: '',
        name: session.label,
        role: 'Mobile user',
      },
    };
  }

  function createCode(label, owner = null) {
    const code = crypto.randomBytes(4).toString('hex').toUpperCase();
    const cleanOwner = normalizeOwner(owner);
    db.createCode(
      code,
      label || 'ChatGPT account',
      cleanOwner ? JSON.stringify(cleanOwner) : null,
      Date.now() + 10 * 60 * 1000,
    );
    return code;
  }

  function createSession(label, ownerJson = null) {
    const token = crypto.randomBytes(32).toString('base64url');
    db.createSession(
      hashToken(token, cfg.sessionSecret),
      label,
      crypto.randomUUID().replaceAll('-', ''),
      ownerJson,
    );
    return token;
  }

  function getSession(req) {
    const auth = req.headers.authorization || '';
    const match = /^Bearer\s+(.+)$/i.exec(auth);
    if (!match) return null;
    return db.getSession(hashToken(match[1], cfg.sessionSecret)) || null;
  }

  function hasAdminAccess(req) {
    if (!cfg.adminToken) return false;
    return req.headers['x-admin-token'] === cfg.adminToken;
  }

  async function agenticRequest(pathname, options = {}) {
    if (!cfg.agenticOsUrl || !cfg.agenticOsToken) {
      const error = new Error('Agentic OS is not configured');
      error.status = 503;
      throw error;
    }
    const response = await fetchImpl(`${cfg.agenticOsUrl}${pathname}`, {
      method: options.method || 'GET',
      headers: {
        Authorization: `Bearer ${cfg.agenticOsToken}`,
        ...(options.body ? {'Content-Type': 'application/json'} : {}),
      },
      body: options.body ? JSON.stringify(options.body) : undefined,
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      const error = new Error(data.error || `Agentic OS HTTP ${response.status}`);
      error.status = response.status;
      throw error;
    }
    return data;
  }

  async function agenticAccount(req) {
    if (!cfg.agenticOsUrl) {
      const error = new Error('Agentic OS is not configured');
      error.status = 503;
      throw error;
    }
    const authorization = req.headers.authorization || '';
    if (!/^Bearer\s+\S+$/i.test(authorization)) {
      const error = new Error('Agentic OS account token is required');
      error.status = 401;
      throw error;
    }
    const response = await fetchImpl(`${cfg.agenticOsUrl}/api/auth/me`, {
      headers: {Authorization: authorization},
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok || !data.authed || !data.user) {
      const error = new Error('Invalid or expired Agentic OS account');
      error.status = 401;
      throw error;
    }
    return normalizeOwner(data.user);
  }

  function requireSession(req, res) {
    const session = getSession(req);
    if (!session) {
      sendJson(res, 401, {error: 'Missing or expired MILA session'});
      return null;
    }
    return session;
  }

  function memoryPath(session) {
    return `Agentic OS/People/${safeOwnerSlug(session)}/MILA Mobile Memory.md`;
  }

  async function readMobileMemory(session) {
    const notePath = memoryPath(session);
    const notes = await agenticRequest(
      `/api/knowledge/notes?q=${encodeURIComponent(notePath)}`,
    );
    const note = Array.isArray(notes)
      ? notes.find((item) => item.path === notePath)
      : null;
    if (!note) return {path: notePath, content: '', items: []};
    const record = await agenticRequest(
      `/api/knowledge/notes/read?path=${encodeURIComponent(notePath)}`,
    );
    const indexed = new Map();
    for (const rawLine of String(record.content || '').split(/\r?\n/)) {
      const line = rawLine.trim();
      const match = /^- \[(people|preferences|facts)\] (.+)$/.exec(line);
      if (match) {
        const id = crypto.createHash('sha256').update(line).digest('hex').slice(0, 16);
        indexed.set(id, {id, category: match[1], text: match[2]});
        continue;
      }
      const deleted = /^- \[deleted\] ([a-f0-9]{16})$/.exec(line);
      if (deleted) indexed.delete(deleted[1]);
    }
    const items = [...indexed.values()];
    return {path: notePath, content: String(record.content || ''), items};
  }

  function summarizeTasks(board) {
    const tasks = (board.columns || []).flatMap((column) =>
      (column.tasks || []).map((task) => ({
        ...task,
        status: task.status || column.name,
      })),
    );
    const activeStatuses = new Set(['triage', 'todo', 'scheduled', 'ready', 'running', 'review']);
    return {
      total: tasks.length,
      open: tasks.filter((task) => activeStatuses.has(task.status)).length,
      running: tasks.filter((task) => task.status === 'running').length,
      blocked: tasks.filter((task) => task.status === 'blocked').length,
      done: tasks.filter((task) => task.status === 'done').length,
      recent: tasks.slice(0, 5).map((task) => ({
        id: task.id,
        title: task.title,
        status: task.status,
        priority: Number(task.priority) || 0,
        assignee: task.assignee || '',
      })),
    };
  }

  const server = http.createServer(async (req, res) => {
    try {
      const url = new URL(req.url || '/', cfg.publicBaseUrl);

      if (req.method === 'OPTIONS') {
        send(res, 204, '');
        return;
      }

      if (req.method === 'GET' && url.pathname === '/health') {
        sendJson(res, 200, {ok: true, db: true});
        return;
      }

      if (req.method === 'GET' && url.pathname === '/admin/status') {
        if (!hasAdminAccess(req)) {
          sendJson(res, 403, {error: 'Admin token required'});
          return;
        }
        sendJson(res, 200, {
          ok: true,
          voiceConfigured: Boolean(cfg.geminiApiKey),
          chatConfigured: Boolean(cfg.openAiApiKey),
          accountConnectionsEnabled: cfg.enableOpenAiAccount,
          subscriptionRequired: cfg.requireActiveSubscription,
          liveModel: cfg.geminiLiveModel,
          livekitConfigured: Boolean(
            cfg.livekitUrl && cfg.livekitApiKey && cfg.livekitApiSecret,
          ),
          chatModel: cfg.defaultModel,
        });
        return;
      }

      if (req.method === 'POST' && url.pathname === '/admin/connection-code') {
        if (!hasAdminAccess(req)) {
          sendJson(res, 403, {error: 'Admin token required'});
          return;
        }
        const body = await readJson(req);
        const label = String(body.label || body.owner?.email || body.owner?.name || '').trim() || 'MILA user';
        const owner = normalizeOwner(body.owner);
        const code = createCode(label, owner);
        sendJson(res, 200, {ok: true, code, label, owner, expiresInSeconds: 600});
        return;
      }

      if (req.method === 'GET' && url.pathname === '/admin/devices') {
        if (!hasAdminAccess(req)) {
          sendJson(res, 403, {error: 'Admin token required'});
          return;
        }
        sendJson(res, 200, {
          devices: db.listSessions().map((session) => ({
            ...session,
            owner: ownerFromJson(session.ownerJson),
            ownerJson: undefined,
          })),
        });
        return;
      }

      const adminDeviceMatch = /^\/admin\/devices\/([a-f0-9]{32})$/.exec(url.pathname);
      if (req.method === 'DELETE' && adminDeviceMatch) {
        if (!hasAdminAccess(req)) {
          sendJson(res, 403, {error: 'Admin token required'});
          return;
        }
        if (!db.revokeSession(adminDeviceMatch[1])) {
          sendJson(res, 404, {error: 'Active device session not found'});
          return;
        }
        sendJson(res, 200, {ok: true, id: adminDeviceMatch[1]});
        return;
      }

      if (req.method === 'GET' && url.pathname.startsWith('/downloads/')) {
        await sendDownload(res, url.pathname, cfg);
        return;
      }

      if (req.method === 'GET' && url.pathname === '/v1/app/update') {
        const platform = url.searchParams.get('platform') || 'android';
        const currentCode = Number(url.searchParams.get('versionCode') || 0);
        const update = db.getUpdate(platform) || defaultUpdate(platform);
        sendJson(res, 200, {
          ...update,
          updateAvailable: update.latestCode > currentCode,
          updateRequired: update.minSupportedCode > currentCode,
        });
        return;
      }

      if (req.method === 'POST' && url.pathname === '/admin/app/update') {
        if (!hasAdminAccess(req)) {
          sendJson(res, 403, {error: 'Admin token required'});
          return;
        }
        const body = await readJson(req);
        const update = normalizeUpdate(body);
        db.upsertUpdate(update);
        sendJson(res, 200, {ok: true, update});
        return;
      }

      if (req.method === 'POST' && url.pathname === '/admin/subscription') {
        if (!cfg.enableOpenAiAccount) {
          sendJson(res, 404, {error: 'Not found'});
          return;
        }
        if (!hasAdminAccess(req)) {
          sendJson(res, 403, {error: 'Admin token required'});
          return;
        }
        const subscription = normalizeSubscription(await readJson(req));
        db.upsertSubscription(subscription);
        sendJson(res, 200, {ok: true, subscription});
        return;
      }

      if (url.pathname === '/auth/openai/start') {
        if (!cfg.enableOpenAiAccount) {
          sendJson(res, 404, {error: 'Not found'});
          return;
        }
        if (req.method === 'GET') {
          send(res, 200, renderConnectPage());
          return;
        }

        if (req.method === 'POST') {
          const form = new URLSearchParams(await readBody(req));
          const label = form.get('label')?.trim() || 'ChatGPT account';
          const code = createCode(label);
          send(res, 200, renderCodePage(code, label));
          return;
        }
      }

      if (
        req.method === 'POST' &&
        url.pathname === '/v1/auth/agentic'
      ) {
        const owner = await agenticAccount(req);
        if (!owner) {
          sendJson(res, 401, {error: 'Agentic OS account is unavailable'});
          return;
        }
        const label = owner.email || owner.name || 'MILA user';
        const token = createSession(label, JSON.stringify(owner));
        sendJson(res, 201, {
          token,
          label,
          owner,
        });
        return;
      }

      if (
        req.method === 'POST' &&
        (url.pathname === '/v1/auth/device' ||
          url.pathname === '/auth/openai/device')
      ) {
        const body = await readJson(req);
        const code = String(body.code || '').trim().toUpperCase();
        const record = db.getCode(code);
        if (!record || record.expiresAt < Date.now()) {
          sendJson(res, 400, {error: 'Invalid or expired connection code'});
          return;
        }

        db.deleteCode(code);
        const token = createSession(record.label, record.ownerJson || null);
        sendJson(res, 200, {token, ...publicSession(record)});
        return;
      }

      if (req.method === 'GET' && url.pathname === '/v1/agentic/status') {
        const session = requireSession(req, res);
        if (!session) return;
        const [profiles, orchestration] = await Promise.all([
          agenticRequest('/api/kanban/profiles'),
          agenticRequest('/api/kanban/orchestration'),
        ]);
        sendJson(res, 200, {
          ok: true,
          connected: true,
          ...publicSession(session),
          profiles: profiles.profiles || [],
          orchestration,
        });
        return;
      }

      if (req.method === 'GET' && url.pathname === '/v1/dashboard') {
        const session = requireSession(req, res);
        if (!session) return;
        const [board, knowledge, operations, mila] = await Promise.all([
          agenticRequest('/api/kanban/board'),
          agenticRequest('/api/knowledge/status'),
          agenticRequest('/api/operations/status').catch((error) => ({
            available: false,
            error: error.message,
          })),
          agenticRequest('/api/integrations/mila/status').catch((error) => ({
            ok: false,
            error: error.message,
          })),
        ]);
        sendJson(res, 200, {
          ok: true,
          connected: true,
          account: publicSession(session),
          workspace: {
            name: operations?.readiness?.workspace?.name || 'Agentic OS',
            readiness: operations?.readiness?.status || 'unknown',
            readinessScore: Number(operations?.readiness?.score) || 0,
          },
          tasks: summarizeTasks(board),
          knowledge: {
            ready: Boolean(knowledge.ready),
            writable: Boolean(knowledge.writable),
            notes: Number(knowledge.notes) || 0,
            folders: Number(knowledge.folders) || 0,
            mcpStatus: knowledge.mcp?.status || 'unknown',
          },
          operations: {
            available: Boolean(operations.available),
            fourC: operations.readiness?.status || 'unknown',
            score: Number(operations.readiness?.score) || 0,
          },
          mila: {
            voiceConfigured: Boolean(mila.voiceConfigured),
            liveModel: mila.liveModel || cfg.geminiLiveModel,
          },
          syncedAt: Date.now(),
        });
        return;
      }

      if (req.method === 'GET' && url.pathname === '/v1/tasks') {
        if (!requireSession(req, res)) return;
        const board = await agenticRequest('/api/kanban/board');
        const tasks = (board.columns || []).flatMap((column) =>
          (column.tasks || []).map((task) => ({
            ...task,
            status: task.status || column.name,
          })),
        );
        sendJson(res, 200, {tasks, syncedAt: Date.now()});
        return;
      }

      if (req.method === 'POST' && url.pathname === '/v1/tasks') {
        const session = requireSession(req, res);
        if (!session) return;
        const body = await readJson(req);
        const title = String(body.title || '').trim().slice(0, 240);
        if (!title) {
          sendJson(res, 400, {error: 'Task title is required'});
          return;
        }
        const created = await agenticRequest('/api/kanban/tasks', {
          method: 'POST',
          body: {
            title,
            body: String(body.body || body.subtitle || '').trim().slice(0, 20000),
            initialStatus: body.initialStatus === 'ready' ? 'ready' : 'triage',
            assignee: String(body.assignee || 'default').trim().slice(0, 64),
            priority: Math.max(0, Math.min(3, Number(body.priority) || 0)),
          },
        });
        await agenticRequest('/api/kanban/dispatch', {
          method: 'POST',
          body: {},
        }).catch(() => {});
        sendJson(res, 201, {...created, requestedBy: publicSession(session)});
        return;
      }

      const taskMatch = /^\/v1\/tasks\/(t_[a-zA-Z0-9]+)$/.exec(url.pathname);
      if (taskMatch && req.method === 'GET') {
        if (!requireSession(req, res)) return;
        sendJson(
          res,
          200,
          await agenticRequest(`/api/kanban/tasks/${taskMatch[1]}`),
        );
        return;
      }

      if (taskMatch && req.method === 'PATCH') {
        if (!requireSession(req, res)) return;
        const body = await readJson(req);
        const patch = {};
        if (['ready', 'blocked', 'review', 'done', 'archived'].includes(body.status)) {
          patch.status = body.status;
        }
        if (body.blockReason !== undefined) {
          patch.block_reason = String(body.blockReason).trim().slice(0, 2000);
        }
        if (!Object.keys(patch).length) {
          sendJson(res, 400, {error: 'No supported task update'});
          return;
        }
        sendJson(
          res,
          200,
          await agenticRequest(`/api/kanban/tasks/${taskMatch[1]}`, {
            method: 'PATCH',
            body: patch,
          }),
        );
        return;
      }

      if (req.method === 'GET' && url.pathname === '/v1/memory') {
        const session = requireSession(req, res);
        if (!session) return;
        const memory = await readMobileMemory(session);
        sendJson(res, 200, {items: memory.items, syncedAt: Date.now()});
        return;
      }

      if (req.method === 'POST' && url.pathname === '/v1/memory') {
        const session = requireSession(req, res);
        if (!session) return;
        const body = await readJson(req);
        const text = String(body.text || '').trim().replace(/\s+/g, ' ').slice(0, 500);
        const category = ['people', 'preferences', 'facts'].includes(body.category)
          ? body.category
          : 'facts';
        if (!text) {
          sendJson(res, 400, {error: 'Memory text is required'});
          return;
        }
        const memory = await readMobileMemory(session);
        const duplicate = memory.items.find(
          (item) => item.text.toLowerCase() === text.toLowerCase(),
        );
        if (duplicate) {
          sendJson(res, 200, {ok: true, item: duplicate, duplicate: true});
          return;
        }
        const line = `- [${category}] ${text}`;
        await agenticRequest('/api/knowledge/notes/append', {
          method: 'POST',
          body: {
            path: memory.path,
            text: memory.content
              ? line
              : `# MILA Mobile Memory\n\n${line}`,
          },
        });
        sendJson(res, 201, {
          ok: true,
          item: {
            id: crypto.createHash('sha256').update(line).digest('hex').slice(0, 16),
            category,
            text,
          },
        });
        return;
      }

      const memoryMatch = /^\/v1\/memory\/([a-f0-9]{16})$/.exec(url.pathname);
      if (memoryMatch && req.method === 'DELETE') {
        const session = requireSession(req, res);
        if (!session) return;
        const memory = await readMobileMemory(session);
        if (!memory.items.some((item) => item.id === memoryMatch[1])) {
          sendJson(res, 404, {error: 'Memory item not found'});
          return;
        }
        await agenticRequest('/api/knowledge/notes/append', {
          method: 'POST',
          body: {
            path: memory.path,
            text: `- [deleted] ${memoryMatch[1]}`,
          },
        });
        sendJson(res, 200, {ok: true, id: memoryMatch[1]});
        return;
      }

      if (req.method === 'POST' && url.pathname === '/v1/chat/stream') {
        if (!cfg.enableOpenAiAccount) {
          sendJson(res, 404, {error: 'Not found'});
          return;
        }
        const session = getSession(req);
        if (!session) {
          sendJson(res, 401, {error: 'Missing or expired MILA session'});
          return;
        }

        if (cfg.requireActiveSubscription) {
          const subscription = db.getSubscription(session.label);
          if (!subscription || subscription.activeUntil < Date.now()) {
            sendJson(res, 402, {
              error: 'Active subscription required',
              label: session.label,
            });
            return;
          }
        }

        if (!cfg.openAiApiKey) {
          sendJson(res, 500, {error: 'OPENAI_API_KEY is not configured'});
          return;
        }

        const body = await readJson(req);
        await streamOpenAiChat({body, res, cfg, fetchImpl});
        return;
      }

      if (req.method === 'POST' && url.pathname === '/v1/gemini/chat') {
        const session = requireSession(req, res);
        if (!session) return;

        if (cfg.requireActiveSubscription) {
          const subscription = db.getSubscription(session.label);
          if (!subscription || subscription.activeUntil < Date.now()) {
            sendJson(res, 402, {error: 'Active subscription required'});
            return;
          }
        }

        if (!cfg.geminiApiKey) {
          sendJson(res, 500, {error: 'GEMINI_API_KEY is not configured'});
          return;
        }

        const body = await readJson(req);
        sendJson(res, 200, await generateGeminiChat({body, cfg, fetchImpl}));
        return;
      }

      if (req.method === 'POST' && url.pathname === '/v1/voice/token') {
        const session = getSession(req);
        if (!session) {
          sendJson(res, 401, {error: 'Missing or expired MILA session'});
          return;
        }

        if (cfg.requireActiveSubscription) {
          const subscription = db.getSubscription(session.label);
          if (!subscription || subscription.activeUntil < Date.now()) {
            sendJson(res, 402, {
              error: 'Active subscription required',
              label: session.label,
            });
            return;
          }
        }

        if (!cfg.geminiApiKey) {
          sendJson(res, 500, {error: 'GEMINI_API_KEY is not configured'});
          return;
        }

        const body = await readJson(req);
        const language = normalizeLanguage(body.language);
        const token = await createGeminiLiveToken({cfg, fetchImpl});
        sendJson(res, 200, {...token, language});
        return;
      }

      if (req.method === 'POST' && url.pathname === '/v1/voice/livekit-token') {
        const session = requireSession(req, res);
        if (!session) return;

        if (
          !cfg.livekitUrl ||
          !cfg.livekitApiKey ||
          !cfg.livekitApiSecret
        ) {
          sendJson(res, 503, {error: 'LiveKit voice transport is not configured'});
          return;
        }

        if (cfg.requireActiveSubscription) {
          const subscription = db.getSubscription(session.label);
          if (!subscription || subscription.activeUntil < Date.now()) {
            sendJson(res, 402, {
              error: 'Active subscription required',
              label: session.label,
            });
            return;
          }
        }

        const body = await readJson(req);
        const language = normalizeLanguage(body.language);
        const profile = normalizeLiveProfile(body.profile);
        const owner = ownerFromJson(session.ownerJson);
        const room = `mila-${crypto.randomUUID()}`;
        const identityBase = owner?.id || owner?.email || session.label;
        const identity = `${safeIdentity(identityBase)}-${crypto.randomBytes(4).toString('hex')}`;
        const token = new AccessToken(
          cfg.livekitApiKey,
          cfg.livekitApiSecret,
          {
            identity,
            name: owner?.name || session.label || 'MILA user',
            ttl: '15m',
            metadata: JSON.stringify({
              owner: normalizeOwner(owner),
              language,
              source: 'mila-mobile',
            }),
          },
        );
        token.addGrant({
          roomJoin: true,
          room,
          canPublish: true,
          canSubscribe: true,
          canPublishData: true,
        });
        token.roomConfig = new RoomConfiguration({
          metadata: JSON.stringify({
            language,
            profile,
            source: 'agentic-os',
          }),
        });

        sendJson(res, 201, {
          server_url: cfg.livekitUrl,
          participant_token: await token.toJwt(),
          room_name: room,
          language,
        });
        return;
      }

      sendJson(res, 404, {error: 'Not found'});
    } catch (error) {
      const status = Number(error.status);
      sendJson(
        res,
        status >= 400 && status < 600 ? status : 500,
        {error: error.message || 'Server error'},
      );
    }
  });

  return {server, db};
}

function normalizeLanguage(value) {
  const raw = String(value || 'auto').trim();
  if (['ru-RU', 'uz-UZ', 'en-US', 'auto'].includes(raw)) return raw;
  if (raw.startsWith('uz')) return 'uz-UZ';
  if (raw.startsWith('en')) return 'en-US';
  if (raw.startsWith('ru')) return 'ru-RU';
  return 'auto';
}

function safeIdentity(value) {
  return String(value || 'mobile-user')
    .trim()
    .replace(/[^a-zA-Z0-9_-]/g, '-')
    .replace(/-+/g, '-')
    .slice(0, 80) || 'mobile-user';
}

/// Creates a short-lived, single-use token for an on-device Live API session.
/// The long-lived Gemini key remains on the MILA server.  We constrain the
/// model here so a copied token cannot be used with a more expensive model.
async function createGeminiLiveToken({cfg, fetchImpl}) {
  const now = Date.now();
  const upstream = await fetchImpl(
    'https://generativelanguage.googleapis.com/v1alpha/auth_tokens',
    {
      method: 'POST',
      headers: {
        'x-goog-api-key': cfg.geminiApiKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        uses: 1,
        expireTime: new Date(now + 30 * 60 * 1000).toISOString(),
        newSessionExpireTime: new Date(now + 60 * 1000).toISOString(),
        bidiGenerateContentSetup: {
          model: `models/${cfg.geminiLiveModel}`,
        },
        fieldMask: 'model',
      }),
    },
  );
  const body = await upstream.json().catch(() => ({}));
  if (!upstream.ok || typeof body.name !== 'string' || !body.name) {
    const detail = body?.error?.message || `Gemini token service error ${upstream.status}`;
    throw new Error(detail);
  }
  return {
    token: body.name,
    expiresAt: body.expireTime || null,
    newSessionExpiresAt: body.newSessionExpireTime || null,
  };
}

async function generateGeminiChat({body, cfg, fetchImpl}) {
  const model = String(body.model || 'gemini-2.5-flash').trim();
  if (!/^[a-zA-Z0-9._-]{1,100}$/.test(model)) {
    const error = new Error('Invalid Gemini model');
    error.status = 400;
    throw error;
  }

  const messages = Array.isArray(body.messages) ? body.messages.slice(-24) : [];
  const contents = messages
    .map((message) => {
      const attachments = Array.isArray(message.attachments)
        ? message.attachments.slice(0, 4)
        : [];
      return {
        role: message.role === 'assistant' ? 'model' : 'user',
        parts: [
          ...attachments
            .filter((item) => typeof item?.data === 'string' && typeof item?.mimeType === 'string')
            .map((item) => ({inlineData: {mimeType: item.mimeType, data: item.data}})),
          {text: String(message.content || '').slice(0, 30000)},
        ],
      };
    })
    .filter((message) => message.parts.some((part) => part.text || part.inlineData));
  if (!contents.length) {
    const error = new Error('A chat message is required');
    error.status = 400;
    throw error;
  }

  const upstream = await fetchImpl(
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`,
    {
      method: 'POST',
      headers: {
        'x-goog-api-key': cfg.geminiApiKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        ...(body.systemPrompt ? {systemInstruction: {parts: [{text: String(body.systemPrompt).slice(0, 30000)}]}} : {}),
        contents,
      }),
    },
  );
  const response = await upstream.json().catch(() => ({}));
  if (!upstream.ok) {
    const error = new Error(response?.error?.message || `Gemini error ${upstream.status}`);
    error.status = upstream.status;
    throw error;
  }
  const text = (response.candidates?.[0]?.content?.parts || [])
    .map((part) => String(part.text || ''))
    .join('')
    .trim();
  if (!text) {
    const error = new Error('Gemini returned an empty response');
    error.status = 502;
    throw error;
  }
  return {text, model};
}

async function streamOpenAiChat({body, res, cfg, fetchImpl}) {
  const messages = Array.isArray(body.messages) ? body.messages : [];
  const systemPrompt = String(body.systemPrompt || '');
  const model = String(body.model || cfg.defaultModel);

  const upstream = await fetchImpl('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${cfg.openAiApiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model,
      stream: true,
      messages: [
        ...(systemPrompt ? [{role: 'system', content: systemPrompt}] : []),
        ...messages.map((message) => ({
          role: message.role === 'assistant' ? 'assistant' : 'user',
          content: String(message.content || ''),
        })),
      ],
    }),
  });

  res.writeHead(upstream.status, {
    'Access-Control-Allow-Origin': cfg.allowedOrigin,
    'Cache-Control': 'no-cache, no-transform',
    'Connection': 'keep-alive',
    'Content-Type': 'text/event-stream; charset=utf-8',
  });

  if (!upstream.ok || !upstream.body) {
    const text = await upstream.text();
    res.write(`data: ${JSON.stringify({error: text})}\n\n`);
    res.end();
    return;
  }

  const reader = upstream.body.getReader();
  try {
    while (true) {
      const {done, value} = await reader.read();
      if (done) break;
      res.write(value);
    }
  } finally {
    res.end();
  }
}

function renderConnectPage() {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>MILA ChatGPT Connection</title>
  <style>
    body { margin: 0; font-family: system-ui, -apple-system, Segoe UI, sans-serif; background: #0d111b; color: white; }
    main { max-width: 520px; margin: 0 auto; padding: 48px 22px; }
    .card { background: #161c2b; border: 1px solid #ffffff22; border-radius: 18px; padding: 24px; }
    input, button { width: 100%; box-sizing: border-box; border-radius: 14px; padding: 14px 16px; font-size: 16px; }
    input { margin: 14px 0; background: #0d111b; border: 1px solid #ffffff22; color: white; }
    button { border: 0; color: white; background: linear-gradient(90deg, #7b61ff, #a855f7); font-weight: 700; }
    p { color: #9aa3b5; line-height: 1.45; }
  </style>
</head>
<body>
  <main>
    <div class="card">
      <h1>Connect ChatGPT to MILA</h1>
      <p>Enter the account label your phone will show. In production this page should be replaced by your real login/subscription flow.</p>
      <form method="post" action="/auth/openai/start">
        <input name="label" placeholder="Email or name" autocomplete="email">
        <button type="submit">Create connection code</button>
      </form>
    </div>
  </main>
</body>
</html>`;
}

function renderCodePage(code, label) {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>MILA Connection Code</title>
  <style>
    body { margin: 0; font-family: system-ui, -apple-system, Segoe UI, sans-serif; background: #0d111b; color: white; }
    main { max-width: 520px; margin: 0 auto; padding: 48px 22px; }
    .card { background: #161c2b; border: 1px solid #ffffff22; border-radius: 18px; padding: 24px; text-align: center; }
    .code { margin: 22px 0; font-size: 38px; letter-spacing: 6px; font-weight: 800; color: #00e5ff; }
    p { color: #9aa3b5; line-height: 1.45; }
  </style>
</head>
<body>
  <main>
    <div class="card">
      <h1>Paste this code in MILA</h1>
      <p>Account: ${escapeHtml(label)}</p>
      <div class="code">${code}</div>
      <p>The code expires in ten minutes.</p>
    </div>
  </main>
</body>
</html>`;
}

function defaultUpdate(platform) {
  return {
    platform,
    latestVersion: '1.0.0',
    latestCode: 1,
    minSupportedVersion: '1.0.0',
    minSupportedCode: 1,
    apkUrl: '',
    notes: 'You are using the latest available version.',
    updatedAt: 0,
  };
}

async function sendDownload(res, pathname, cfg) {
  const requested = decodeURIComponent(pathname.replace(/^\/downloads\//, ''));
  const baseDir = path.resolve(cfg.downloadsDir);
  const filePath = path.resolve(baseDir, requested);
  const relative = path.relative(baseDir, filePath);

  if (!requested || relative.startsWith('..') || path.isAbsolute(relative)) {
    sendStatus(res, 404);
    return;
  }

  try {
    const stat = await fs.promises.stat(filePath);
    if (!stat.isFile()) {
      sendStatus(res, 404);
      return;
    }

    res.writeHead(200, {
      'Access-Control-Allow-Origin': cfg.allowedOrigin,
      'Content-Length': stat.size,
      'Content-Type': contentType(filePath),
    });
    fs.createReadStream(filePath).pipe(res);
  } catch {
    sendStatus(res, 404);
  }
}

function sendStatus(res, status) {
  res.writeHead(status, {'Content-Type': 'text/plain; charset=utf-8'});
  res.end(http.STATUS_CODES[status] || 'Error');
}

function contentType(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  if (ext === '.apk') return 'application/vnd.android.package-archive';
  if (ext === '.json') return 'application/json; charset=utf-8';
  if (ext === '.txt') return 'text/plain; charset=utf-8';
  return 'application/octet-stream';
}

function normalizeUpdate(body) {
  const platform = String(body.platform || 'android').trim();
  const latestVersion = String(body.latestVersion || '').trim();
  const latestCode = Number(body.latestCode || 0);
  const minSupportedVersion = String(
    body.minSupportedVersion || latestVersion,
  ).trim();
  const minSupportedCode = Number(body.minSupportedCode || latestCode);
  const apkUrl = String(body.apkUrl || '').trim();
  const notes = String(body.notes || '').trim();

  if (!platform) throw new Error('platform is required');
  if (!latestVersion) throw new Error('latestVersion is required');
  if (!Number.isInteger(latestCode) || latestCode < 1) {
    throw new Error('latestCode must be a positive integer');
  }
  if (!Number.isInteger(minSupportedCode) || minSupportedCode < 1) {
    throw new Error('minSupportedCode must be a positive integer');
  }

  return {
    platform,
    latestVersion,
    latestCode,
    minSupportedVersion,
    minSupportedCode,
    apkUrl,
    notes,
  };
}

function normalizeSubscription(body) {
  const label = String(body.label || '').trim();
  const plan = String(body.plan || 'monthly').trim();
  const activeUntilRaw = body.activeUntil || body.activeUntilIso;
  const activeUntil = typeof activeUntilRaw === 'number'
    ? activeUntilRaw
    : Date.parse(String(activeUntilRaw || ''));

  if (!label) throw new Error('label is required');
  if (!Number.isFinite(activeUntil)) {
    throw new Error('activeUntil or activeUntilIso is required');
  }

  return {label, plan, activeUntil};
}

function loadDotEnv(filePath) {
  if (!fs.existsSync(filePath)) return;
  const lines = fs.readFileSync(filePath, 'utf8').split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const index = trimmed.indexOf('=');
    if (index < 0) continue;
    const key = trimmed.slice(0, index).trim();
    const value = trimmed.slice(index + 1).trim();
    if (!process.env[key]) process.env[key] = value;
  }
}

async function readBody(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const body = Buffer.concat(chunks).toString('utf8');
  if (body.length > 1024 * 1024) throw new Error('Request body too large');
  return body;
}

async function readJson(req) {
  const raw = await readBody(req);
  return raw ? JSON.parse(raw) : {};
}

function hashToken(token, secret) {
  return crypto.createHmac('sha256', secret).update(token).digest('hex');
}

function escapeHtml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const {server} = createMilaServer();
  server.listen(config.port, () => {
    console.log(`MILA backend listening on ${config.publicBaseUrl}`);
  });
}
