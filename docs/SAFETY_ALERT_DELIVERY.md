# Safety-alert delivery deployment

The safety-alert feature has three deliberately separate roles:

- The pipeline authors, validates, stages, and promotes a human-approved event feed.
- Supabase stores the public current release, privately associates a push token with a signed-in account, and performs server-only audience selection from `user_stacks`.
- Firebase Cloud Messaging (FCM) delivers only a generic nudge. The device re-fetches and checksum-verifies the feed before showing regulatory copy.

## One-time infrastructure

1. Create or select the Firebase project used by the iOS and Android apps, then run `flutterfire configure` in this repository. Commit the generated native configuration appropriate to the release process; do not put service-account credentials in the app.
2. Enable Push Notifications in the Apple App ID/provisioning profile and upload the APNs key to Firebase. Enable Firebase Cloud Messaging for the Android app.
3. Apply `supabase/migrations/20260808120000_safety_alert_delivery.sql`.
4. Deploy `register-push-token` and `dispatch-safety-alert-release`. The latter is intentionally configured with `verify_jwt = false` because it authenticates the pipeline using its own constant-time secret header; do not expose that secret to the app.
5. Set Edge Function secrets:
   - `FCM_SERVICE_ACCOUNT_JSON` — the Firebase service-account JSON, server-only.
   - `SAFETY_ALERT_DISPATCH_SECRET` — a long random value shared only with the pipeline runtime.

## Publishing a verified event

The FDA sync can create a draft only. A human verifies authority, scope, matching snapshot, consumer copy, and `consumer_disposition` (`block` or `review`), then marks the revision published. From the pipeline repository run:

```bash
bash scripts/run_safety_alert_publish.sh
```

It validates and stages the immutable feed, uploads a content-addressed object, promotes the release atomically, and asks the server-only dispatcher to send generic FCM nudges. Re-running the same release is safe: delivery is de-duplicated per `(alert_id, revision, device token)`.

## Operational checks

- An app that cannot retrieve a verified release retains its last-known-good feed and does not resolve existing signals.
- First install baselines existing alerts, so historic feed data is visible in-app but never treated as newly delivered.
- A retraction removes only its own fast-lane signal. It never clears a catalog BLOCKED verdict.
- No push payload contains a product name, ingredient, medication, profile field, or regulatory copy.
