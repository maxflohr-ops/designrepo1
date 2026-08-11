import { buildServer } from "../api/server.js";
import { migrate } from "../db.js";
import { config } from "../config.js";
import { makeGateways } from "../gateways/index.js";

await migrate();
const app = buildServer(makeGateways());
await app.listen({ port: config.port, host: "0.0.0.0" });
console.log(`bounty sounds backend on :${config.port} (gateways: ${process.env.GATEWAYS ?? "fake"})`);
