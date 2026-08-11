import type { Queryable } from "../../db.js";

// The in-app wire. APNs delivery hangs off the same write; the push transport
// is a stub until the app ships.
export async function pushWire(
  db: Queryable, accountId: string, body: string, tone: "money" | "warn" | "info" = "info",
) {
  await db.query(
    "insert into wire_item (account_id, body, tone) values ($1,$2,$3)", [accountId, body, tone],
  );
  await sendPush(accountId, body);
}

export async function listWire(db: Queryable, accountId: string, limit = 50) {
  const { rows } = await db.query(
    `select id, body, tone, read_at, created_at from wire_item
     where account_id = $1 order by created_at desc limit $2`, [accountId, limit]);
  return rows;
}

// Fan the wire item out to the account's registered devices. Silent no-op
// until APNS_KEY_P8/APNS_KEY_ID/APNS_TEAM_ID are configured.
async function sendPush(accountId: string, body: string) {
  const { apnsConfigured, sendApnsAlert } = await import("./apns.js");
  if (!apnsConfigured()) return;
  const { pool } = await import("../../db.js");
  const { rows } = await pool.query(
    "select token from device_push_token where account_id = $1", [accountId]);
  await Promise.allSettled(rows.map((r) => sendApnsAlert(r.token, body)));
}
