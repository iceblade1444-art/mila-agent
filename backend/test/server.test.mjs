import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {test} from 'node:test';
import {TokenVerifier} from 'livekit-server-sdk';

import {createAppDb} from '../db.mjs';
import {createMilaServer, normalizeLiveProfile} from '../server.mjs';

async function withServer(options, run) {
  const merged = {
    ...options,
    config: {
      dbPath: ':memory:',
      ...(options.config || {}),
    },
  };
  const {server} = createMilaServer(merged);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const {port} = server.address();
  const baseUrl = `http://127.0.0.1:${port}`;
  try {
    await run(baseUrl);
  } finally {
    await new Promise((resolve, reject) =>
      server.close((error) => (error ? reject(error) : resolve())),
    );
  }
}

async function connectMobile(baseUrl, label = 'Mobile tester', owner = null) {
  const issued = await fetch(`${baseUrl}/admin/connection-code`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Admin-Token': 'admin-secret',
    },
    body: JSON.stringify({label, ...(owner ? {owner} : {})}),
  });
  const {code} = await issued.json();
  const exchange = await fetch(`${baseUrl}/v1/auth/device`, {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({code}),
  });
  return exchange.json();
}

test('health endpoint returns ok', async () => {
  await withServer({}, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/health`);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {ok: true, db: true});
  });
});

test('admin status reports capabilities without exposing secrets', async () => {
  await withServer(
    {
      config: {
        adminToken: 'admin-secret',
        geminiApiKey: 'gemini-secret',
        openAiApiKey: '',
      },
    },
    async (baseUrl) => {
      const denied = await fetch(`${baseUrl}/admin/status`);
      assert.equal(denied.status, 403);

      const response = await fetch(`${baseUrl}/admin/status`, {
        headers: {'X-Admin-Token': 'admin-secret'},
      });
      assert.equal(response.status, 200);
      const json = await response.json();
      assert.equal(json.voiceConfigured, true);
      assert.equal(json.chatConfigured, false);
      assert.equal(JSON.stringify(json).includes('gemini-secret'), false);
    },
  );
});

test('admin can issue a one-time MILA connection code', async () => {
  await withServer(
    {config: {adminToken: 'admin-secret', enableOpenAiAccount: false}},
    async (baseUrl) => {
      const issued = await fetch(`${baseUrl}/admin/connection-code`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Admin-Token': 'admin-secret',
        },
        body: JSON.stringify({label: 'Mila mobile'}),
      });
      assert.equal(issued.status, 200);
      const issuedJson = await issued.json();
      const {code} = issuedJson;
      assert.match(code, /^[A-F0-9]{8}$/);
      assert.equal(issuedJson.owner, null);

      const exchange = await fetch(`${baseUrl}/v1/auth/device`, {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({code}),
      });
      assert.equal(exchange.status, 200);
      const session = await exchange.json();
      assert.equal(session.label, 'Mila mobile');
      assert.ok(session.token.length > 20);

      const reused = await fetch(`${baseUrl}/v1/auth/device`, {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({code}),
      });
      assert.equal(reused.status, 400);
    },
  );
});

test('Agentic OS connection code unifies the mobile session owner', async () => {
  await withServer(
    {config: {adminToken: 'admin-secret'}},
    async (baseUrl) => {
      const session = await connectMobile(baseUrl, 'iceblade1444@gmail.com', {
        id: 'creator',
        email: 'iceblade1444@gmail.com',
        name: 'Creator',
        role: 'Creator',
      });
      assert.equal(session.label, 'iceblade1444@gmail.com');
      assert.deepEqual(session.owner, {
        id: 'creator',
        email: 'iceblade1444@gmail.com',
        name: 'Creator',
        role: 'Creator',
      });
    },
  );
});

test('Agentic OS connection code returns the short-lived account grant once', async () => {
  await withServer(
    {config: {adminToken: 'admin-secret'}},
    async (baseUrl) => {
      const issued = await fetch(`${baseUrl}/admin/connection-code`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Admin-Token': 'admin-secret',
        },
        body: JSON.stringify({
          label: 'Mobile member',
          accountGrant: 'signed-short-lived-grant',
        }),
      });
      const {code} = await issued.json();
      const exchange = await fetch(`${baseUrl}/v1/auth/device`, {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({code}),
      });
      const session = await exchange.json();
      assert.equal(session.accountGrant, 'signed-short-lived-grant');

      const reused = await fetch(`${baseUrl}/v1/auth/device`, {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({code}),
      });
      assert.equal(reused.status, 400);
    },
  );
});

test('expired MILA sessions are rejected and removed', () => {
  const db = createAppDb(':memory:');
  try {
    db.createSession('expired-hash', 'Old device', 'a'.repeat(32), null, Date.now() - 1);
    assert.equal(db.getSession('expired-hash'), undefined);
    assert.deepEqual(db.listSessions(), []);

    db.createSession('active-hash', 'Current device', 'b'.repeat(32), null, Date.now() + 10000);
    assert.equal(db.getSession('active-hash').label, 'Current device');
    assert.equal(db.listSessions()[0].active, true);
  } finally {
    db.close();
  }
});

test('authenticated Agentic OS account creates a private MILA voice session', async () => {
  const calls = [];
  await withServer(
    {
      config: {agenticOsUrl: 'http://agentic-os.internal:8787'},
      fetchImpl: async (url, request = {}) => {
        calls.push({url, request});
        return Response.json({
          authed: true,
          user: {
            id: 'usr_mobile',
            email: 'mobile@example.com',
            name: 'Mobile Member',
            role: 'Member',
          },
        });
      },
    },
    async (baseUrl) => {
      const denied = await fetch(`${baseUrl}/v1/auth/agentic`, {method: 'POST'});
      assert.equal(denied.status, 401);

      const response = await fetch(`${baseUrl}/v1/auth/agentic`, {
        method: 'POST',
        headers: {Authorization: 'Bearer account-token'},
      });
      assert.equal(response.status, 201);
      const session = await response.json();
      assert.ok(session.token.length > 20);
      assert.equal(session.label, 'mobile@example.com');
      assert.deepEqual(session.owner, {
        id: 'usr_mobile',
        email: 'mobile@example.com',
        name: 'Mobile Member',
        role: 'Member',
      });
    },
  );
  assert.equal(calls[0].url, 'http://agentic-os.internal:8787/api/auth/me');
  assert.equal(calls[0].request.headers.Authorization, 'Bearer account-token');
});

test('admin can list and revoke a specific mobile device without exposing tokens', async () => {
  await withServer(
    {config: {adminToken: 'admin-secret'}},
    async (baseUrl) => {
      const {token, label} = await connectMobile(baseUrl, 'Creator phone');
      const headers = {'X-Admin-Token': 'admin-secret'};
      const listed = await fetch(`${baseUrl}/admin/devices`, {headers});
      assert.equal(listed.status, 200);
      const devices = (await listed.json()).devices;
      const device = devices.find((item) => item.label === label);
      assert.match(device.id, /^[a-f0-9]{32}$/);
      assert.equal(device.active, true);
      assert.equal(JSON.stringify(devices).includes(token), false);

      const revoked = await fetch(`${baseUrl}/admin/devices/${device.id}`, {
        method: 'DELETE', headers,
      });
      assert.equal(revoked.status, 200);
      const denied = await fetch(`${baseUrl}/v1/agentic/status`, {
        headers: {Authorization: `Bearer ${token}`},
      });
      assert.equal(denied.status, 401);
    },
  );
});

test('connected mobile can use the secure Gemini text proxy without receiving the provider key', async () => {
  const fetchImpl = async (url, request = {}) => {
    assert.match(url, /gemini-2\.5-flash:generateContent$/);
    assert.equal(request.headers['x-goog-api-key'], 'gemini-secret');
    const body = JSON.parse(request.body);
    assert.equal(body.contents[0].parts[0].text, 'Hello');
    assert.deepEqual(body.tools, [{googleSearch: {}}]);
    return Response.json({
      candidates: [{content: {parts: [{text: 'Hello from MILA'}]}}],
    });
  };
  await withServer(
    {
      fetchImpl,
      config: {adminToken: 'admin-secret', geminiApiKey: 'gemini-secret'},
    },
    async (baseUrl) => {
      const {token} = await connectMobile(baseUrl);
      const response = await fetch(`${baseUrl}/v1/gemini/chat`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: 'gemini-2.5-flash',
          systemPrompt: 'Be helpful',
          messages: [{role: 'user', content: 'Hello'}],
        }),
      });
      assert.equal(response.status, 200);
      assert.deepEqual(await response.json(), {
        text: 'Hello from MILA', model: 'gemini-2.5-flash',
      });
    },
  );
});

test('Gemini mobile chat answers finished goods stock directly from live ERP context', async () => {
  const calls = [];
  const fetchImpl = async (url, request = {}) => {
    calls.push({url, request});
    const pathname = new URL(url).pathname;
    if (pathname === '/api/mila/agent-token') {
      assert.equal(request.headers.Authorization, 'Bearer agentic-secret');
      return Response.json({token: 'scoped-creator-token'});
    }
    if (pathname === '/api/erp') {
      assert.equal(request.headers.Authorization, 'Bearer scoped-creator-token');
      return Response.json({
        ok: true,
        baseUrl: 'https://erp.milanapremium.uz',
        cards: {
          erp_finished_goods_stock: {
            total_pieces: 535,
            total_packages: 9,
            total_models: 1,
            top_models: [
              {
                model_code: 'PJ1118-2922',
                model_name: 'Фут-штаны',
                order_no: 'SO-2026-000017',
                total_pieces: 535,
                total_packages: 9,
                section: 'N',
                cell: 'N-01',
                shelf: 'S1',
              },
            ],
          },
          erp_active_production: {
            cutting_output: 14654,
            sewing_output: 535,
            packaging_output: 535,
            active_work_orders: 47,
          },
          erp_business_control: {total_orders: 93},
        },
        server: {tools: [{name: 'erp_finished_goods_stock'}]},
      });
    }
    throw new Error(`Gemini should not be called for direct ERP facts: ${url}`);
  };

  await withServer(
    {
      fetchImpl,
      config: {
        adminToken: 'admin-secret',
        geminiApiKey: 'gemini-secret',
        agenticOsUrl: 'http://agentic-os.internal:8787',
        agenticOsToken: 'agentic-secret',
      },
    },
    async (baseUrl) => {
      const {token} = await connectMobile(baseUrl, 'Mobile manager', {
        id: 'creator', email: 'owner@example.test', name: 'Owner', role: 'Creator',
      });
      const response = await fetch(`${baseUrl}/v1/gemini/chat`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: 'gemini-2.5-flash',
          systemPrompt: 'Be helpful',
          messages: [
            {
              role: 'user',
              content: 'Мила, сколько сейчас готовых изделий на складе?',
            },
          ],
        }),
      });
      assert.equal(response.status, 200);
      const payload = await response.json();
      assert.equal(payload.model, 'erp-direct');
      assert.match(payload.text, /535 шт/);
      assert.match(payload.text, /9 упаковок/);
      assert.match(payload.text, /1 модель/);
      assert.match(payload.text, /PJ1118-2922/);
      assert.equal(payload.source, '/warehouse-stock + /warehouse-map');
    },
  );

  assert.ok(calls.some((call) => call.url === 'http://agentic-os.internal:8787/api/erp'));
  assert.equal(calls.filter((call) => /generateContent$/.test(call.url)).length, 0);
});

test('Gemini mobile chat receives live ERP context for non-direct ERP questions', async () => {
  const calls = [];
  let geminiBody = null;
  const fetchImpl = async (url, request = {}) => {
    calls.push({url, request});
    const pathname = new URL(url).pathname;
    if (pathname === '/api/mila/agent-token') {
      return Response.json({token: 'scoped-creator-token'});
    }
    if (pathname === '/api/erp') {
      assert.equal(request.headers.Authorization, 'Bearer scoped-creator-token');
      return Response.json({
        ok: true,
        baseUrl: 'https://erp.milanapremium.uz',
        cards: {
          erp_finished_goods_stock: {
            total_pieces: 535,
            total_packages: 9,
            total_models: 1,
            top_models: [{model_code: 'PJ1118-2922', model_name: 'Фут-штаны', total_pieces: 535}],
          },
        },
        server: {tools: [{name: 'erp_finished_goods_stock'}]},
      });
    }
    assert.match(url, /gemini-2\.5-flash:generateContent$/);
    geminiBody = JSON.parse(request.body);
    return Response.json({
      candidates: [{content: {parts: [{text: 'ERP context attached.'}]}}],
    });
  };

  await withServer(
    {
      fetchImpl,
      config: {
        adminToken: 'admin-secret',
        geminiApiKey: 'gemini-secret',
        agenticOsUrl: 'http://agentic-os.internal:8787',
        agenticOsToken: 'agentic-secret',
      },
    },
    async (baseUrl) => {
      const {token} = await connectMobile(baseUrl, 'Mobile manager', {
        id: 'creator', email: 'owner@example.test', name: 'Owner', role: 'Creator',
      });
      const response = await fetch(`${baseUrl}/v1/gemini/chat`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: 'gemini-2.5-flash',
          systemPrompt: 'Be helpful',
          messages: [{role: 'user', content: 'Мила, сделай общий ERP обзор.'}],
        }),
      });
      assert.equal(response.status, 200);
      assert.equal((await response.json()).text, 'ERP context attached.');
    },
  );

  const systemText = geminiBody.systemInstruction.parts[0].text;
  assert.match(systemText, /MOBILE MILA ERP FACTS/);
  assert.match(systemText, /535 pcs/);
  assert.match(systemText, /PJ1118-2922/);
  assert.match(systemText, /warehouse-stock/);
  assert.match(systemText, /Never use production output/);
});

test('member mobile sessions receive only scoped production data and cannot use MCP or Kanban', async () => {
  const calls = [];
  const fetchImpl = async (url, request = {}) => {
    const pathname = new URL(url).pathname;
    calls.push(pathname);
    if (pathname === '/api/mila/agent-token') {
      assert.equal(request.headers.Authorization, 'Bearer agentic-secret');
      assert.deepEqual(JSON.parse(request.body), {userId: 'usr_member', channel: 'mobile'});
      return Response.json({token: 'scoped-member-token'});
    }
    if (pathname === '/api/production') {
      assert.equal(request.headers.Authorization, 'Bearer scoped-member-token');
      return Response.json({
        ok: true,
        access: 'own',
        scope: {type: 'employee', id: 'usr_member', name: 'Employee'},
        metrics: {taskCount: 1},
        tasks: [{id: 'mine', employee_id: 'ERP-17'}],
      });
    }
    return Response.json({error: 'unexpected'}, {status: 500});
  };

  await withServer({
    fetchImpl,
    config: {
      adminToken: 'admin-secret',
      agenticOsUrl: 'http://agentic-os.internal:8787',
      agenticOsToken: 'agentic-secret',
    },
  }, async (baseUrl) => {
    const {token} = await connectMobile(baseUrl, 'Employee phone', {
      id: 'usr_member', email: 'employee@example.test', name: 'Employee', role: 'Member',
    });
    const headers = {Authorization: `Bearer ${token}`};
    const production = await fetch(`${baseUrl}/v1/erp/context`, {headers});
    assert.equal(production.status, 200);
    const body = await production.json();
    assert.equal(body.access, 'own');
    assert.deepEqual(body.tasks.map((item) => item.id), ['mine']);
    assert.equal((await fetch(`${baseUrl}/v1/tools/mcp`, {headers})).status, 403);
    assert.equal((await fetch(`${baseUrl}/v1/tasks`, {headers})).status, 403);
  });

  assert.equal(calls.includes('/api/erp'), false);
  assert.equal(calls.includes('/api/mcp/servers'), false);
  assert.equal(calls.includes('/api/kanban/board'), false);
});

test('mobile session synchronizes tasks through the private Agentic OS proxy', async () => {
  const calls = [];
  let memoryContent = '';
  const fetchImpl = async (url, request = {}) => {
    calls.push({url, request});
    assert.equal(request.headers.Authorization, 'Bearer agentic-secret');
    const pathname = new URL(url).pathname;
    if (pathname === '/api/kanban/profiles') {
      return Response.json({profiles: [{name: 'default'}, {name: 'scout'}]});
    }
    if (pathname === '/api/kanban/orchestration') {
      return Response.json({orchestrator_profile: 'default', auto_decompose: true});
    }
    if (pathname === '/api/kanban/board') {
      return Response.json({
        columns: [
          {name: 'running', tasks: [{id: 't_live1', title: 'Research market', assignee: 'scout'}]},
          {name: 'done', tasks: []},
        ],
      });
    }
    if (pathname === '/api/knowledge/status') {
      return Response.json({
        ready: true,
        writable: true,
        notes: 7,
        folders: 3,
        mcp: {status: 'active'},
      });
    }
    if (pathname === '/api/operations/status') {
      return Response.json({
        available: true,
        readiness: {status: 'healthy', score: 95},
      });
    }
    if (pathname === '/api/integrations/mila/status') {
      return Response.json({
        voiceConfigured: true,
        liveModel: 'gemini-3.1-flash-live-preview',
      });
    }
    if (pathname === '/api/kanban/tasks' && request.method === 'POST') {
      const body = JSON.parse(request.body);
      assert.equal(body.initialStatus, 'triage');
      assert.equal(body.assignee, 'default');
      return Response.json({task: {id: 't_new1', ...body, status: 'triage'}});
    }
    if (pathname === '/api/kanban/dispatch') return Response.json({claimed: 0});
    if (pathname === '/api/knowledge/notes') {
      const notePath = new URL(url).searchParams.get('q');
      return Response.json(memoryContent ? [{path: notePath}] : []);
    }
    if (pathname === '/api/knowledge/notes/read') {
      return Response.json({content: memoryContent});
    }
    if (pathname === '/api/knowledge/notes/append') {
      const body = JSON.parse(request.body);
      memoryContent += `${memoryContent ? '\n' : ''}${body.text}`;
      return Response.json({path: body.path, content: memoryContent});
    }
    return Response.json({error: 'unexpected path'}, {status: 404});
  };

  await withServer(
    {
      fetchImpl,
      config: {
        adminToken: 'admin-secret',
        agenticOsUrl: 'http://agentic-os.internal:8787',
        agenticOsToken: 'agentic-secret',
      },
    },
    async (baseUrl) => {
      const {token} = await connectMobile(baseUrl, 'Creator', {
        id: 'creator',
        email: 'creator@example.com',
        name: 'Creator',
        role: 'Creator',
      });
      const headers = {Authorization: `Bearer ${token}`};

      const denied = await fetch(`${baseUrl}/v1/tasks`);
      assert.equal(denied.status, 401);

      const status = await fetch(`${baseUrl}/v1/agentic/status`, {headers});
      assert.equal(status.status, 200);
      const statusJson = await status.json();
      assert.equal(statusJson.profiles.length, 2);
      assert.equal(statusJson.orchestration.orchestrator_profile, 'default');

      const list = await fetch(`${baseUrl}/v1/tasks`, {headers});
      const listJson = await list.json();
      assert.equal(listJson.tasks[0].status, 'running');
      assert.equal(listJson.tasks[0].assignee, 'scout');

      const dashboard = await fetch(`${baseUrl}/v1/dashboard`, {headers});
      assert.equal(dashboard.status, 200);
      const dashboardJson = await dashboard.json();
      assert.equal(dashboardJson.account.owner.email, 'creator@example.com');
      assert.equal(dashboardJson.tasks.running, 1);
      assert.equal(dashboardJson.knowledge.notes, 7);
      assert.equal(dashboardJson.mila.voiceConfigured, true);

      const create = await fetch(`${baseUrl}/v1/tasks`, {
        method: 'POST',
        headers: {...headers, 'Content-Type': 'application/json'},
        body: JSON.stringify({title: 'Plan launch', body: 'Return a verified plan'}),
      });
      assert.equal(create.status, 201);
      assert.equal((await create.json()).task.id, 't_new1');

      const saveMemory = await fetch(`${baseUrl}/v1/memory`, {
        method: 'POST',
        headers: {...headers, 'Content-Type': 'application/json'},
        body: JSON.stringify({
          text: 'Prefers concise briefings',
          category: 'preferences',
        }),
      });
      assert.equal(saveMemory.status, 201);
      const savedItem = (await saveMemory.json()).item;
      assert.match(savedItem.id, /^[a-f0-9]{16}$/);

      const memory = await fetch(`${baseUrl}/v1/memory`, {headers});
      assert.equal((await memory.json()).items[0].text, 'Prefers concise briefings');

      const removeMemory = await fetch(
        `${baseUrl}/v1/memory/${savedItem.id}`,
        {method: 'DELETE', headers},
      );
      assert.equal(removeMemory.status, 200);
      const afterDelete = await fetch(`${baseUrl}/v1/memory`, {headers});
      assert.deepEqual((await afterDelete.json()).items, []);
    },
  );

  assert.ok(calls.some((call) => call.url.endsWith('/api/kanban/dispatch')));
  assert.ok(calls.some((call) => {
    if (!call.url.endsWith('/api/knowledge/notes/append')) return false;
    return JSON.parse(call.request.body).path === 'Agentic OS/People/creator/MILA Mobile Memory.md';
  }));
});

test('mobile session can discover and confirm Agentic OS MCP tool calls safely', async () => {
  const calls = [];
  const fetchImpl = async (url, request = {}) => {
    calls.push({url, request});
    assert.equal(request.headers.Authorization, 'Bearer agentic-secret');
    const pathname = new URL(url).pathname;
    if (pathname === '/api/mcp/servers') {
      return Response.json([
        {
          id: 'mcp_obsidian',
          name: 'obsidian',
          kind: 'obsidian',
          desc: 'Shared vault',
          status: 'stopped',
          command: 'node',
          tools: [
            {
              name: 'obsidian_search_notes',
              description: 'Search notes',
              inputSchema: {type: 'object'},
            },
          ],
        },
      ]);
    }
    if (pathname === '/api/mcp/servers/mcp_obsidian/connect') {
      return Response.json({ok: true, tools: [{name: 'obsidian_search_notes'}]});
    }
    if (pathname === '/api/mcp/servers/mcp_obsidian/call') {
      const body = JSON.parse(request.body);
      assert.equal(request.headers['X-Agent-Source'], 'mila-mobile');
      assert.equal(body.tool, 'obsidian_search_notes');
      assert.deepEqual(body.args, {query: 'MILA'});
      return Response.json({ok: true, result: {content: [{type: 'text', text: 'Found MILA'}]}});
    }
    return Response.json({error: 'unexpected path'}, {status: 404});
  };

  await withServer(
    {
      fetchImpl,
      config: {
        adminToken: 'admin-secret',
        agenticOsUrl: 'http://agentic-os.internal:8787',
        agenticOsToken: 'agentic-secret',
      },
    },
    async (baseUrl) => {
      const {token} = await connectMobile(baseUrl, 'Creator phone', {
        id: 'creator',
        email: 'creator@example.com',
        name: 'Creator',
        role: 'Creator',
      });
      const headers = {Authorization: `Bearer ${token}`};

      const tools = await fetch(`${baseUrl}/v1/tools/mcp`, {headers});
      assert.equal(tools.status, 200);
      const toolsJson = await tools.json();
      assert.equal(toolsJson.tools[0].name, 'obsidian_search_notes');
      assert.equal(JSON.stringify(toolsJson).includes('command'), false);

      const staged = await fetch(`${baseUrl}/v1/tools/mcp/call`, {
        method: 'POST',
        headers: {...headers, 'Content-Type': 'application/json'},
        body: JSON.stringify({
          server: 'obsidian',
          tool: 'obsidian_search_notes',
          args: {query: 'MILA'},
        }),
      });
      assert.equal(staged.status, 202);
      const stagedJson = await staged.json();
      assert.equal(stagedJson.confirmationRequired, true);

      const confirmed = await fetch(`${baseUrl}/v1/tools/mcp/call`, {
        method: 'POST',
        headers: {...headers, 'Content-Type': 'application/json'},
        body: JSON.stringify({confirmationToken: stagedJson.confirmationToken}),
      });
      assert.equal(confirmed.status, 200);
      assert.equal((await confirmed.json()).result.content[0].text, 'Found MILA');
    },
  );

  assert.ok(calls.some((call) => call.url.endsWith('/api/mcp/servers/mcp_obsidian/connect')));
  assert.ok(calls.some((call) => call.url.endsWith('/api/mcp/servers/mcp_obsidian/call')));
});

test('app update metadata can be saved and checked', async () => {
  await withServer(
    {config: {adminToken: 'secret'}},
    async (baseUrl) => {
      const save = await fetch(`${baseUrl}/admin/app/update`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Admin-Token': 'secret',
        },
        body: JSON.stringify({
          platform: 'android',
          latestVersion: '1.0.1',
          latestCode: 2,
          minSupportedVersion: '1.0.0',
          minSupportedCode: 1,
          apkUrl: 'https://example.com/app.apk',
          notes: 'Bug fixes',
        }),
      });
      assert.equal(save.status, 200);

      const check = await fetch(
        `${baseUrl}/v1/app/update?platform=android&versionCode=1`,
      );
      assert.equal(check.status, 200);
      const json = await check.json();
      assert.equal(json.latestCode, 2);
      assert.equal(json.updateAvailable, true);
      assert.equal(json.updateRequired, false);
    },
  );
});

test('downloads endpoint serves APK files from the downloads directory', async () => {
  const downloadsDir = fs.mkdtempSync(path.join(os.tmpdir(), 'mila-downloads-'));
  fs.writeFileSync(path.join(downloadsDir, 'app-release.apk'), 'apk-bytes');

  await withServer(
    {config: {downloadsDir}},
    async (baseUrl) => {
      const response = await fetch(`${baseUrl}/downloads/app-release.apk`);
      assert.equal(response.status, 200);
      assert.equal(
        response.headers.get('content-type'),
        'application/vnd.android.package-archive',
      );
      assert.equal(await response.text(), 'apk-bytes');

      const traversal = await fetch(`${baseUrl}/downloads/../server.mjs`);
      assert.equal(traversal.status, 404);
    },
  );
});

test('connection page creates a code and exchanges it for a token', async () => {
  await withServer({config: {enableOpenAiAccount: true}}, async (baseUrl) => {
    const page = await fetch(`${baseUrl}/auth/openai/start`, {
      method: 'POST',
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: new URLSearchParams({label: 'user@example.com'}),
    });
    assert.equal(page.status, 200);
    const html = await page.text();
    const code = html.match(/[A-F0-9]{8}/)?.[0];
    assert.ok(code);

    const exchange = await fetch(`${baseUrl}/auth/openai/device`, {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({code}),
    });
    assert.equal(exchange.status, 200);
    const json = await exchange.json();
    assert.equal(json.label, 'user@example.com');
    assert.equal(typeof json.token, 'string');
    assert.ok(json.token.length > 20);
  });
});

test('chat stream requires a MILA session', async () => {
  await withServer({config: {enableOpenAiAccount: true}}, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/chat/stream`, {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({messages: []}),
    });
    assert.equal(response.status, 401);
  });
});

