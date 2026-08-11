import { pool } from "../../db.js";

// TikTok token store. The live TikTok gateway persists tokens here at OAuth
// time and reads them back (refreshing when stale) for Display API polls.

export interface StoredTokens {
  accessToken: string;
  refreshToken: string | null;
  expiresAt: Date;
}

export async function saveTikTokTokens(
  openId: string,
  t: { accessToken: string; refreshToken?: string | null; expiresInSec: number; scopes?: string[] },
): Promise<void> {
  await pool.query(
    `insert into tiktok_token (tiktok_open_id, access_token, refresh_token, expires_at, scopes)
     values ($1, $2, $3, now() + make_interval(secs => $4), $5)
     on conflict (tiktok_open_id) do update set
       access_token = excluded.access_token,
       refresh_token = coalesce(excluded.refresh_token, tiktok_token.refresh_token),
       expires_at = excluded.expires_at,
       scopes = excluded.scopes,
       updated_at = now()`,
    [openId, t.accessToken, t.refreshToken ?? null, t.expiresInSec, t.scopes ?? []],
  );
}

export async function getTikTokTokens(openId: string): Promise<StoredTokens | null> {
  const { rows: [r] } = await pool.query(
    "select access_token, refresh_token, expires_at from tiktok_token where tiktok_open_id = $1",
    [openId],
  );
  if (!r) return null;
  return { accessToken: r.access_token, refreshToken: r.refresh_token, expiresAt: new Date(r.expires_at) };
}

// -- App Attest key registry -------------------------------------------------

export async function registerAttestKey(accountId: string, keyId: string): Promise<void> {
  await pool.query(
    "insert into attest_key (account_id, key_id) values ($1, $2) on conflict do nothing",
    [accountId, keyId],
  );
}

export async function hasAttestKeys(accountId: string): Promise<boolean> {
  const { rowCount } = await pool.query("select 1 from attest_key where account_id = $1 limit 1", [accountId]);
  return !!rowCount;
}

export async function isRegisteredAttestKey(accountId: string, keyId: string): Promise<boolean> {
  const { rowCount } = await pool.query(
    "select 1 from attest_key where account_id = $1 and key_id = $2", [accountId, keyId]);
  return !!rowCount;
}
