import { randomUUID } from "node:crypto";
import type { Queryable } from "../db.js";
import { config } from "../config.js";

// Account-ref conventions. Balance of a ref = credits − debits.
//   external:artist:{accountId}    the artist's outside money (payment method)
//   escrow:bounty:{bountyId}       the funded purse
//   held:submission:{id}           clipper portion reserved against counted views
//   held_fee:submission:{id}       fee gross-up reserved alongside it (§8 Q1: artist pays)
//   payable:clipper:{accountId}    cleared, cashable
//   fees:platform                  collected platform fees
//   external:clipper:{accountId}   money transferred out via Stripe Connect
//   debt:artist:{accountId}        chargeback debt (§8 Q4)
//   external:chargeback            money pulled back by the card network
export const refs = {
  externalArtist: (id: string) => `external:artist:${id}`,
  escrow: (bountyId: string) => `escrow:bounty:${bountyId}`,
  held: (submissionId: string) => `held:submission:${submissionId}`,
  heldFee: (submissionId: string) => `held_fee:submission:${submissionId}`,
  payable: (accountId: string) => `payable:clipper:${accountId}`,
  fees: "fees:platform",
  externalClipper: (id: string) => `external:clipper:${id}`,
  debtArtist: (id: string) => `debt:artist:${id}`,
  externalChargeback: "external:chargeback",
};

export type LedgerKind =
  | "purse_fund"
  | "accrual_reserve"
  | "release_reserve"
  | "payout_clear"
  | "cash_out"
  | "refund"
  | "chargeback";

export interface Leg {
  ref: string;
  direction: "debit" | "credit";
  amountCents: number;
}

// Append one balanced transaction. The deferred DB trigger re-checks the
// zero-sum invariant at commit; we also check here so the error is close to
// the caller.
export async function postTxn(
  db: Queryable,
  kind: LedgerKind,
  legs: Leg[],
  ids: { bountyId?: string; submissionId?: string } = {},
): Promise<string> {
  const sum = legs.reduce(
    (a, l) => a + (l.direction === "credit" ? l.amountCents : -l.amountCents),
    0,
  );
  if (sum !== 0) throw new Error(`unbalanced ${kind} txn: off by ${sum}`);
  if (legs.some((l) => l.amountCents <= 0 || !Number.isInteger(l.amountCents)))
    throw new Error(`invalid amount in ${kind} txn`);
  const txnId = randomUUID();
  // One INSERT for all legs: the deferred zero-sum trigger fires at (implicit)
  // transaction commit, so a txn's legs must never be split across statements
  // when running in autocommit.
  const values: string[] = [];
  const params: unknown[] = [txnId, kind, ids.bountyId ?? null, ids.submissionId ?? null];
  legs.forEach((l, i) => {
    const p = params.length;
    values.push(`($1, $${p + 1}, $${p + 2}, $${p + 3}, $2, $3, $4)`);
    params.push(l.ref, l.direction, l.amountCents);
  });
  await db.query(
    `insert into ledger_entry (txn_id, account_ref, direction, amount_cents, kind, bounty_id, submission_id)
     values ${values.join(", ")}`,
    params,
  );
  return txnId;
}

export async function balance(db: Queryable, ref: string): Promise<number> {
  const { rows } = await db.query(
    `select coalesce(sum(case direction when 'credit' then amount_cents else -amount_cents end), 0)::bigint as bal
     from ledger_entry where account_ref = $1`,
    [ref],
  );
  return rows[0].bal;
}

export const platformFee = (clipperCents: number) =>
  Math.floor((clipperCents * config.platformFeeBps) / 10000);

// Largest clipper amount c such that c + fee(c) fits in `remaining`.
export function maxClipperAmountFor(remaining: number): number {
  let c = Math.max(Math.floor((remaining * 10000) / (10000 + config.platformFeeBps)), 0);
  while (c + platformFee(c) > remaining) c--;
  while (c + 1 + platformFee(c + 1) <= remaining) c++; // fee floors can leave headroom
  return Math.max(c, 0);
}

// -- canonical money flows ---------------------------------------------------

