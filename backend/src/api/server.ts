import Fastify from "fastify";
import { createHash } from "node:crypto";
import { pool } from "../db.js";
import { ApiError, BountyService } from "../modules/bounties/service.js";
import { CountingService } from "../modules/counting/service.js";
import { TreasuryService } from "../modules/treasury/service.js";
import { IdentityService } from "../modules/identity/service.js";
import { listWire } from "../modules/notify/service.js";
import type { StripeGateway } from "../gateways/stripe.js";
import type { TikTokClient } from "../gateways/tiktok.js";
import { withIdempotency } from "./idempotency.js";

export interface Deps {
  stripe: StripeGateway;
  tiktok: TikTokClient;
}

export function buildServer(deps: Deps) {
  const identity = new IdentityService(deps.tiktok);
  const bounties = new BountyService(deps.stripe, deps.tiktok);
  const counting = new CountingService(deps.tiktok, bounties);
  const treasury = new TreasuryService(deps.stripe);

  const app = Fastify({ logger: process.env.NODE_ENV !== "test" });

  app.setErrorHandler((err, _req, reply) => {
    if (err instanceof ApiError)
      return reply.code(err.status).send({ error: err.code, message: err.message });
    app.log.error(err);
    return reply.code(500).send({ error: "internal", message: "something broke" });
  });

  const auth = (req: { headers: Record<string, unknown> }) =>
    identity.authenticate(req.headers.authorization as string | undefined);

  // -- identity --------------------------------------------------------------

  app.post("/v1/auth/tiktok", async (req) => {
    const { code, role } = (req.body ?? {}) as { code?: string; role?: string };
    if (!code) throw new ApiError(422, "code_required", "TikTok OAuth code required");
    return identity.loginWithTikTok(code, role === "artist" ? "artist" : "clipper");
  });

  app.post("/v1/me/push-tokens", async (req) => {
    const me = await auth(req);
    const { token } = (req.body ?? {}) as { token?: string };
    if (!token) throw new ApiError(422, "token_required", "push token required");
    await identity.registerPushToken(me.id, token);
    return { ok: true };
  });

  // -- board (§6) ------------------------------------------------------------

  // The swipe stack: live bounties with open slots, ranked by taste profile —
  // sounds from artists this clipper has worked before rank first, then the
  // freshest purse. Cursor pagination, ETag for cheap refreshes.
  app.get("/v1/board", async (req, reply) => {
    const me = await auth(req);
    const q = req.query as { cursor?: string; limit?: string; sound?: string };
    const limit = Math.min(Number(q.limit ?? 10), 50);
    let cursorCond = "";
    const params: unknown[] = [me.id, limit];
    if (q.cursor) {
      const [ts, id] = Buffer.from(q.cursor, "base64url").toString().split("|");
      params.push(ts, id);
      cursorCond = "and (b.created_at, b.id) < ($3::timestamptz, $4::uuid)";
    }
    let soundCond = "";
    if (q.sound) {
      params.push(q.sound);
      soundCond = `and snd.tiktok_music_id = $${params.length}`;
    }
    const { rows } = await pool.query(
      `select b.id, b.serial, b.title, b.brief, b.payout_model, b.rate_cents, b.rate_unit,
              b.purse_cents, b.slot_cap, b.window_days, b.platform, b.deadline_at, b.created_at,
              snd.title as sound_title, snd.tiktok_music_id,
              (select count(*)::int from claim cl where cl.bounty_id = b.id and cl.state in ('open','submitted')) as claimed_slots,
              exists (select 1 from claim cl2 join bounty b2 on b2.id = cl2.bounty_id
                      where cl2.account_id = $1 and b2.artist_account_id = b.artist_account_id) as worked_before
       from bounty b
       join sound snd on snd.id = b.sound_id
       where b.state = 'live' and b.deadline_at > now()
         and (select count(*) from claim cl where cl.bounty_id = b.id and cl.state in ('open','submitted')) < b.slot_cap
         ${cursorCond} ${soundCond}
       order by worked_before desc, b.created_at desc, b.id desc
       limit $2`,
      params,
    );
    const last = rows[rows.length - 1];
    const nextCursor = rows.length === limit && last
      ? Buffer.from(`${new Date(last.created_at).toISOString()}|${last.id}`).toString("base64url")
      : null;

    const etag = `"${createHash("sha1").update(JSON.stringify(rows.map((r) => [r.id, r.claimed_slots]))).digest("hex")}"`;
    if (req.headers["if-none-match"] === etag) return reply.code(304).send();
    reply.header("etag", etag);
    return { bounties: rows, nextCursor };
  });

  // Details, terms, and the captured-clips panel in one payload.
  app.get("/v1/bounties/:id", async (req) => {
    await auth(req);
    const { id } = req.params as { id: string };
    const { rows: [b] } = await pool.query(
      `select b.*, snd.title as sound_title, snd.tiktok_music_id,
              (select count(*)::int from claim cl where cl.bounty_id = b.id and cl.state in ('open','submitted')) as claimed_slots
       from bounty b join sound snd on snd.id = b.sound_id where b.id = $1`,
      [id],
    );
    if (!b) throw new ApiError(404, "not_found", "bounty not found");
    const { rows: captured } = await pool.query(
      `select s.id, s.tiktok_video_id, a.handle,
              coalesce((select max(view_count) from view_sample vs where vs.submission_id = s.id), 0) as views,
              s.accrued_cents, s.state
       from submission s
       join claim cl on cl.id = s.claim_id
       join account a on a.id = cl.account_id
       where cl.bounty_id = $1 and s.state in ('counting','payable','paid')
       order by s.accrued_cents desc limit 12`,
      [id],
    );
    return { bounty: b, captured };
  });

  // -- claims ----------------------------------------------------------------

  app.post("/v1/bounties/:id/claims", async (req, reply) => {
    const me = await auth(req);
    const { id } = req.params as { id: string };
    await withIdempotency(req, reply, me.id, async () => ({
      status: 201,
      body: { claim: await bounties.claim(me.id, id) },
    }));
  });

  app.patch("/v1/claims/:id", async (req) => {
    const me = await auth(req);
    const { id } = req.params as { id: string };
    const { checklist } = (req.body ?? {}) as { checklist?: unknown };
    return { claim: await bounties.patchChecklist(me.id, id, checklist) };
  });

  app.post("/v1/claims/:id/submission", async (req, reply) => {
    const me = await auth(req);
    const { id } = req.params as { id: string };
    const { tiktokVideoId } = (req.body ?? {}) as { tiktokVideoId?: string };
    if (!tiktokVideoId) throw new ApiError(422, "video_required", "tiktokVideoId required");
    await withIdempotency(req, reply, me.id, async () => {
      const out = await bounties.createSubmission(me.id, id, tiktokVideoId);
      return { status: out.submission.state === "rejected" ? 422 : 201, body: out };
    });
  });

  // -- purse / payouts -------------------------------------------------------

  app.get("/v1/me/purse", async (req) => {
    const me = await auth(req);
    return treasury.purse(me.id);
  });

  app.post("/v1/me/payouts", async (req, reply) => {
    const me = await auth(req);
    // Cash out requires a fresh device-attested assertion (App Attest on iOS,
    // surfaced to the user as Face ID). Verification is stubbed to presence.
    const attestation = req.headers["x-device-attestation"];
    if (typeof attestation !== "string" || attestation.length < 8)
      throw new ApiError(403, "attestation_required", "fresh device attestation required");
    const { amountCents } = (req.body ?? {}) as { amountCents?: number };
    if (!amountCents) throw new ApiError(422, "amount_required", "amountCents required");
    await withIdempotency(req, reply, me.id, async () => ({
      status: 201,
      body: await treasury.createPayout(me.id, amountCents),
    }));
  });

  // Clipper's desk: open claim (with checklist) + everything under review.
  app.get("/v1/me/claims", async (req) => {
    const me = await auth(req);
    const { rows } = await pool.query(
      `select cl.id, cl.state, cl.checklist, cl.claimed_at, cl.expires_at,
              b.id as bounty_id, b.serial, b.title, b.rate_cents, b.rate_unit, b.payout_model,
              s.id as submission_id, s.state as submission_state, s.accrued_cents, s.posted_at,
              d.id as dispute_id, d.state as dispute_state, d.reason_code
       from claim cl
       join bounty b on b.id = cl.bounty_id
       left join submission s on s.claim_id = cl.id
       left join dispute d on d.submission_id = s.id and d.state <> 'resolved'
       where cl.account_id = $1
       order by cl.claimed_at desc limit 50`,
      [me.id],
    );
    return { claims: rows };
  });

  app.get("/v1/me/wire", async (req) => {
    const me = await auth(req);
    return { items: await listWire(pool, me.id) };
  });

  // -- artist ----------------------------------------------------------------

  app.post("/v1/bounties", async (req, reply) => {
    const me = await auth(req);
    if (me.suspended_at)
      throw new ApiError(403, "suspended", "posting is paused until the balance clears"); // §8 Q4
    const b = (req.body ?? {}) as Record<string, unknown>;
    for (const k of ["soundId", "title", "payoutModel", "rateCents", "purseCents", "deadlineAt"])
      if (b[k] === undefined) throw new ApiError(422, "missing_field", `${k} required`);
    await withIdempotency(req, reply, me.id, async () => ({
      status: 201,
      body: await bounties.createDraft(me.id, {
        soundId: String(b.soundId),
        title: String(b.title),
        brief: String(b.brief ?? ""),
        payoutModel: b.payoutModel === "per_clip" ? "per_clip" : "per_view",
        rateCents: Number(b.rateCents),
        rateUnit: Number(b.rateUnit ?? 1),
        purseCents: Number(b.purseCents),
        slotCap: Number(b.slotCap ?? 12),
        deadlineAt: new Date(String(b.deadlineAt)),
        platform: b.platform ? String(b.platform) : undefined,
      }),
    }));
  });

  app.post("/v1/bounties/:id/topups", async (req, reply) => {
    const me = await auth(req);
    const { id } = req.params as { id: string };
    const { amountCents } = (req.body ?? {}) as { amountCents?: number };
    if (!amountCents) throw new ApiError(422, "amount_required", "amountCents required");
    await withIdempotency(req, reply, me.id, async () => ({
      status: 201,
      body: await bounties.createTopUp(me.id, id, amountCents),
    }));
  });

  // Artist review feed: pending submissions across the artist's bounties.
  app.get("/v1/me/review", async (req) => {
    const me = await auth(req);
    const { rows } = await pool.query(
      `select s.id, s.state, s.accrued_cents, s.tiktok_video_id, s.posted_at,
              a.handle, b.title as bounty_title, b.serial, b.id as bounty_id,
              coalesce((select max(view_count) from view_sample vs where vs.submission_id = s.id), 0) as views
       from submission s
       join claim cl on cl.id = s.claim_id
       join account a on a.id = cl.account_id
       join bounty b on b.id = cl.bounty_id
       where b.artist_account_id = $1 and s.state in ('counting','payable','held','paid','void')
       order by s.created_at desc limit 100`,
      [me.id],
    );
    return { submissions: rows };
  });

  app.post("/v1/submissions/:id/verdict", async (req, reply) => {
    const me = await auth(req);
    const { id } = req.params as { id: string };
    const { verdict, reason } = (req.body ?? {}) as { verdict?: string; reason?: string };
    if (verdict !== "approve" && verdict !== "dispute")
      throw new ApiError(422, "bad_verdict", "verdict must be approve or dispute");
    await withIdempotency(req, reply, me.id, async () => ({
      status: 200,
      body: await bounties.verdict(me.id, id, verdict, reason),
    }));
  });

  app.post("/v1/disputes/:id/appeal", async (req, reply) => {
    const me = await auth(req);
    const { id } = req.params as { id: string };
    const { statement, evidence } = (req.body ?? {}) as { statement?: string; evidence?: unknown[] };
    if (!statement) throw new ApiError(422, "statement_required", "case statement required");
    await withIdempotency(req, reply, me.id, async () => ({
      status: 201,
      body: await bounties.appeal(me.id, id, statement, evidence ?? []),
    }));
  });

  // -- webhooks --------------------------------------------------------------

  // Signature verification is the Stripe SDK's job in production; the fake
  // gateway has no signatures, so this trusts a shared secret header.
  app.post("/v1/stripe/webhook", async (req) => {
    if (req.headers["x-webhook-secret"] !== (process.env.STRIPE_WEBHOOK_SECRET ?? "whsec_dev"))
      throw new ApiError(401, "bad_signature", "webhook signature check failed");
    const evt = (req.body ?? {}) as {
      type?: string;
      data?: { object?: { id?: string; payment_intent?: string; amount?: number } };
    };
    const obj = evt.data?.object ?? {};
    if (evt.type === "payment_intent.succeeded") {
      const bountyId = await bounties.markFunded(obj.id!, obj.amount!);
      return { handled: true, bountyId };
    }
    if (evt.type === "charge.dispute.created") {
      const out = await treasury.handleChargeback(obj.payment_intent!, obj.amount!);
      return { handled: true, ...out };
    }
    return { handled: false };
  });

  return Object.assign(app, { services: { identity, bounties, counting, treasury } });
}
