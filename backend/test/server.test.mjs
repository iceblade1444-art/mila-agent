import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {test} from 'node:test';

import {createMilaServer} from '../server.mjs';

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
      const {code} = await issued.json();
      assert.match(code, /^[A-F0-9]{8}$/);

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
        headers: {Authorization: `Bearer ${sessionToken}`},
      });
      assert.equal(response.status, 200);
      assert.deepEqual(await response.json(), {
        token: 'ephemeral-token',
        expiresAt: '2026-07-11T12:30:00Z',
        newSessionExpiresAt: '2026-07-11T12:01:00Z',
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
