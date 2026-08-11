import { pool, withTxn } from "../../db.js";
import { config } from "../../config.js";
import { transition } from "../../domain/states.js";
import { balance, cashOut, recordChargeback, refs, refundArtist } from "../../domain/ledger.js";
import type { StripeGateway } from "../../gateways/stripe.js";
import { ApiError } from "../bounties/service.js";
import { pushWire } from "../notify/service.js";
import { emitOpsEvent } from "../notify/ops.js";

export class TreasuryService {
  constructor(private stripe: StripeGateway) {}

  // GET /v1/me/purse — payable, pending, lifetime, and the ledger feed.
  async purse(accountId: string) {
    const payable = await balance(pool, refs.payable(accountId));
    const { rows: [agg] } = await pool.query(
      `select
         (coalesce(sum(le.amount_cents) filter (
           where le.direction = 'credit' and le.account_ref like 'held:%' ), 0)
         - coalesce(sum(le.amount_cents) filter (
           where le.direction = 'debit' and le.account_ref like 'held:%' ), 0))::bigint as pending,
         coalesce(sum(le.amount_cents) filter (
           where le.kind = 'payout_clear' and le.account_ref = $2 and le.direction = 'credit'), 0)::bigint as lifetime
       from ledger_entry le
       left join submission s on s.id = le.submission_id
       left join claim cl on cl.id = s.claim_id
       where cl.account_id = $1 or le.account_ref = $2`,
      [accountId, refs.payable(accountId)],
    );
    const { rows: feed } = await pool.query(
      `select le.kind, le.direction, le.amount_cents, le.created_at, le.bounty_id, le.submission_id,
              b.title as bounty_title, s.state as submission_state
       from ledger_entry le
       left join bounty b on b.id = le.bounty_id
       left join submission s on s.id = le.submission_id
       where le.account_ref in ($1, $2)
          or (le.account_ref like 'held%' and le.submission_id in
                (select s2.id from submission s2 join claim c2 on c2.id = s2.claim_id where c2.account_id = $3))
       order by le.created_at desc, le.id desc limit 60`,
      [refs.payable(accountId), refs.externalClipper(accountId), accountId],
    );
    return {
      payableCents: payable,
      pendingCents: Number(agg.pending),
      lifetimeCents: Number(agg.lifetime),
      feed,
    };
  }

  // POST /v1/me/payouts — cash out. Device attestation is checked by the
  // route; this enforces balance and the §7 new-account hold.
  async createPayout(accountId: string, amountCents: number) {
    return withTxn(async (c) => {
      await c.query("select pg_advisory_xact_lock(hashtext($1))", [`payout:${accountId}`]);
      const payable = await balance(c, refs.payable(accountId));
      if (amountCents <= 0 || amountCents > payable)
        throw new ApiError(422, "insufficient_funds", `payable balance is ${payable}`);

      // §7 — hold the first payout of any new account for 7 days past settlement.
      const { rows: [prior] } = await c.query(
        `select 1 from ledger_entry where account_ref = $1 and kind = 'cash_out' limit 1`,
        [refs.payable(accountId)],
      );
      if (!prior) {
        const { rows: [latest] } = await c.query(
          `select max(created_at) as at from ledger_entry
           where account_ref = $1 and kind = 'payout_clear'`,
          [refs.payable(accountId)],
        );
        const eligibleAt = new Date(latest.at);
        eligibleAt.setDate(eligibleAt.getDate() + config.firstPayoutHoldDays);
        if (eligibleAt > new Date())
          throw new ApiError(403, "first_payout_hold",
            `first payouts clear ${config.firstPayoutHoldDays} days after settlement; try after ${eligibleAt.toISOString()}`);
      }

      const { rows: [acct] } = await c.query("select * from account where id = $1", [accountId]);
      const transfer = await this.stripe.createTransfer(
        amountCents, acct.payout_method_id ?? `acct_${accountId.slice(0, 8)}`, { accountId });
      await cashOut(c, accountId, amountCents);
      await pushWire(c, accountId, `Cash out sent — $${(amountCents / 100).toLocaleString()} on the way.`, "money");
      return { transferId: transfer.id, amountCents };
    });
  }

  // Settlement: every claim terminal → refund the remaining escrow to the
  // artist's original payment method. The fee was already grossed out of the
  // purse at payout time, so the refund is exactly what's left (§4, §8 Q1).
  async settleBounty(bountyId: string) {
    return withTxn(async (c) => {
      const { rows: [b] } = await c.query("select * from bounty where id = $1 for update", [bountyId]);
      if (!b) throw new ApiError(404, "not_found", "bounty not found");
      if (!["live", "closing"].includes(b.state))
        throw new ApiError(409, "bad_state", `bounty is ${b.state}`);
      const { rows: [{ unfinished }] } = await c.query(
        `select count(*)::int as unfinished from claim cl
         where cl.bounty_id = $1 and cl.state in ('open','submitted')`,
        [bountyId],
      );
      if (unfinished > 0) throw new ApiError(409, "claims_outstanding", `${unfinished} claims still open`);
      if (b.state === "live") await transition(c, "bounty", bountyId, "closing");

      const remaining = await balance(c, refs.escrow(bountyId));
      if (remaining > 0) {
        await this.stripe.createRefund(b.stripe_payment_intent_id, remaining);
        await refundArtist(c, bountyId, b.artist_account_id, remaining);
      }
      await transition(c, "bounty", bountyId, "settled");
      await pushWire(c, b.artist_account_id,
        `“${b.title}” settled. $${(remaining / 100).toLocaleString()} unspent refunded.`, "money");
      return { refundedCents: remaining };
    });
  }

  // §8 Q4 — Stripe charge.dispute webhook: clippers keep their money, the
  // spent portion becomes artist debt, the bounty freezes, the artist is
  // suspended from posting until the debt clears.
  async handleChargeback(paymentIntentId: string, amountCents: number) {
    return withTxn(async (c) => {
      const { rows: [b] } = await c.query(
        "select * from bounty where stripe_payment_intent_id = $1 for update", [paymentIntentId]);
      if (!b) throw new ApiError(404, "unknown_payment", "no bounty for that payment intent");
      const { debtCents } = await recordChargeback(c, b.id, b.artist_account_id, amountCents);
      if (!["settled", "cancelled", "frozen"].includes(b.state))
        await transition(c, "bounty", b.id, "frozen");
      await c.query("update account set suspended_at = now() where id = $1", [b.artist_account_id]);
      await pushWire(c, b.artist_account_id,
        `Payment reversed on “${b.title}”. $${(debtCents / 100).toLocaleString()} is owed; posting is paused until it clears.`,
        "warn");
      return { debtCents, bountyId: b.id, bountyTitle: b.title as string };
    }).then((out) => {
      emitOpsEvent("chargeback", out);
      return out;
    });
  }
}

// Background job: claims past expires_at return their slot to the board.
// Expiry is the only state change a job may make without an actor (§3).
export async function expireClaims(now = new Date()) {
  return withTxn(async (c) => {
    const { rows } = await c.query(
      `select id, bounty_id, account_id from claim
       where state = 'open' and expires_at <= $1 for update skip locked`,
      [now],
    );
    for (const cl of rows) {
      await transition(c, "claim", cl.id, "expired");
      await pushWire(c, cl.account_id, "A claim lapsed — the slot went back on the board.", "warn");
    }
    return rows.length;
  });
}
