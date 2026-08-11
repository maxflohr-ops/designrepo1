import type { StripeGateway } from "./stripe.js";

// Production Stripe Connect gateway over Stripe's REST API (form-encoded,
// fetch-based — no SDK dependency). The platform account holds escrow (§4):
// PaymentIntents fund purses, Transfers pay clippers' connected accounts,
// Refunds return unspent purses.
//
// Env: STRIPE_SECRET_KEY (sk_live_… / sk_test_…).
// Webhooks: point Stripe at POST /v1/stripe/webhook for
// payment_intent.succeeded and charge.dispute.created. Verify signatures
// with STRIPE_WEBHOOK_SECRET before this ships (see api/server.ts).
export class LiveStripe implements StripeGateway {
  constructor(private secretKey = process.env.STRIPE_SECRET_KEY ?? "") {
    if (!this.secretKey) throw new Error("STRIPE_SECRET_KEY is not set");
  }

  private async call(path: string, params: Record<string, string>): Promise<Record<string, unknown>> {
    const res = await fetch(`https://api.stripe.com/v1/${path}`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${this.secretKey}`,
        "content-type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams(params).toString(),
    });
    const body = (await res.json()) as Record<string, unknown>;
    if (!res.ok) {
      const err = (body.error ?? {}) as { message?: string; type?: string };
      throw new Error(`stripe ${path}: ${err.type ?? res.status} — ${err.message ?? "unknown error"}`);
    }
    return body;
  }

  async createPaymentIntent(amountCents: number, meta: Record<string, string>) {
    const pi = await this.call("payment_intents", {
      amount: String(amountCents),
      currency: "usd",
      "automatic_payment_methods[enabled]": "true",
      ...Object.fromEntries(Object.entries(meta).map(([k, v]) => [`metadata[${k}]`, v])),
    });
    return { id: pi.id as string, clientSecret: pi.client_secret as string };
  }

  async createTransfer(amountCents: number, connectedAccountId: string, meta: Record<string, string>) {
    const tr = await this.call("transfers", {
      amount: String(amountCents),
      currency: "usd",
      destination: connectedAccountId,
      ...Object.fromEntries(Object.entries(meta).map(([k, v]) => [`metadata[${k}]`, v])),
    });
    return { id: tr.id as string };
  }

  async createRefund(paymentIntentId: string, amountCents: number) {
    const re = await this.call("refunds", {
      payment_intent: paymentIntentId,
      amount: String(amountCents),
    });
    return { id: re.id as string };
  }
}