export function fundPurse(db: Queryable, bountyId: string, artistId: string, amount: number) {
  return postTxn(db, "purse_fund", [
    { ref: refs.externalArtist(artistId), direction: "debit", amountCents: amount },
    { ref: refs.escrow(bountyId), direction: "credit", amountCents: amount },
  ], { bountyId });
}

// Reserve `clipperCents` (+ the grossed-up fee) out of the purse.
export function reserveAccrual(
  db: Queryable, bountyId: string, submissionId: string, clipperCents: number,
) {
  const fee = platformFee(clipperCents);
  const legs: Leg[] = [
    { ref: refs.escrow(bountyId), direction: "debit", amountCents: clipperCents + fee },
    { ref: refs.held(submissionId), direction: "credit", amountCents: clipperCents },
  ];
  if (fee > 0) legs.push({ ref: refs.heldFee(submissionId), direction: "credit", amountCents: fee });
  return postTxn(db, "accrual_reserve", legs, { bountyId, submissionId });
}

// Give a reserve back to the purse (void, or dispute resolved for the artist).
export async function releaseReserve(db: Queryable, bountyId: string, submissionId: string) {
  const held = await balance(db, refs.held(submissionId));
  const heldFee = await balance(db, refs.heldFee(submissionId));
  if (held + heldFee === 0) return null;
  const legs: Leg[] = [{ ref: refs.escrow(bountyId), direction: "credit", amountCents: held + heldFee }];
  if (held > 0) legs.push({ ref: refs.held(submissionId), direction: "debit", amountCents: held });
  if (heldFee > 0) legs.push({ ref: refs.heldFee(submissionId), direction: "debit", amountCents: heldFee });
  return postTxn(db, "release_reserve", legs, { bountyId, submissionId });
}

// Clear a submission's reserve: clipper portion becomes payable, fee is collected.
export async function clearToPayable(
  db: Queryable, bountyId: string, submissionId: string, clipperAccountId: string,
) {
  const held = await balance(db, refs.held(submissionId));
  const heldFee = await balance(db, refs.heldFee(submissionId));
  if (held + heldFee === 0) return { paid: 0 };
  const legs: Leg[] = [];
  if (held > 0) {
    legs.push({ ref: refs.held(submissionId), direction: "debit", amountCents: held });
    legs.push({ ref: refs.payable(clipperAccountId), direction: "credit", amountCents: held });
  }
  if (heldFee > 0) {
    legs.push({ ref: refs.heldFee(submissionId), direction: "debit", amountCents: heldFee });
    legs.push({ ref: refs.fees, direction: "credit", amountCents: heldFee });
  }
  await postTxn(db, "payout_clear", legs, { bountyId, submissionId });
  return { paid: held };
}

export function cashOut(db: Queryable, accountId: string, amount: number) {
  return postTxn(db, "cash_out", [
    { ref: refs.payable(accountId), direction: "debit", amountCents: amount },
    { ref: refs.externalClipper(accountId), direction: "credit", amountCents: amount },
  ]);
}

export function refundArtist(db: Queryable, bountyId: string, artistId: string, amount: number) {
  return postTxn(db, "refund", [
    { ref: refs.escrow(bountyId), direction: "debit", amountCents: amount },
    { ref: refs.externalArtist(artistId), direction: "credit", amountCents: amount },
  ], { bountyId });
}

// §8 Q4 — the card network pulled the full funding back. Whatever is still in
// escrow goes with it; the already-spent portion becomes the artist's debt.
// Paid clippers keep their money.
export async function recordChargeback(
  db: Queryable, bountyId: string, artistId: string, chargedBackCents: number,
) {
  const inEscrow = await balance(db, refs.escrow(bountyId));
  const spent = chargedBackCents - inEscrow;
  if (spent < 0) throw new Error("chargeback exceeds funded amount");
  const legs: Leg[] = [
    { ref: refs.externalChargeback, direction: "credit", amountCents: chargedBackCents },
  ];
  if (inEscrow > 0) legs.push({ ref: refs.escrow(bountyId), direction: "debit", amountCents: inEscrow });
  if (spent > 0) legs.push({ ref: refs.debtArtist(artistId), direction: "debit", amountCents: spent });
  await postTxn(db, "chargeback", legs, { bountyId });
  return { debtCents: spent };
}
