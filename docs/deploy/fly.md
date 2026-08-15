# Workstream F — Fly.io deploy (prepared, NOT deployed)

Everything here is ready to run. Nothing in this document has been executed —
no app created, no secrets set, no DNS touched. Run it top to bottom when you
want production up.

Config lives in `backend/fly.toml`. Two process groups off the one
`backend/Dockerfile` image:

| group | command | traffic |
|---|---|---|
| `api` | `node dist/src/bin/server.js` | public, behind Fly proxy, `min_machines_running = 2` |
| `worker` | `node dist/src/bin/worker.js` | none — claim expiry + the TikTok counting pass |

Migrations run once per deploy through `release_command`, before either group
starts. Both entrypoints also call `migrate()` at boot; that is idempotent and
stays as a safety net for a machine restarted outside a deploy.

---

## 0. Prerequisites

```bash
brew install flyctl          # or: curl -L https://fly.io/install.sh | sh
fly auth login
fly version                  # confirm you're on a current flyctl
```

---

## 1. Create the app

```bash
fly apps create bounty-sounds-api --org personal
```

Nothing deploys yet — `fly.toml` is already checked in, so skip `fly launch`
(it would overwrite the config).

---

## 2. Managed Postgres

```bash
fly mpg create \
  --name bounty-sounds-db \
  --region sjc \
  --plan basic \
  --volume-size 10

fly mpg list                                   # note the cluster id
fly mpg attach <clusterID> -a bounty-sounds-api
```

`attach` sets `DATABASE_URL` as a secret and restarts the app.

### Read this before you trust the backups

Two things to know, both of which matter because the ledger is the money.

**The recovery window is 10 days and is not currently adjustable.** Fly's
managed Postgres takes automated backups on all plans, but the retention
window is fixed. For a double-entry ledger that is the system of record for
real payouts, 10 days of history is thin — a reconciliation error discovered
in month two is not recoverable from Fly alone. I could not confirm from Fly's
public docs that MPG exposes true point-in-time recovery (restore to an
arbitrary timestamp) as opposed to restore-from-snapshot. **Confirm this with
Fly support before the pilot funds a real purse**, and ask them directly:
*"does MPG support PITR to an arbitrary second within the window, and can
retention be extended on a paid plan?"*

**Regardless of the answer, add your own off-site dump.** This is the belt to
Fly's braces and costs almost nothing:

```bash
# nightly logical backup to Tigris (S3-compatible, on Fly)
fly storage create bounty-sounds-backups        # provisions a Tigris bucket + creds
```

Then run `pg_dump` on a schedule against the **direct** (unpooled) URL and
`aws s3 cp` the result to that bucket, with the object keyed by date. Keep 90
days. If you'd rather not run a cron machine, a GitHub Actions scheduled
workflow with the direct URL in repo secrets does the same job.

**Use the direct URL for migrations and dumps, not the pooled one.** `fly mpg
attach` sets `DATABASE_URL` to the *pooled* PgBouncer connection string by
default. Pooled transaction-mode connections are correct for the API's normal
request traffic, but they are the wrong tool for schema migrations and
`pg_dump` — both want a stable session. Pull the direct URL from
`fly mpg status <clusterID>` and set it as a separate secret:

```bash
fly secrets set DIRECT_DATABASE_URL="postgres://...direct-host.../bounty" -a bounty-sounds-api
```

If the release_command migration ever hangs or errors on a lock, that is the
pooler — point it at `DIRECT_DATABASE_URL` and it will clear.

---

## 3. Redis

```bash
fly redis create --name bounty-sounds-redis --region sjc
fly redis status bounty-sounds-redis     # prints the redis:// URL
fly secrets set REDIS_URL="redis://..." -a bounty-sounds-api
```

Redis here carries rate limits on auth and claims, and counting-job
bookkeeping. Nothing in Redis is the system of record, so eviction is
survivable — but if you see claim rate limits behaving oddly after a Redis
restart, that is why.

---

## 4. Secrets

Every one of these is env-only and must never land in the repo. `GATEWAYS` is
already pinned to `live` in `fly.toml`, so these are load-bearing the moment
you deploy.

```bash
fly secrets set -a bounty-sounds-api \
  STRIPE_SECRET_KEY="sk_test_..." \
  STRIPE_WEBHOOK_SECRET="whsec_..." \
  TIKTOK_CLIENT_SECRET="..." \
  TIKTOK_REDIRECT_URI="https://api.bountysounds.com/v1/auth/tiktok/callback" \
  SENTRY_DSN="https://...@...ingest.sentry.io/..." \
  OPS_WEBHOOK_URL="https://hooks.slack.com/services/..." \
  APNS_KEY_ID="..." \
  APNS_TEAM_ID="..." \
  APNS_KEY_P8="$(cat AuthKey_XXXXXXXX.p8)"
```

