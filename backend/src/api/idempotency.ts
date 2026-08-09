import { createHash } from "node:crypto";
import type { FastifyReply, FastifyRequest } from "fastify";
import { pool } from "../db.js";
import { ApiError } from "../modules/bounties/service.js";

// §6 — every mutating call takes an Idempotency-Key. First writer wins the
// key; a retry with the same key and body replays the stored response; the
// same key with a different body is a client bug (422). Claim and payout are
// the calls that will actually be retried.
export async function withIdempotency(
  req: FastifyRequest,
  reply: FastifyReply,
  accountId: string,
  handler: () => Promise<{ status: number; body: unknown }>,
): Promise<void> {
  const key = req.headers["idempotency-key"];
  if (typeof key !== "string" || key.length < 1 || key.length > 200)
    throw new ApiError(400, "idempotency_key_required", "provide an Idempotency-Key header");

  const requestHash = createHash("sha256")
    .update(`${req.method} ${req.url} ${JSON.stringify(req.body ?? null)}`)
    .digest("hex");

  const { rowCount } = await pool.query(
    `insert into idempotency_key (key, account_id, endpoint, request_hash)
     values ($1, $2, $3, $4) on conflict do nothing`,
    [key, accountId, req.routeOptions.url ?? req.url, requestHash],
  );

  if (!rowCount) {
    const { rows: [row] } = await pool.query(
      "select * from idempotency_key where key = $1 and account_id = $2",
      [key, accountId],
    );
    if (row.request_hash !== requestHash)
      throw new ApiError(422, "idempotency_key_reused", "same key, different request");
    if (row.response_status === null)
      throw new ApiError(409, "in_progress", "original request still running");
    reply.code(row.response_status).send(row.response_body);
    return;
  }

  try {
    const { status, body } = await handler();
    await pool.query(
      `update idempotency_key set response_status = $3, response_body = $4
       where key = $1 and account_id = $2`,
      [key, accountId, status, JSON.stringify(body)],
    );
    reply.code(status).send(body);
  } catch (err) {
    // Domain rejections are stable outcomes — replay them too. Unexpected
    // errors release the key so a retry can run fresh.
    if (err instanceof ApiError) {
      const body = { error: err.code, message: err.message };
      await pool.query(
        `update idempotency_key set response_status = $3, response_body = $4
         where key = $1 and account_id = $2`,
        [key, accountId, err.status, JSON.stringify(body)],
      );
      reply.code(err.status).send(body);
      return;
    }
    await pool.query(
      "delete from idempotency_key where key = $1 and account_id = $2 and response_status is null",
      [key, accountId],
    );
    throw err;
  }
}
