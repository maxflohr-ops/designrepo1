import type { Queryable } from "../db.js";

// §3 — the three state machines, as data. Every state change in the system
// goes through transition(), which locks the row, checks the edge, and writes.

export type BountyState = "draft" | "funding" | "live" | "closing" | "settled" | "cancelled" | "frozen";
export type ClaimState = "open" | "submitted" | "settled" | "expired";
export type SubmissionState =
  | "pending_checks" | "counting" | "payable" | "paid" | "held" | "void" | "rejected";

const BOUNTY: Record<BountyState, BountyState[]> = {
  draft: ["funding", "cancelled"],
  funding: ["live", "cancelled"],
  live: ["closing", "frozen"], // a live bounty cannot lose funding; frozen only via chargeback
  closing: ["settled", "frozen"],
  settled: [],
  cancelled: [],
  frozen: [],
};

const CLAIM: Record<ClaimState, ClaimState[]> = {
  open: ["submitted", "expired"], // expired is the only job-made change without an actor
  submitted: ["settled"],
  settled: [],
  expired: [],
};

const SUBMISSION: Record<SubmissionState, SubmissionState[]> = {
  pending_checks: ["counting", "rejected"],
  counting: ["payable", "held", "void"],
  payable: ["paid", "held"],
  held: ["counting", "payable", "void"], // resolve back, or void (deleted video / dispute lost)
  paid: [],
  void: [],
  rejected: [],
};

const MACHINES = { bounty: BOUNTY, claim: CLAIM, submission: SUBMISSION } as const;

export class InvalidTransition extends Error {
  constructor(table: string, from: string, to: string) {
    super(`${table}: ${from} → ${to} is not a legal transition`);
  }
}

export function assertTransition(
  table: keyof typeof MACHINES, from: string, to: string,
): void {
  const edges = (MACHINES[table] as Record<string, string[]>)[from];
  if (!edges || !edges.includes(to)) throw new InvalidTransition(table, from, to);
}

// Lock the row, validate the edge, write the new state. Returns the previous state.
export async function transition(
  db: Queryable,
  table: keyof typeof MACHINES,
  id: string,
  to: string,
  extraSet = "",
  extraParams: unknown[] = [],
): Promise<string> {
  const { rows } = await db.query(`select state from ${table} where id = $1 for update`, [id]);
  if (!rows[0]) throw new Error(`${table} ${id} not found`);
  const from = rows[0].state as string;
  assertTransition(table, from, to);
  await db.query(
    `update ${table} set state = $2${table === "bounty" ? ", updated_at = now()" : ""}${extraSet} where id = $1`,
    [id, to, ...extraParams],
  );
  return from;
}
