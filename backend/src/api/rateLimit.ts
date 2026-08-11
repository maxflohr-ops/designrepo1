import { redis } from "../redis.js";
import { ApiError } from "../modules/bounties/service.js";

// Fixed-window counter in Redis. Throws 429 when the window's budget is
// spent. Buckets: auth (per IP), claim (per account).
export async function rateLimit(
  bucket: string,
  id: string,
  limit: number,
  windowSec: number,
): Promise<void> {
  const windowStart = Math.floor(Date.now() / 1000 / windowSec);
  const key = `rate:${bucket}:${id}:${windowStart}`;
  const n = await redis.incr(key);
  if (n === 1) await redis.expire(key, windowSec + 1);
  if (n > limit)
    throw new ApiError(429, "rate_limited", `too many ${bucket} requests; retry shortly`);
}