test('OpenAI account flow is disabled by default', async () => {
  await withServer({}, async (baseUrl) => {
    const page = await fetch(`${baseUrl}/auth/openai/start`);
    assert.equal(page.status, 404);

    const stream = await fetch(`${baseUrl}/v1/chat/stream`, {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({messages: []}),
    });
    assert.equal(stream.status, 404);
  });
});

test('voice token is protected and never exposes the Gemini API key', async () => {
  let tokenRequest;
  const fetchImpl = async (url, request) => {
    tokenRequest = {url, request};
    return new Response(
      JSON.stringify({
        name: 'ephemeral-token',
        expireTime: '2026-07-11T12:30:00Z',
        newSessionExpireTime: '2026-07-11T12:01:00Z',
      }),
      {status: 200, headers: {'Content-Type': 'application/json'}},
    );
  };

  await withServer(
    {
      fetchImpl,
      config: {geminiApiKey: 'AIza-server-only', enableOpenAiAccount: true},
    },
    async (baseUrl) => {
      const denied = await fetch(`${baseUrl}/v1/voice/token`, {method: 'POST'});
      assert.equal(denied.status, 401);

      const page = await fetch(`${baseUrl}/auth/openai/start`, {
        method: 'POST',
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: new URLSearchParams({label: 'Voice tester'}),
      });
      const code = (await page.text()).match(/[A-F0-9]{8}/)?.[0];
      const exchange = await fetch(`${baseUrl}/auth/openai/device`, {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({code}),
      });
      const {token: sessionToken} = await exchange.json();

      const response = await fetch(`${baseUrl}/v1/voice/token`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${sessionToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({language: 'uz-UZ'}),
      });
      assert.equal(response.status, 200);
      assert.deepEqual(await response.json(), {
        token: 'ephemeral-token',
        expiresAt: '2026-07-11T12:30:00Z',
        newSessionExpiresAt: '2026-07-11T12:01:00Z',
        language: 'uz-UZ',
      });
    },
  );

  assert.equal(
    tokenRequest.url,
    'https://generativelanguage.googleapis.com/v1alpha/auth_tokens',
  );
  assert.equal(tokenRequest.request.headers['x-goog-api-key'], 'AIza-server-only');
  const body = JSON.parse(tokenRequest.request.body);
  assert.equal(body.uses, 1);
  assert.equal(body.fieldMask, 'model');
  assert.equal(body.bidiGenerateContentSetup.model, 'models/gemini-3.1-flash-live-preview');
});

