import { randomUUID } from "node:crypto";

// Stripe Connect, platform as escrow holder (§4). Real implementation would
// wrap the stripe SDK; everything upstream depends only on this interface.
export interface StripeGateway {
  // Funding a purse: PaymentIntent into the platform account.
  createPaymentIntent(amountCents: number, meta: Record<string, string>): Promise<{
    id: string;
    clientSecret: string;
  }>;
  // Payouts: Transfer to the clipper's connected account.
  createTransfer(amountCents: number, connectedAccountId: string, meta: Record<string, string>): Promise<{ id: string }>;
  // Refund of the unspent purse to the original payment method.
  createRefund(paymentIntentId: string, amountCents: number): Promise<{ id: string }>;
}

export class FakeStripe implements StripeGateway {
  intents: { id: string; amountCents: number; meta: Record<string, string> }[] = [];
  transfers: { id: string; amountCents: number; connectedAccountId: string }[] = [];
  refunds: { id: string; paymentIntentId: string; amountCents: number }[] = [];

  async createPaymentIntent(amountCents: number, meta: Record<string, string>) {
    const id = `pi_${randomUUID().slice(0, 8)}`;
    this.intents.push({ id, amountCents, meta });
    return { id, clientSecret: `${id}_secret_test` };
  }
  async createTransfer(amountCents: number, connectedAccountId: string) {
    const id = `tr_${randomUUID().slice(0, 8)}`;
    this.transfers.push({ id, amountCents, connectedAccountId });
    return { id };
  }
  async createRefund(paymentIntentId: string, amountCents: number) {
    const id = `re_${randomUUID().slice(0, 8)}`;
    this.refunds.push({ id, paymentIntentId, amountCents });
    return { id };
  }
}
