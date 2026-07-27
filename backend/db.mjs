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
      account_grant TEXT,
      expires_at INTEGER NOT NULL,
      created_at INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS sessions (
      token_hash TEXT PRIMARY KEY,
      session_id TEXT,
      label TEXT NOT NULL,
      owner_json TEXT,
      created_at INTEGER NOT NULL,
      expires_at INTEGER NOT NULL,
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
  try {
    db.exec('ALTER TABLE connection_codes ADD COLUMN account_grant TEXT');
  } catch (error) {
    if (!String(error.message).includes('duplicate column name')) throw error;
  }
  try {
    db.exec('ALTER TABLE sessions ADD COLUMN expires_at INTEGER');
  } catch (error) {
    if (!String(error.message).includes('duplicate column name')) throw error;
  }
  db.exec(`
    UPDATE sessions
    SET session_id = lower(hex(randomblob(16)))
    WHERE session_id IS NULL OR session_id = '';
    UPDATE sessions
    SET expires_at = created_at + ${30 * 24 * 60 * 60 * 1000}
    WHERE expires_at IS NULL OR expires_at = 0;
    CREATE UNIQUE INDEX IF NOT EXISTS sessions_session_id_idx ON sessions(session_id);
  `);

  const statements = {
    insertCode: db.prepare(`
      INSERT OR REPLACE INTO connection_codes
      (code, label, owner_json, account_grant, expires_at, created_at)
      VALUES (?, ?, ?, ?, ?, ?)
    `),
    getCode: db.prepare(`
      SELECT code, label, owner_json AS ownerJson,
        account_grant AS accountGrant, expires_at AS expiresAt
      FROM connection_codes WHERE code = ?
    `),
    deleteCode: db.prepare('DELETE FROM connection_codes WHERE code = ?'),
    deleteExpiredCodes: db.prepare(
      'DELETE FROM connection_codes WHERE expires_at < ?',
    ),
    insertSession: db.prepare(`
      INSERT INTO sessions
        (token_hash, session_id, label, owner_json, created_at, expires_at)
      VALUES (?, ?, ?, ?, ?, ?)
    `),
    getSession: db.prepare(`
      SELECT token_hash AS tokenHash, label, owner_json AS ownerJson,
        created_at AS createdAt, expires_at AS expiresAt
      FROM sessions
      WHERE token_hash = ? AND revoked_at IS NULL AND expires_at > ?
    `),
    listSessions: db.prepare(`
      SELECT session_id AS id, label, owner_json AS ownerJson,
        created_at AS createdAt, expires_at AS expiresAt, revoked_at AS revokedAt
      FROM sessions ORDER BY created_at DESC LIMIT 100
    `),
    pruneSessions: db.prepare(`
      DELETE FROM sessions
      WHERE expires_at <= ? OR (revoked_at IS NOT NULL AND revoked_at <= ?)
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
    createCode(code, label, ownerJson, accountGrant, expiresAt) {
      statements.insertCode.run(
        code,
        label,
        ownerJson || null,
        accountGrant || null,
        expiresAt,
        Date.now(),
      );
    },
    getCode(code) {
      statements.deleteExpiredCodes.run(Date.now());
      return statements.getCode.get(code);
    },
    deleteCode(code) {
      statements.deleteCode.run(code);
    },
    createSession(tokenHash, label, sessionId, ownerJson, expiresAt) {
      const now = Date.now();
      statements.pruneSessions.run(now, now - 7 * 24 * 60 * 60 * 1000);
      statements.insertSession.run(
        tokenHash,
        sessionId,
        label,
        ownerJson || null,
        now,
        expiresAt,
      );
    },
    getSession(tokenHash) {
      const now = Date.now();
      statements.pruneSessions.run(now, now - 7 * 24 * 60 * 60 * 1000);
      return statements.getSession.get(tokenHash, now);
    },
    listSessions() {
      const now = Date.now();
      statements.pruneSessions.run(now, now - 7 * 24 * 60 * 60 * 1000);
      return statements.listSessions.all().map((session) => ({
        ...session,
        active: session.revokedAt == null && session.expiresAt > now,
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
