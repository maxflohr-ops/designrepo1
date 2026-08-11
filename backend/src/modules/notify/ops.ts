// Staff-facing ops events. When OPS_WEBHOOK_URL is set (Make/Zapier hook or
// any collector feeding the "Bounty Sounds Ops — Review Queue" board), every
// event that needs a human lands there: disputes, appeals, spike holds,
// chargebacks. Fire-and-forget — ops visibility must never fail a money txn.
export function emitOpsEvent(
  kind: "dispute_opened" | "appeal_lodged" | "spike_hold" | "chargeback",
  data: Record<string, unknown>,
): void {
  const url = process.env.OPS_WEBHOOK_URL;
  if (!url) return;
  fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ kind, at: new Date().toISOString(), ...data }),
  }).catch(() => {});
}
