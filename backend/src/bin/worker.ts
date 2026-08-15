import { Sentry, sentryEnabled } from "../observability/instrument.js"; // must come first
import { migrate } from "../db.js";
import { BountyService } from "../modules/bounties/service.js";
import { CountingService } from "../modules/counting/service.js";
import { expireClaims } from "../modules/treasury/service.js";
import { makeGateways } from "../gateways/index.js";

// The background loop: claim expiry every minute, a counting pass every
// minute (each submission carries its own next_poll_at, so the decaying
// cadence emerges from the schedule, not the loop frequency).
await migrate();
const { stripe, tiktok } = makeGateways();
const counting = new CountingService(tiktok, new BountyService(stripe, tiktok));

const tick = async () => {
  try {
    const expired = await expireClaims();
    const polled = await counting.runOnce();
    if (expired || polled.length) console.log(`tick: ${expired} claims expired, ${polled.length} polls`);
  } catch (err) {
    console.error("worker tick failed", err);
    if (sentryEnabled) Sentry.captureException(err);
  }
};
await tick();
setInterval(tick, 60_000);