test('LiveKit token uses the paired account and a private one-time room', async () => {
  await withServer(
    {
      config: {
        adminToken: 'admin-secret',
        livekitUrl: 'wss://voice.example.test/rtc',
        livekitApiKey: 'livekit-key',
        livekitApiSecret: 'livekit-secret-with-enough-entropy',
      },
    },
    async (baseUrl) => {
      const denied = await fetch(`${baseUrl}/v1/voice/livekit-token`, {
        method: 'POST',
      });
      assert.equal(denied.status, 401);

      const session = await connectMobile(baseUrl, 'creator@example.test', {
        id: 'creator',
        email: 'creator@example.test',
        name: 'Creator',
        role: 'Creator',
      });
      const response = await fetch(`${baseUrl}/v1/voice/livekit-token`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${session.token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          language: 'uz-UZ',
          profile: {
            voiceName: 'Sulafat',
            additionalInstructions: 'Speak warmly.',
            affectiveDialog: true,
            thinkingLevel: 'medium',
            mediaResolution: 'high',
            style: 'assistant',
            pace: 'medium',
            delivery: 'natural',
            listeningProfile: 'balanced',
            responseLength: 'brief',
            transport: 'direct',
            persona: '',
            voiceDirection: '',
            proactiveAudio: true,
            userName: '',
            contextTriggerTokens: 90000,
            contextTargetTokens: 70000,
            functionCalling: false,
          },
        }),
      });
      assert.equal(response.status, 201);
      const payload = await response.json();
      assert.equal(payload.server_url, 'wss://voice.example.test/rtc');
      assert.match(payload.room_name, /^mila-[0-9a-f-]{36}$/);
      assert.equal(payload.language, 'uz-UZ');

      const claims = await new TokenVerifier(
        'livekit-key',
        'livekit-secret-with-enough-entropy',
      ).verify(payload.participant_token);
      assert.equal(claims.name, 'Creator');
      assert.equal(claims.video.roomJoin, true);
      assert.equal(claims.video.room, payload.room_name);
      assert.equal(claims.video.canPublish, true);
      assert.equal(claims.video.canSubscribe, true);
      assert.equal(
        JSON.parse(claims.metadata).owner.email,
        'creator@example.test',
      );
      assert.deepEqual(JSON.parse(claims.roomConfig.metadata), {
        language: 'uz-UZ',
        owner: { id: 'creator', email: 'creator@example.test', name: 'Creator', role: 'Creator' },
        profile: {
          voiceName: 'Sulafat',
          additionalInstructions: 'Speak warmly.',
          style: 'assistant',
          pace: 'medium',
          delivery: 'natural',
          listeningProfile: 'balanced',
          responseLength: 'brief',
          transport: 'direct',
          persona: '',
          voiceDirection: '',
          affectiveDialog: true,
          proactiveAudio: true,
          userName: '',
          thinkingLevel: 'medium',
          mediaResolution: 'high',
          contextTriggerTokens: 90000,
          contextTargetTokens: 70000,
          functionCalling: false,
        },
        source: 'agentic-os',
      });
    },
  );
});

