import { FakeStripe } from "./stripe.js";
import { StubTikTok } from "./tiktok.js";
import { LiveStripe } from "./stripeLive.js";
import { LiveTikTok } from "./tiktokLive.js";
import type { StripeGateway } from "./stripe.js";
import type { TikTokClient } from "./tiktok.js";

// GATEWAYS=live flips both external services to production implementations;
// anything else (default) runs the fakes so dev and CI never touch the network.
export function makeGateways(): { stripe: StripeGateway; tiktok: TikTokClient } {
  if (process.env.GATEWAYS === "live") {
    return { stripe: new LiveStripe(), tiktok: new LiveTikTok() };
  }
  return { stripe: new FakeStripe(), tiktok: new StubTikTok() };
}
