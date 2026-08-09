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

// APNs stub — replace with a real provider (token-based APNs) at ship time.
async function sendPush(_accountId: string, _body: string) {}
