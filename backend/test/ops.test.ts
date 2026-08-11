import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createServer, type Server } from "node:http";
import { fundedBountyWithSubmission, resetDb } from "./helpers.js";
import { config } from "../src/config.js";

// The ops webhook feeds the staff review queue (Notion/Airtable via a
// collector). Every human-decision event must land there.
describe("ops events", () => {
  const received: { kind: string }[] = [];
  let server: Server;

  beforeAll(async () => {
    await resetDb();
    server = createServer((req, res) => {
      let body = "";
      req.on("data", (c) => (body += c));
      req.on("end", () => {
        received.push(JSON.parse(body));
        res.writeHead(200).end("ok");
      });
    });
    await new Promise<void>((resolve) => server.listen(0, resolve));
    const { port } = server.address() as { port: number };
    process.env.OPS_WEBHOOK_URL = `http://127.0.0.1:${port}/hook`;
  });

  afterAll(async () => {
    delete process.env.OPS_WEBHOOK_URL;
    await new Promise((resolve) => server.close(resolve));
  });

  const waitFor = async (n: number) => {
    for (let i = 0; i < 50 && received.length < n; i++)
      await new Promise((r) => setTimeout(r, 20));
  };

  it("emits dispute_opened, appeal_lodged, and spike_hold", async () => {
    const { svc, artist, clipper, submission } = await fundedBountyWithSubmission({ purseCents: 5_000_000 });
    // spike: one interval above the absolute floor
    svc.tiktok.videos.get("v1")!.viewCount = config.spikeAbsoluteFloor + 1;
    await svc.counting.pollSubmission(submission.id);
    await waitFor(1);
    expect(received.map((r) => r.kind)).toContain("spike_hold");

    // staff clears the spike back to counting, artist disputes, clipper appeals
    const { pool } = await import("./helpers.js");
    await pool.query("update submission set state = 'counting', held_reason = null where id = $1", [submission.id]);
    const verdict = await svc.bounties.verdict(artist.id, submission.id, "dispute", "sound_mismatch");
    await svc.bounties.appeal(clipper.id, (verdict as { disputeId: string }).disputeId, "the sound matches", []);
    await waitFor(3);

    const kinds = received.map((r) => r.kind);
    expect(kinds).toContain("dispute_opened");
    expect(kinds).toContain("appeal_lodged");
    const dispute = received.find((r) => r.kind === "dispute_opened") as Record<string, unknown>;
    expect(dispute.reason).toBe("sound_mismatch");
    expect(dispute.slaHours).toBe(72);
  });
});
