import { beforeAll, describe, expect, it } from "vitest";
import { resetDb, pool } from "./helpers.js";
import { seedDemo } from "../scripts/seed-demo.js";
import { apnsProviderJwt } from "../src/modules/notify/apns.js";
import { generateKeyPairSync, createVerify } from "node:crypto";

describe("demo seed", () => {
  beforeAll(resetDb);

  it("seeds a reviewable marketplace and refuses to double-seed", async () => {
    const out = await seedDemo();
    expect(out.bountyIds).toHaveLength(4);
    expect(out.clipperToken).toBeTruthy();

    const { rows: [counts] } = await pool.query(`
      select
        (select count(*)::int from bounty where state = 'live') as live,
        (select count(*)::int from submission where state = 'counting') as counting,
        (select count(*)::int from submission where state = 'paid') as paid,
        (select count(*)::int from submission where state = 'held') as held`);
    expect(counts).toEqual({ live: 4, counting: 1, paid: 1, held: 1 });

    await expect(seedDemo()).rejects.toThrow(/refusing to seed/);
  });
});

describe("apns provider jwt", () => {
  it("signs a verifiable ES256 token", () => {
    const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
    process.env.APNS_KEY_P8 = privateKey.export({ type: "pkcs8", format: "pem" }).toString();
    process.env.APNS_KEY_ID = "TESTKEY123";
    process.env.APNS_TEAM_ID = "TEAM123456";

    const jwt = apnsProviderJwt();
    const [header, claims, signature] = jwt.split(".");
    expect(JSON.parse(Buffer.from(header!, "base64url").toString())).toEqual({
      alg: "ES256", kid: "TESTKEY123",
    });
    expect(JSON.parse(Buffer.from(claims!, "base64url").toString()).iss).toBe("TEAM123456");

    const verifier = createVerify("sha256");
    verifier.update(`${header}.${claims}`);
    const valid = verifier.verify(
      { key: publicKey, dsaEncoding: "ieee-p1363" as const },
      Buffer.from(signature!, "base64url"),
    );
    expect(valid).toBe(true);

    delete process.env.APNS_KEY_P8;
    delete process.env.APNS_KEY_ID;
    delete process.env.APNS_TEAM_ID;
  });
});