Set from `fly.toml`, no action needed: `NODE_ENV`, `PORT`, `GATEWAYS`,
`PUBLIC_WEB_URL`, `APNS_HOST`, `APNS_BUNDLE_ID`, `TIKTOK_DIRECT_POST`,
`POLL_BUDGET_PER_RUN`, `SENTRY_ENVIRONMENT`, `SENTRY_TRACES_SAMPLE_RATE`.
Set by `fly mpg attach` / `fly redis`: `DATABASE_URL`, `REDIS_URL`.
`TIKTOK_CLIENT_KEY` is a public identifier and is already in `src/config.ts`.

**Start Stripe in test mode.** Deploy, smoke-test end to end on
`sk_test_`, and only then swap in the live key. `GATEWAYS=live` selects the
real Stripe/TikTok implementations; it says nothing about which Stripe *mode*
the key is for.

---

## 5. Deploy

```bash
fly deploy -c backend/fly.toml
fly status -a bounty-sounds-api            # api ×2 + worker ×1 should be green
fly logs -a bounty-sounds-api -g worker    # expect a "tick:" line within a minute
```

Scale later with `fly scale count api=4 worker=1 -a bounty-sounds-api`.
Keep `worker` at exactly 1 — the counting job's cadence assumes a single
poller, and a second one would double-poll TikTok straight into 429s.

---

## 6. DNS + TLS

```bash
fly certs add api.bountysounds.com -a bounty-sounds-api
fly certs show api.bountysounds.com -a bounty-sounds-api   # prints required records
```

Add the printed A/AAAA (or CNAME) records at your registrar, wait for
validation, then point at the new host:

- **Stripe** → webhook endpoint `https://api.bountysounds.com/v1/webhooks/stripe`.
  The signing secret it gives you is `STRIPE_WEBHOOK_SECRET`.
- **TikTok** → redirect URI `https://api.bountysounds.com/v1/auth/tiktok/callback`,
  matching `TIKTOK_REDIRECT_URI` exactly, character for character.

---

## 7. Sentry

`backend/src/observability/instrument.ts` is imported first from both
entrypoints so the SDK patches `http`, `pg` and `ioredis` before any
connection opens. With no `SENTRY_DSN` it is a total no-op — which is why CI
and the local suite are unaffected (still 54/54 green).

It is configured to keep secrets out of Sentry: `sendDefaultPii: false`, and a
`beforeSend` that strips request bodies, cookies, and the `authorization`,
`x-device-attestation` and `stripe-signature` headers. Don't relax that —
those headers carry session tokens and App Attest assertions.

Create a project at sentry.io (Node platform), copy the DSN into the secret
above. Traces sample at 10%; errors at 100%.

---

## 8. Uptime check on /healthz

Two layers, and they do different jobs:

1. **Fly's own check** is already in `fly.toml` — `GET /healthz` every 15s.
   This gates rolling deploys and restarts sick machines. It does *not* tell
   you when the whole app is down.
2. **An external monitor is the one that pages you.** Point any of
   Better Stack / Pingdom / UptimeRobot at `https://api.bountysounds.com/healthz`,
   60s interval, alert after 2 consecutive failures, notify your phone.

Also worth an alert, because neither check above covers it: the worker has no
inbound traffic, so it can die silently while `/healthz` stays green. Add a
Sentry alert rule for "no `tick:` events in 10 minutes", or have the worker
ping a Better Stack heartbeat URL each pass.

---

## 9. Smoke test (Stripe test mode)

```bash
curl -fsS https://api.bountysounds.com/healthz && echo OK
```

Then, per `docs/COWORK-HANDOFF.md` §F.4, run one bounty end to end on test
keys: fund a purse → claim → submit → count → approve → cash out. Finish by
reconciling the ledger for that bounty:

```sql
-- must balance exactly; funded = paid + fees + held + refunded
SELECT kind, direction, SUM(amount_cents)
FROM ledger_entry WHERE bounty_id = '<id>'
GROUP BY kind, direction ORDER BY kind;
```

---

## 10. Rollback

```bash
fly releases -a bounty-sounds-api
fly deploy --image <previous-image-ref> -c backend/fly.toml
```

Note that a rollback does **not** undo a migration. Any migration that lands
with a deploy must be backward-compatible with the previous release, or the
rollback path is a restore instead — which is the whole reason §2's off-site
dump matters.

---

## What I could not verify

- Whether MPG offers true arbitrary-timestamp PITR, and whether the 10-day
  window can be extended. Ask Fly support before the pilot (§2).
- Exact plan sizing. `basic` (shared-2x / 1GB, ~$38/mo) is right for a pilot
  and will not carry launch traffic; watch connection counts and step up to
  `launch` when the counting job's poll volume climbs.
- Nothing here has been run against a real Fly account, so the first
  `fly deploy` may surface an org/region availability detail I can't see from
  here.
