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
  sessionTtlDays: Number(process.env.SESSION_TTL_DAYS || 30),
  dbPath: process.env.DB_PATH || path.join(dirname, 'data', 'mila.db'),
  downloadsDir: process.env.DOWNLOADS_DIR || path.join(dirname, 'downloads'),
  adminToken: process.env.ADMIN_TOKEN || '',
  agenticOsUrl: (process.env.AGENTIC_OS_URL || '').replace(/\/$/, ''),
  agenticOsToken: process.env.AGENTIC_OS_TOKEN || '',
  enableOpenAiAccount: process.env.ENABLE_OPENAI_ACCOUNT === 'true',
  requireActiveSubscription: process.env.REQUIRE_ACTIVE_SUBSCRIPTION === 'true',
};

const LIVE_VOICES = new Set([
  'Sulafat', 'Achird', 'Achernar', 'Vindemiatrix', 'Leda',
  'Algieba', 'Despina', 'Schedar', 'Callirrhoe', 'Umbriel',
  'Zubenelgenubi', 'Aoede', 'Zephyr', 'Autonoe', 'Puck',
  'Laomedeia', 'Sadachbia', 'Fenrir', 'Charon', 'Rasalgethi',
  'Iapetus', 'Erinome', 'Sadaltager', 'Pulcherrima', 'Kore',
  'Orus', 'Alnilam', 'Gacrux', 'Algenib', 'Enceladus',
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
    voiceName: LIVE_VOICES.has(source.voiceName) ? source.voiceName : 'Leda',
    additionalInstructions: String(source.additionalInstructions || '').trim().slice(0, 12000),
    style: String(source.style || 'assistant').slice(0, 40),
    pace: String(source.pace || 'medium').slice(0, 40),
    delivery: String(source.delivery || 'natural').slice(0, 40),
    listeningProfile: String(source.listeningProfile || 'balanced').slice(0, 40),
    responseLength: String(source.responseLength || 'brief').slice(0, 40),
    transport: String(source.transport || 'direct').slice(0, 40),
    persona: String(source.persona || '').trim().slice(0, 1200),
    voiceDirection: String(source.voiceDirection || '').replace(/\s+/g, ' ').trim().slice(0, 240),
    affectiveDialog: source.affectiveDialog !== false,
    proactiveAudio: source.proactiveAudio !== false,
    userName: String(source.userName || '').trim().slice(0, 40),
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
  const pendingMcpCalls = new Map();

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

  function sanitizeMcpTool(server, tool = {}) {
    return {
      serverId: server.id,
      server: server.name,
      kind: server.kind,
      status: server.status || 'stopped',
      name: String(tool.name || '').slice(0, 160),
      description: String(tool.description || '').slice(0, 600),
      inputSchema: tool.inputSchema || null,
    };
  }

  function sanitizeMcpServers(servers) {
    return (Array.isArray(servers) ? servers : []).map((server) => ({
      id: String(server.id || '').slice(0, 160),
      name: String(server.name || '').slice(0, 160),
      kind: String(server.kind || '').slice(0, 80),
      desc: String(server.desc || '').slice(0, 500),
      status: String(server.status || 'stopped').slice(0, 40),
      tools: (Array.isArray(server.tools) ? server.tools : [])
        .slice(0, 100)
        .map((tool) => sanitizeMcpTool(server, tool)),
    })).filter((server) => server.id && server.name);
  }

  function cleanMcpCallArgs(body = {}) {
    const rawArgs = body.args && typeof body.args === 'object' && !Array.isArray(body.args)
      ? body.args
      : {};
    const safeArgs = JSON.parse(JSON.stringify(rawArgs));
    return {
      server: String(body.server || body.serverId || '').trim().slice(0, 160),
      tool: String(body.tool || body.name || '').trim().slice(0, 160),
      args: safeArgs,
    };
  }

  function cleanupMcpConfirmations() {
    const now = Date.now();
    for (const [token, value] of pendingMcpCalls) {
      if (value.expiresAt <= now) pendingMcpCalls.delete(token);
    }
  }

  function stageMcpCall(session, body) {
    cleanupMcpConfirmations();
    const call = cleanMcpCallArgs(body);
    if (!call.server || !call.tool) {
      const error = new Error('MCP server and tool are required');
      error.status = 400;
      throw error;
    }
    const argsText = JSON.stringify(call.args);
    if (argsText.length > 50000) {
      const error = new Error('MCP tool arguments are too large');
      error.status = 413;
      throw error;
    }
    const token = crypto.randomBytes(24).toString('base64url');
    const summary = `Call MCP tool "${call.tool}" on "${call.server}"`;
    pendingMcpCalls.set(token, {
      sessionId: session.id,
      call,
      summary,
      expiresAt: Date.now() + 5 * 60 * 1000,
    });
    return {
      confirmationRequired: true,
      confirmationToken: token,
      summary,
      expiresInSeconds: 300,
    };
  }

  function consumeMcpCall(session, token) {
    cleanupMcpConfirmations();
    const record = pendingMcpCalls.get(token);
    pendingMcpCalls.delete(token);
    if (!record || record.sessionId !== session.id || record.expiresAt <= Date.now()) {
      const error = new Error('Confirmation expired or does not match this MCP call');
      error.status = 409;
      throw error;
    }
    return record.call;
  }

  function createCode(label, owner = null, accountGrant = '') {
    const code = crypto.randomBytes(4).toString('hex').toUpperCase();
    const cleanOwner = normalizeOwner(owner);
    db.createCode(
      code,
      label || 'ChatGPT account',
      cleanOwner ? JSON.stringify(cleanOwner) : null,
      String(accountGrant || '').trim().slice(0, 8192),
      Date.now() + 10 * 60 * 1000,
    );
    return code;
  }

  function createSession(label, ownerJson = null) {
    const token = crypto.randomBytes(32).toString('base64url');
    const ttlDays = boundedInteger(cfg.sessionTtlDays, 30, 1, 90);
    db.createSession(
      hashToken(token, cfg.sessionSecret),
      label,
      crypto.randomUUID().replaceAll('-', ''),
      ownerJson,
      Date.now() + ttlDays * 24 * 60 * 60 * 1000,
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
        ...(options.headers || {}),
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

  function erpNumber(value, fallback = 0) {
    const number = Number(value);
    return Number.isFinite(number) ? number : fallback;
  }

  function erpText(value, max = 160) {
    return String(value ?? '').replace(/\s+/g, ' ').trim().slice(0, max);
  }

  function summarizeFinishedGoodsRows(finishedGoods) {
    const rows = Array.isArray(finishedGoods?.top_models)
      ? finishedGoods.top_models
      : Array.isArray(finishedGoods?.items)
        ? finishedGoods.items
        : [];
    return rows.slice(0, 8).map((row) => ({
      model: erpText(row.model_code || row.sku || row.model || row.name),
      name: erpText(row.model_name || row.name || row.title),
      order: erpText(row.order_no || row.production_no || row.order),
      pieces: erpNumber(row.total_pieces ?? row.available_pieces ?? row.pieces ?? row.quantity),
      packages: erpNumber(row.total_packages ?? row.packages),
      section: erpText(row.section),
      cell: erpText(row.cell),
      shelf: erpText(row.shelf),
      color: erpText(row.color),
    }));
  }

  function summarizeErpSnapshot(snapshot) {
    const cards = snapshot?.cards || {};
    const gm = cards.erp_gm_summary || {};
    const activeProduction = cards.erp_active_production || {};
    const business = cards.erp_business_control || {};
    const inventory = cards.erp_inventory_status || {};
    const finance = cards.erp_finance_summary || {};
    const finishedGoods = cards.erp_finished_goods_stock || {};
    const busiestFlow =
      business?.answer_hints?.busiest_sewing_flow ||
      (Array.isArray(business?.busiest_sewing_flows) ? business.busiest_sewing_flows[0] : null) ||
      {};
    const nextWarehouse =
      business?.answer_hints?.next_warehouse_order ||
      (Array.isArray(business?.warehouse_eta) ? business.warehouse_eta[0] : null) ||
      {};

    return {
      ok: Boolean(snapshot?.ok),
      source: 'Agentic OS /api/erp',
      baseUrl: erpText(snapshot?.baseUrl || cfg.agenticOsUrl, 240),
      fetchedAt: new Date().toISOString(),
      errors: snapshot?.errors || {},
      finishedGoods: {
        source: '/warehouse-stock + /warehouse-map',
        apiSource: '/api/packages/storage-map',
        pieces: erpNumber(
          finishedGoods.total_pieces ??
            finishedGoods.available_pieces ??
            finishedGoods.pieces ??
            finishedGoods.quantity,
        ),
        packages: erpNumber(finishedGoods.total_packages ?? finishedGoods.packages),
        models: erpNumber(finishedGoods.total_models ?? finishedGoods.models),
        sections: Array.isArray(finishedGoods.sections)
          ? finishedGoods.sections.slice(0, 12).map((item) => erpText(item, 60))
          : [],
        topModels: summarizeFinishedGoodsRows(finishedGoods),
      },
      production: {
        activeOrders: erpNumber(
          business.total_orders ?? activeProduction.active_work_orders ?? gm.active_orders,
        ),
        trackedOrders: erpNumber(business.total_orders),
        productionOutput: erpNumber(
          activeProduction.cutting_output ??
            gm.production_output ??
            business.production_output,
        ),
        cuttingOutput: erpNumber(activeProduction.cutting_output),
        sewingOutput: erpNumber(activeProduction.sewing_output),
        packagingOutput: erpNumber(activeProduction.packaging_output),
        reworkQty: erpNumber(activeProduction.rework_qty),
        busiestFlow: {
          flow: erpText(busiestFlow.flow || busiestFlow.name || busiestFlow.department),
          orders: erpNumber(busiestFlow.orders),
          plannedQuantity: erpNumber(busiestFlow.planned_quantity ?? busiestFlow.quantity),
        },
        nextWarehouseOrder: {
          productionNo: erpText(nextWarehouse.production_no),
          orderNo: erpText(nextWarehouse.order_no),
          model: erpText(nextWarehouse.model_code || nextWarehouse.model),
          warehouseEta: erpText(nextWarehouse.warehouse_eta || nextWarehouse.due_date),
          status: erpText(nextWarehouse.warehouse_status || nextWarehouse.status),
          quantity: erpNumber(nextWarehouse.planned_quantity ?? nextWarehouse.quantity),
        },
      },
      inventory: {
        materialItems: erpNumber(inventory.total_items ?? inventory.items?.length),
      },
      finance: {
        revenue: erpNumber(finance.revenue_total ?? gm.revenue),
        payments: erpNumber(finance.payments_received),
        stockValue: erpNumber(finance.branded_stock_value ?? gm.branded_stock_value),
      },
      tools: Array.isArray(snapshot?.server?.tools) ? snapshot.server.tools.length : 0,
    };
  }

  function formatErpVoiceInstruction(summary) {
    const fg = summary.finishedGoods || {};
    const production = summary.production || {};
    const models = (fg.topModels || [])
      .map((row) => {
        const location = [row.section, row.cell, row.shelf].filter(Boolean).join('/');
        return `${row.model || row.name || 'unknown'}: ${row.pieces} pcs${row.name ? `, ${row.name}` : ''}${row.order ? `, order ${row.order}` : ''}${location ? `, ${location}` : ''}`;
      })
      .join('; ');
    return [
      'AUTHORITATIVE LIVE ERP CONTEXT.',
      'Use this for Milana ERP business questions before answering. If the user asks for ERP facts and this context is stale or unavailable, call the ERP tool instead of guessing.',
      `Finished goods warehouse source: ${fg.source}. This is the only source for готовые изделия / finished goods stock.`,
      `Finished goods now: ${fg.pieces} pcs, ${fg.packages} packages, ${fg.models} models.`,
      models ? `Finished goods rows: ${models}.` : 'Finished goods rows: no model rows returned.',
      `Production/process source is separate: active orders ${production.activeOrders}, tracked orders ${production.trackedOrders}, cutting ${production.cuttingOutput}, sewing ${production.sewingOutput}, packaging ${production.packagingOutput}, rework ${production.reworkQty}.`,
      production.busiestFlow?.flow
        ? `Busiest sewing flow: ${production.busiestFlow.flow}, ${production.busiestFlow.plannedQuantity} pcs.`
        : 'Busiest sewing flow: not returned.',
      production.nextWarehouseOrder?.productionNo
        ? `Next warehouse order: ${production.nextWarehouseOrder.productionNo}, model ${production.nextWarehouseOrder.model}, ETA ${production.nextWarehouseOrder.warehouseEta}.`
        : 'Next warehouse order: not returned.',
      'Never mix material inventory, production output, and finished goods warehouse. Never invent model names, quantities, sections, cells, dates, or prices.',
    ].join('\n').slice(0, 7000);
  }

  async function buildErpVoiceBriefing() {
    if (!cfg.agenticOsUrl || !cfg.agenticOsToken) return null;
    try {
      const snapshot = await agenticRequest('/api/erp');
      const summary = summarizeErpSnapshot(snapshot);
      return {
        ...summary,
        instruction: formatErpVoiceInstruction(summary),
      };
    } catch (error) {
      return {
        ok: false,
        source: 'Agentic OS /api/erp',
        fetchedAt: new Date().toISOString(),
        error: error.message || 'ERP context unavailable',
        instruction:
          'ERP live context is unavailable for this voice room. For ERP questions, say that live ERP data could not be verified instead of guessing.',
      };
    }
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
        const code = createCode(label, owner, body.accountGrant);
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
        sendJson(res, 200, {
          token,
          ...publicSession(record),
          ...(record.accountGrant ? {accountGrant: record.accountGrant} : {}),
        });
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

      if (req.method === 'GET' && url.pathname === '/v1/tools/mcp') {
        const session = requireSession(req, res);
        if (!session) return;
        const servers = sanitizeMcpServers(await agenticRequest('/api/mcp/servers'));
        sendJson(res, 200, {
          ok: true,
          account: publicSession(session),
          servers,
          tools: servers.flatMap((server) => server.tools || []),
          syncedAt: Date.now(),
        });
        return;
      }

      if (req.method === 'GET' && url.pathname === '/v1/erp/context') {
        const session = requireSession(req, res);
        if (!session) return;
        sendJson(res, 200, (await buildErpVoiceBriefing()) || {
          ok: false,
          error: 'Agentic OS ERP context is not configured',
        });
        return;
      }

      if (req.method === 'POST' && url.pathname === '/v1/tools/mcp/call') {
        const session = requireSession(req, res);
        if (!session) return;
        const body = await readJson(req);
        if (!body.confirmationToken) {
          sendJson(res, 202, stageMcpCall(session, body));
          return;
        }

        const call = consumeMcpCall(session, String(body.confirmationToken || ''));
        const servers = sanitizeMcpServers(await agenticRequest('/api/mcp/servers'));
        const server = servers.find((item) => item.id === call.server || item.name === call.server);
        if (!server) {
          sendJson(res, 404, {error: `MCP server not found: ${call.server}`});
          return;
        }
        if (server.status !== 'active') {
          await agenticRequest(`/api/mcp/servers/${encodeURIComponent(server.id)}/connect`, {
            method: 'POST',
            headers: {'X-Agent-Name': publicSession(session).owner.name || session.label, 'X-Agent-Source': 'mila-mobile'},
          });
        }
        const result = await agenticRequest(`/api/mcp/servers/${encodeURIComponent(server.id)}/call`, {
          method: 'POST',
          headers: {'X-Agent-Name': publicSession(session).owner.name || session.label, 'X-Agent-Source': 'mila-mobile'},
          body: {tool: call.tool, args: call.args},
        });
        sendJson(res, 200, {
          ok: true,
          server: {id: server.id, name: server.name, kind: server.kind},
          tool: call.tool,
          result: result.result,
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
        const erpContext = shouldAttachErpContext(body)
          ? await buildErpVoiceBriefing()
          : null;
        const directErpAnswer = maybeAnswerErpDirectly(body, erpContext);
        if (directErpAnswer) {
          sendJson(res, 200, directErpAnswer);
          return;
        }
        sendJson(res, 200, await generateGeminiChat({
          body,
          cfg,
          fetchImpl,
          erpContext,
        }));
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
        const erp = await buildErpVoiceBriefing();
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
              erpReady: Boolean(erp?.ok),
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
            // Who placed the call. The participant pass has carried this all
            // along, but the agent reads room metadata, so it never learned who
            // it was speaking to — and therefore authenticated to Agentic OS as
            // the installation itself, which resolves to the owner. It was the
            // owner on everybody's call. Naming the caller here is what lets it
            // ask for a credential of their own instead.
            ...(owner ? {owner: normalizeOwner(owner)} : {}),
            ...(erp ? {erp} : {}),
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

function textFromChatBody(body) {
  const messages = Array.isArray(body?.messages) ? body.messages : [];
  return messages
    .slice(-8)
    .map((message) => String(message?.content || ''))
    .join('\n')
    .toLowerCase();
}

function shouldAttachErpContext(body) {
  const text = textFromChatBody(body);
  return /\b(erp|warehouse|stock|inventory|production|order|sewing|packaging|cutting|finance|revenue|factory)\b/.test(text) ||
    /(склад|остатк|готов(ых|ые|ая|ой)?\s+издел|готов(ая|ой|ую)?\s+продукц|производств|заказ|пошив|упаковк|раскро|закрой|выручк|финанс|модель|товар|ячейк|полк|секци)/i.test(text) ||
    /(ombor|tayyor|mahsulot|ishlab|buyurtma|tikuv|qadoq|bichuv|moliya|daromad|model)/i.test(text);
}

function latestChatText(body) {
  const messages = Array.isArray(body?.messages) ? body.messages : [];
  const last = [...messages].reverse().find((message) => message?.role !== 'assistant');
  return String(last?.content || '').trim();
}

function isFinishedGoodsQuestion(text) {
  const normalized = String(text || '').toLowerCase();
  return (
    /(готов(ых|ые|ая|ой|ую)?\s+(издел|продукц|товар|вещ)|склад\s+готов|готов.*склад|warehouse.*finished|finished.*warehouse|finished\s+goods)/i.test(normalized) ||
    /(склад|остатк|warehouse|stock|ombor)/i.test(normalized) &&
      /(сколько|количеств|штук|pcs|items|вещ|товар|mahsulot|qancha|nechta)/i.test(normalized)
  );
}

function directErpNumber(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function directErpText(value, max = 160) {
  return String(value ?? '').replace(/\s+/g, ' ').trim().slice(0, max);
}

function directFinishedGoodsAnswer(erpContext) {
  const fg = erpContext?.finishedGoods || {};
  const pieces = directErpNumber(
    fg.pieces ??
      fg.total_pieces ??
      fg.available_pieces ??
      fg.quantity,
    Number.NaN,
  );
  if (!Number.isFinite(pieces)) return null;
  const packages = directErpNumber(fg.packages ?? fg.total_packages, Number.NaN);
  const models = directErpNumber(fg.models ?? fg.total_models, Number.NaN);
  const top = Array.isArray(fg.topModels) ? fg.topModels[0] : null;
  const details = [];
  if (Number.isFinite(packages)) details.push(`${packages} упаковок`);
  if (Number.isFinite(models)) details.push(`${models} модель`);
  if (top) {
    const model = directErpText(top.model || top.name);
    const name = directErpText(top.name);
    const rowPieces = directErpNumber(top.pieces, Number.NaN);
    const location = [top.section, top.cell, top.shelf].map((item) => directErpText(item, 40)).filter(Boolean).join('/');
    const topDetails = [
      model ? `${model}${name && name !== model ? ` (${name})` : ''}` : '',
      Number.isFinite(rowPieces) ? `${rowPieces} шт.` : '',
      location ? `локация ${location}` : '',
    ].filter(Boolean).join(', ');
    if (topDetails) details.push(`основная строка: ${topDetails}`);
  }
  return {
    text: `На складе готовых изделий сейчас ${pieces} шт.${details.length ? ` ${details.join('; ')}.` : ''}`,
    model: 'erp-direct',
    source: '/warehouse-stock + /warehouse-map',
  };
}

function maybeAnswerErpDirectly(body, erpContext) {
  if (!erpContext?.ok) return null;
  const latest = latestChatText(body);
  if (isFinishedGoodsQuestion(latest)) {
    return directFinishedGoodsAnswer(erpContext);
  }
  return null;
}

function composeMobileErpPrompt(erpContext) {
  if (!erpContext) return '';
  const instruction = String(erpContext.instruction || '').trim();
  const fallback = JSON.stringify(erpContext, null, 2);
  return [
    'MOBILE MILA ERP FACTS.',
    'For Milana ERP questions, answer only from the live ERP context below. If erpContext.ok is true, never say you failed to get ERP data. If the exact fact is absent, say only that this exact field is not present in the returned ERP snapshot. Do not invent numbers, model names, orders, warehouse cells, dates, or prices.',
    'Critical warehouse rule: готовые изделия / finished goods stock must come only from /warehouse-stock and /warehouse-map, exposed as finishedGoods / erp_finished_goods_stock. Never use production output, material inventory, GM summary, or memory as the answer for finished goods.',
    'If the user asks "сколько готовых изделий на складе", answer the finishedGoods.pieces value and, if available, mention packages/models and top model rows.',
    instruction || fallback,
  ].join('\n').slice(0, 12000);
}

async function generateGeminiChat({body, cfg, fetchImpl, erpContext = null}) {
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

  const systemPrompt = [
    String(body.systemPrompt || '').trim(),
    composeMobileErpPrompt(erpContext),
  ].filter(Boolean).join('\n\n');

  const upstream = await fetchImpl(
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`,
    {
      method: 'POST',
      headers: {
        'x-goog-api-key': cfg.geminiApiKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        ...(systemPrompt ? {systemInstruction: {parts: [{text: systemPrompt.slice(0, 30000)}]}} : {}),
        ...(body.groundWithGoogleSearch === false ? {} : {tools: [{googleSearch: {}}]}),
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
