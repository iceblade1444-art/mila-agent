import fs from 'node:fs';
import path from 'node:path';
import {DatabaseSync} from 'node:sqlite';

export function createAppDb(dbPath = path.join('data', 'mila.db')) {
  if (dbPath !== ':memory:') {
    fs.mkdirSync(path.dirname(dbPath), {recursive: true});
  }
  const db = new DatabaseSync(dbPath);
  db.exec(`
    PRAGMA journal_mode = WAL;
    CREATE TABLE IF NOT EXISTS connection_codes (
      code TEXT PRIMARY KEY,
      label TEXT NOT NULL,
      owner_json TEXT,
      expires_at INTEGER NOT NULL,
      created_at INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS sessions (
      token_hash TEXT PRIMARY KEY,
      session_id TEXT,
      label TEXT NOT NULL,
      owner_json TEXT,
      created_at INTEGER NOT NULL,
      revoked_at INTEGER
    );
    CREATE TABLE IF NOT EXISTS app_updates (
      platform TEXT PRIMARY KEY,
      latest_version TEXT NOT NULL,
      latest_code INTEGER NOT NULL,
      min_supported_version TEXT NOT NULL,
      min_supported_code INTEGER NOT NULL,
      apk_url TEXT NOT NULL,
      notes TEXT NOT NULL,
      updated_at INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS subscriptions (
      label TEXT PRIMARY KEY,
      plan TEXT NOT NULL,
      active_until INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
  `);
  try {
    db.exec('ALTER TABLE sessions ADD COLUMN session_id TEXT');
  } catch (error) {
    if (!String(error.message).includes('duplicate column name')) throw error;
  }
  for (const table of ['connection_codes', 'sessions']) {
    try {
      db.exec(`ALTER TABLE ${table} ADD COLUMN owner_json TEXT`);
    } catch (error) {
      if (!String(error.message).includes('duplicate column name')) throw error;
    }
  }
  db.exec(`
    UPDATE sessions
    SET session_id = lower(hex(randomblob(16)))
    WHERE session_id IS NULL OR session_id = '';
    CREATE UNIQUE INDEX IF NOT EXISTS sessions_session_id_idx ON sessions(session_id);
  `);

  const statements = {
    insertCode: db.prepare(`
      INSERT OR REPLACE INTO connection_codes
      (code, label, owner_json, expires_at, created_at) VALUES (?, ?, ?, ?, ?)
    `),
    getCode: db.prepare(`
      SELECT code, label, owner_json AS ownerJson, expires_at AS expiresAt
      FROM connection_codes WHERE code = ?
    `),
    deleteCode: db.prepare('DELETE FROM connection_codes WHERE code = ?'),
    deleteExpiredCodes: db.prepare(
      'DELETE FROM connection_codes WHERE expires_at < ?',
    ),
    insertSession: db.prepare(`
      INSERT INTO sessions (token_hash, session_id, label, owner_json, created_at)
      VALUES (?, ?, ?, ?, ?)
    `),
    getSession: db.prepare(`
      SELECT token_hash AS tokenHash, label, owner_json AS ownerJson, created_at AS createdAt
      FROM sessions WHERE token_hash = ? AND revoked_at IS NULL
    `),
    listSessions: db.prepare(`
      SELECT session_id AS id, label, owner_json AS ownerJson, created_at AS createdAt, revoked_at AS revokedAt
      FROM sessions ORDER BY created_at DESC LIMIT 100
    `),
    revokeSession: db.prepare(`
      UPDATE sessions SET revoked_at = ?
      WHERE session_id = ? AND revoked_at IS NULL
    `),
    getUpdate: db.prepare(`
      SELECT
        platform,
        latest_version AS latestVersion,
        latest_code AS latestCode,
        min_supported_version AS minSupportedVersion,
        min_supported_code AS minSupportedCode,
        apk_url AS apkUrl,
        notes,
        updated_at AS updatedAt
      FROM app_updates WHERE platform = ?
    `),
    upsertUpdate: db.prepare(`
      INSERT INTO app_updates (
        platform,
        latest_version,
        latest_code,
        min_supported_version,
        min_supported_code,
        apk_url,
        notes,
        updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(platform) DO UPDATE SET
        latest_version = excluded.latest_version,
        latest_code = excluded.latest_code,
        min_supported_version = excluded.min_supported_version,
        min_supported_code = excluded.min_supported_code,
        apk_url = excluded.apk_url,
        notes = excluded.notes,
        updated_at = excluded.updated_at
    `),
    getSubscription: db.prepare(`
      SELECT label, plan, active_until AS activeUntil, updated_at AS updatedAt
      FROM subscriptions WHERE label = ?
    `),
    upsertSubscription: db.prepare(`
      INSERT INTO subscriptions (label, plan, active_until, updated_at)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(label) DO UPDATE SET
        plan = excluded.plan,
        active_until = excluded.active_until,
        updated_at = excluded.updated_at
    `),
  };

  return {
    raw: db,
    close: () => db.close(),
    createCode(code, label, ownerJson, expiresAt) {
      statements.insertCode.run(code, label, ownerJson || null, expiresAt, Date.now());
    },
    getCode(code) {
      statements.deleteExpiredCodes.run(Date.now());
      return statements.getCode.get(code);
    },
    deleteCode(code) {
      statements.deleteCode.run(code);
    },
    createSession(tokenHash, label, sessionId, ownerJson) {
      statements.insertSession.run(tokenHash, sessionId, label, ownerJson || null, Date.now());
    },
    getSession(tokenHash) {
      return statements.getSession.get(tokenHash);
    },
    listSessions() {
      return statements.listSessions.all().map((session) => ({
        ...session,
        active: session.revokedAt == null,
      }));
    },
    revokeSession(sessionId) {
      return statements.revokeSession.run(Date.now(), sessionId).changes > 0;
    },
    getUpdate(platform) {
      return statements.getUpdate.get(platform);
    },
    upsertUpdate(update) {
      statements.upsertUpdate.run(
        update.platform,
        update.latestVersion,
        update.latestCode,
        update.minSupportedVersion,
        update.minSupportedCode,
        update.apkUrl,
        update.notes,
        Date.now(),
      );
    },
    getSubscription(label) {
      return statements.getSubscription.get(label);
    },
    upsertSubscription(subscription) {
      statements.upsertSubscription.run(
        subscription.label,
        subscription.plan,
        subscription.activeUntil,
        Date.now(),
      );
    },
  };
}
