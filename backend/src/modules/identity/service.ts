import { randomBytes } from "node:crypto";
import { pool } from "../../db.js";
import type { TikTokClient } from "../../gateways/tiktok.js";
import { ApiError } from "../bounties/service.js";

export class IdentityService {
  constructor(private tiktok: TikTokClient) {}

  // TikTok OAuth code exchange → account upsert → opaque session token.
  async loginWithTikTok(code: string, role: "clipper" | "artist") {
    const { openId, handle } = await this.tiktok.exchangeCode(code);
    const { rows: [account] } = await pool.query(
      `insert into account (tiktok_open_id, handle, roles) values ($1, $2, $3)
       on conflict (tiktok_open_id) do update
         set handle = excluded.handle,
             roles = (select array(select distinct unnest(account.roles || excluded.roles)))
       returning *`,
      [openId, handle, [role]],
    );
    const token = randomBytes(24).toString("hex");
    await pool.query(
      "insert into session (token, account_id, expires_at) values ($1, $2, now() + interval '30 days')",
      [token, account.id],
    );
    return { token, account };
  }

  async authenticate(bearer: string | undefined) {
    if (!bearer?.startsWith("Bearer ")) throw new ApiError(401, "unauthenticated", "missing bearer token");
    const { rows: [row] } = await pool.query(
      `select account.* from session join account on account.id = session.account_id
       where session.token = $1 and session.expires_at > now()`,
      [bearer.slice(7)],
    );
    if (!row) throw new ApiError(401, "unauthenticated", "invalid or expired token");
    return row;
  }

  async registerPushToken(accountId: string, token: string) {
    await pool.query(
      `insert into device_push_token (account_id, token) values ($1, $2) on conflict do nothing`,
      [accountId, token],
    );
  }
}
