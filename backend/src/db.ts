import pg from "pg";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { config } from "./config.js";

export type Queryable = pg.Pool | pg.PoolClient;

export const pool = new pg.Pool({ connectionString: config.databaseUrl, max: 10 });

// int8 comes back as string by default; every amount in this system fits a JS number.
pg.types.setTypeParser(20, (v) => Number(v));

export async function withTxn<T>(fn: (client: pg.PoolClient) => Promise<T>): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query("begin");
    const out = await fn(client);
    await client.query("commit");
    return out;
  } catch (err) {
    await client.query("rollback").catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

export async function migrate(dir = new URL("../migrations", import.meta.url).pathname) {
  await pool.query(
    "create table if not exists schema_migration (name text primary key, applied_at timestamptz not null default now())",
  );
  for (const file of readdirSync(dir).filter((f) => f.endsWith(".sql")).sort()) {
    const { rowCount } = await pool.query("select 1 from schema_migration where name = $1", [file]);
    if (rowCount) continue;
    await withTxn(async (c) => {
      await c.query(readFileSync(join(dir, file), "utf8"));
      await c.query("insert into schema_migration (name) values ($1)", [file]);
    });
  }
}
