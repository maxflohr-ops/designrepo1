import { migrate, pool } from "../db.js";

await migrate();
console.log("migrations applied");
await pool.end();
