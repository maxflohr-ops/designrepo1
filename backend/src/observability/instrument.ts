// Sentry bootstrap. Imported FIRST from both entrypoints (before the app or
// worker is constructed) so the SDK's auto-instrumentation can patch http,
// pg and ioredis before anything opens a connection.
//
// No DSN → init() is skipped entirely and every Sentry call below is a no-op,
// so local runs, CI and the test suite behave exactly as they did before.
import * as Sentry from "@sentry/node";

const dsn = process.env.SENTRY_DSN;

if (dsn) {
  Sentry.init({
    dsn,
    environment: process.env.SENTRY_ENVIRONMENT ?? process.env.NODE_ENV ?? "production",
    release: process.env.SENTRY_RELEASE,
    // The ledger is money: sample every error, and enough traces to see the
    // counting job's latency without paying for full-rate tracing.
    tracesSampleRate: Number(process.env.SENTRY_TRACES_SAMPLE_RATE ?? 0.1),
    // Never let request bodies reach Sentry — they carry TikTok tokens,
    // Stripe client secrets and Idempotency-Keys.
    sendDefaultPii: false,
    beforeSend(event) {
      if (event.request) {
        delete event.request.data;
        delete event.request.cookies;
        if (event.request.headers) {
          for (const h of ["authorization", "x-device-attestation", "stripe-signature"]) {
            delete event.request.headers[h];
          }
        }
      }
      return event;
    },
  });
}

export const sentryEnabled = Boolean(dsn);
export { Sentry };