test('Live profile rejects unknown values and keeps context compression valid', () => {
  assert.deepEqual(normalizeLiveProfile({
    voiceName: 'unknown',
    thinkingLevel: 'extreme',
    mediaResolution: 'huge',
    contextTriggerTokens: 100,
    contextTargetTokens: 999999,
  }), {
    voiceName: 'Leda',
    additionalInstructions: '',
    style: 'assistant',
    pace: 'medium',
    delivery: 'natural',
    listeningProfile: 'balanced',
    responseLength: 'brief',
    transport: 'direct',
    persona: '',
    voiceDirection: '',
    affectiveDialog: true,
    proactiveAudio: true,
    userName: '',
    thinkingLevel: 'low',
    mediaResolution: 'low',
    contextTriggerTokens: 65536,
    contextTargetTokens: 57344,
    functionCalling: true,
  });
});

test('chat stream proxies OpenAI SSE after connection', async () => {
  let upstreamBody = '';
  const encoder = new TextEncoder();
  const fetchImpl = async (_url, request) => {
    upstreamBody = request.body;
    return new Response(
      new ReadableStream({
        start(controller) {
          controller.enqueue(
            encoder.encode(
              'data: {"choices":[{"delta":{"content":"Hello"}}]}\n\n',
            ),
          );
          controller.enqueue(encoder.encode('data: [DONE]\n\n'));
          controller.close();
        },
      }),
      {
        status: 200,
        headers: {'Content-Type': 'text/event-stream'},
      },
    );
  };

  await withServer(
    {
      fetchImpl,
      config: {
        openAiApiKey: 'sk-test',
        defaultModel: 'gpt-test',
        enableOpenAiAccount: true,
      },
    },
    async (baseUrl) => {
      const page = await fetch(`${baseUrl}/auth/openai/start`, {
        method: 'POST',
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: new URLSearchParams({label: 'Tester'}),
      });
      const code = (await page.text()).match(/[A-F0-9]{8}/)?.[0];
      const exchange = await fetch(`${baseUrl}/auth/openai/device`, {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({code}),
      });
      const {token} = await exchange.json();

      const stream = await fetch(`${baseUrl}/v1/chat/stream`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: 'gpt-test',
          systemPrompt: 'Be concise.',
          messages: [{role: 'user', content: 'Hi'}],
        }),
      });

      assert.equal(stream.status, 200);
      assert.match(await stream.text(), /Hello/);
      assert.match(upstreamBody, /Be concise/);
      assert.match(upstreamBody, /"role":"user"/);
    },
  );
});

test('chat stream can require an active subscription', async () => {
  await withServer(
    {
      config: {
        openAiApiKey: 'sk-test',
        requireActiveSubscription: true,
        enableOpenAiAccount: true,
      },
    },
    async (baseUrl) => {
      const page = await fetch(`${baseUrl}/auth/openai/start`, {
        method: 'POST',
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: new URLSearchParams({label: 'no-sub@example.com'}),
      });
      const code = (await page.text()).match(/[A-F0-9]{8}/)?.[0];
      const exchange = await fetch(`${baseUrl}/auth/openai/device`, {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({code}),
      });
      const {token} = await exchange.json();

      const stream = await fetch(`${baseUrl}/v1/chat/stream`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({messages: []}),
      });

      assert.equal(stream.status, 402);
    },
  );
});
