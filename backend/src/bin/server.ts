import { buildServer } from "../api/server.js";
import { migrate } from "../db.js";
import { config } from "../config.js";
import { FakeStripe } from "../gateways/stripe.js";
import { StubTikTok } from "../gateways/tiktok.js";

// Dev entrypoint: fake Stripe, stub TikTok. Swap both for real gateways at
// ship time — nothing above the gateway interfaces changes.
await migrate();
const app = buildServer({ stripe: new FakeStripe(), tiktok: new StubTikTok() });
await app.listen({ port: config.port, host: "0.0.0.0" });
console.log(`bounty sounds backend on :${config.port}`);
