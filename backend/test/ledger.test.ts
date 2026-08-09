import { beforeEach, describe, expect, it } from "vitest";
import { resetDb, pool, withTxn, mkAccount, mkSound } from "./helpers.js";
import {
  balance, fundPurse, postTxn, refs, reserveAccrual, clearToPayable,
  releaseReserve, recordChargeback, platformFee, maxClipperAmountFor,
} from "../src/domain/ledger.js";

let B: string, SUB: string, ARTIST: string, CLIPPER: string;

async function seedGraph() {
  await resetDb();
  const artist = await mkAccount("ridgeclub", ["artist"]);
  const clipper = await mkAccount("merrowcuts");
  const sound = await mkSound("m_ridge", "Ridge Club", artist.id);
  const { rows: [b] } = await pool.query(
    `insert into bounty (sound_id, artist_account_id, title, payout_model, rate_cents, rate_unit,
                         purse_cents, deadline_at, state)
     values ($1,$2,'t','per_view',500,5000,50000, now() + interval '10 days', 'live') returning id`,
    [sound.id, artist.id]);
  const { rows: [cl] } = await pool.query(
    `insert into claim (bounty_id, account_id, expires_at) values ($1,$2, now() + interval '6 days') returning id`,
    [b.id, clipper.id]);
  const { rows: [s] } = await pool.query(
    `insert into submission (claim_id, tiktok_video_id, posted_at, window_ends_at)
     values ($1,'v1', now(), now() + interval '14 days') returning id`,
    [cl.id]);
  B = b.id; SUB = s.id; ARTIST = artist.id; CLIPPER = clipper.id;
}

describe("ledger", () => {
  beforeEach(seedGraph);

  it("rejects an unbalanced transaction in code and in the database", async () => {
    await expect(
      postTxn(pool, "purse_fund", [
        { ref: refs.escrow(B), direction: "credit", amountCents: 100 },
      ]),
    ).rejects.toThrow(/unbalanced/);

    await expect(
      withTxn(async (c) => {
        await c.query(
          `insert into ledger_entry (txn_id, account_ref, direction, amount_cents, kind)
           values (gen_random_uuid(), $1, 'credit', 100, 'purse_fund')`,
          [refs.escrow(B)],
        );
      }),
    ).rejects.toThrow(/does not balance/);
  });

  it("is append-only: updates and deletes are no-ops", async () => {
    await fundPurse(pool, B, ARTIST, 1000);
    await pool.query("update ledger_entry set amount_cents = 1");
    await pool.query("delete from ledger_entry");
    expect(await balance(pool, refs.escrow(B))).toBe(1000);
  });

  it("derives balances through fund → reserve → clear, fee grossed from the purse", async () => {
    await fundPurse(pool, B, ARTIST, 50_000);
    expect(await balance(pool, refs.escrow(B))).toBe(50_000);

    await reserveAccrual(pool, B, SUB, 8_800);
    const fee = platformFee(8_800);
    expect(fee).toBe(880);
    expect(await balance(pool, refs.escrow(B))).toBe(50_000 - 8_800 - fee);
    expect(await balance(pool, refs.held(SUB))).toBe(8_800);
    expect(await balance(pool, refs.heldFee(SUB))).toBe(fee);

    const { paid } = await clearToPayable(pool, B, SUB, CLIPPER);
    expect(paid).toBe(8_800); // clipper receives the full advertised amount (§8 Q1)
    expect(await balance(pool, refs.payable(CLIPPER))).toBe(8_800);
    expect(await balance(pool, refs.fees)).toBe(fee);
    expect(await balance(pool, refs.held(SUB))).toBe(0);
  });

  it("releases a reserve back to the purse in full, fee included", async () => {
    await fundPurse(pool, B, ARTIST, 10_000);
    await reserveAccrual(pool, B, SUB, 2_000);
    await releaseReserve(pool, B, SUB);
    expect(await balance(pool, refs.escrow(B))).toBe(10_000);
    expect(await balance(pool, refs.held(SUB))).toBe(0);
    expect(await balance(pool, refs.heldFee(SUB))).toBe(0);
  });

  it("chargeback: escrow drains, spent portion becomes artist debt, clippers keep payable", async () => {
    await fundPurse(pool, B, ARTIST, 50_000);
    await reserveAccrual(pool, B, SUB, 10_000);
    await clearToPayable(pool, B, SUB, CLIPPER);

    const spent = 10_000 + platformFee(10_000);
    const { debtCents } = await recordChargeback(pool, B, ARTIST, 50_000);
    expect(debtCents).toBe(spent);
    expect(await balance(pool, refs.escrow(B))).toBe(0);
    expect(await balance(pool, refs.debtArtist(ARTIST))).toBe(-spent); // debit-only ref reads negative
    expect(await balance(pool, refs.payable(CLIPPER))).toBe(10_000); // §8 Q4: clippers keep it
  });

  it("maxClipperAmountFor inverts the fee gross-up exactly", () => {
    for (const remaining of [0, 1, 10, 11, 999, 1000, 54_999, 55_000]) {
      const c = maxClipperAmountFor(remaining);
      expect(c + platformFee(c)).toBeLessThanOrEqual(remaining);
      expect(c + 1 + platformFee(c + 1)).toBeGreaterThan(remaining);
    }
  });
});
