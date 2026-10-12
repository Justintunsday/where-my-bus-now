# Bus arrival Live Activities: implementation and deployment

## Shipped client behavior

The host app starts a user-selected, exact route/direction/service/boarding-stop activity with `ActivityContent`. `NSSupportsLiveActivities` and the `busnow` URL scheme are in the host plist. The embedded `BusArrivalWidget.appex` renders Lock Screen and all Dynamic Island families. Shared attributes, Unix-second content state, localized content and an end intent belong to both targets. No App Group is needed because the widget renders ActivityKit-supplied content; it does not read bookmarks or fetch data.

There is one tracked trip at a time. A new request must succeed before the previous activity ends. The manager restores existing activities, observes system state changes, reconciles dismissals and coalesces foreground requests with on-screen ETA sessions. Predictions expire after the earlier of 90 seconds and their predicted arrival time. Countdown text is system-rendered; it is not a new ETA request. WidgetKit checks `context.isStale` and shows an explicit refresh indication. A failed request hides the live prediction and preserves the timestamp of the last successful response. Empty provider results remove the prediction; explicit cancellation removes the countdown and ends tracking. An activity older than one hour ends when the app next runs in the foreground. The system can end it earlier and applies its own maximum lifetime when the app is suspended.

Manual ending is available in the app, Settings and the Live Activity button (`LiveActivityIntent`, included in both targets). Deep links encode the complete provider identity; the app validates the scheme, payload size, region, provider, operators, bound dictionary, service type, line ID, source, stop ID and sequence before displaying ETA. A changed route is never silently remapped to a same-number route.

**Current update mode is local foreground only.** `supportsRemoteUpdates` is false and `pushType` is nil. No background polling, remote token registration, push-to-start, or frequent-update entitlement is implied. ActivityKit and WidgetKit UI previews are available without an APNs service. Signed-device lifecycle/presentation still requires verification.

## Existing backend assessment

This repository includes clients for hosted CheLaile `/v1/search`, `/v1/stops/nearby`, `/v1/stops/detail`, `/v1/lines/detail`, `/v1/lines/realtime` and `/v1/health`, plus public Hong Kong operator requests and optional AMap base data. It contains no backend source, durable subscription storage, authenticated activity registration endpoint, APNs signing configuration or worker queue. The hosted API is useful as an upstream mainland data adapter; its current client contract is not an ActivityKit push service. A serverless request handler by itself is insufficient for reliable 30–60 second subscription work. Hong Kong and mainland identities must remain separate, and AMap base data cannot become CheLaile realtime without a verified mapping.

The upstream backend was also inspected at `37cdb4edec8a3120219b97b396ded83fc2b297b4` (2026-10-12): its [HTTP server](https://github.com/Justintunsday/chelaile-api-server/blob/37cdb4edec8a3120219b97b396ded83fc2b297b4/src/api/server.ts) registers query endpoints, with no activity registration routes. The [Cloudflare Worker](https://github.com/Justintunsday/chelaile-api-server/blob/37cdb4edec8a3120219b97b396ded83fc2b297b4/worker/index.ts) exposes a fetch handler; [wrangler configuration](https://github.com/Justintunsday/chelaile-api-server/blob/37cdb4edec8a3120219b97b396ded83fc2b297b4/worker/wrangler.toml) has no durable subscriptions, queues or scheduled triggers. The [Bun container](https://github.com/Justintunsday/chelaile-api-server/blob/37cdb4edec8a3120219b97b396ded83fc2b297b4/Dockerfile) starts the HTTP API only. These are source observations, not an audit of private production configuration.

The backend is suitable for reusing its provider adapter and query models, but needs a new durable subscription/scheduling layer and APNs sender. Recommended deployment: a separate worker process with persistent storage next to the Bun API, reusing its adapter; keep the public Worker/Vercel routes stateless. Alternatively extend the Cloudflare deployment with durable state and scheduling plus a verified APNs delivery path. Neither architecture is implemented or deployed by this PR.

Deploy a durable worker next to the existing API, or a separate service using that API. Provider authorization, upstream rate limits and operational hosting must be confirmed by the service owner. An APNs signing key, team ID and key ID remain server-side secrets, never application resources or committed fixtures.

## Proposed registration contract (not deployed)

`PUT /v1/live-activities/{activityID}` receives an authenticated, expiring subscription containing the ActivityKit update token, APNs environment (sandbox/production), exact `BusTrackingTarget`, creation time and expiry (at most one hour). Validate the provider's route, bound, service and station identity server-side; never trust a client-supplied URL. The server returns a revocable subscription ID. `DELETE` revokes it on manual end. Apply per-installation limits, token encryption, TTL cleanup and log redaction. Token rotation replaces the previous token atomically.

After deployment: enable the Push Notifications capability for the host signing profile, request with `.token`, observe **every** `activity.pushTokenUpdates` emission, register with retry/backoff, and unregister on end/dismissal. Restore observers after relaunch. Keep the local-only path if registration is not available. Do not collect push-to-start tokens: this feature is deliberately started by a user choosing a trip in the app. No `UIBackgroundModes=remote-notification` is needed merely for ActivityKit APNs updates. Add frequent-update support only if justified; check `frequentPushesEnabled`, and do not promise an exact delivery cadence.

## Worker and APNs

Group subscriptions by the full canonical transit query and locale, not route number. Fetch authorized providers once per query, fan out predictions, throttle unchanged values and use a monotonic last-sent timestamp. A successful revised prediction replaces `arrivalEpoch`. An empty response sends unavailable; an explicit cancelled service or permanently invalid identity sends an end event. A transport failure sends unavailable with the last successful `updatedEpoch`; it must not reset freshness. Expired subscriptions receive an end event. Revoke on APNs 410; back off 429/5xx; re-register rotated tokens. Use priority 5 normally and priority 10 only for meaningful urgent changes, within Apple's budget.

HTTP/2 headers:

```
apns-push-type: liveactivity
apns-topic: app.hkbus.swiftui.push-type.liveactivity
apns-priority: 5
authorization: bearer <short-lived provider JWT>
```

Send to `https://api.sandbox.push.apple.com/3/device/{activityUpdateToken}` for development or the production APNs host for production. An update example is in `activity-push-example.json`. All content dates are Unix seconds, matching the exact Codable contract. `stale-date` equals `validUntilEpoch`. An end event uses `event: end`, a full final content state (`status: ended` or `cancelled`, `arrivalEpoch: null`), and an appropriate `dismissal-date`. No persistent countdown survives a cancellation. Never log tokens or provider credentials.

## Required deployment/device gates

1. Sign the host and extension under the same team, retaining the host bundle ID and a prefixed extension bundle ID; confirm embedded extension installation.
2. On iOS 17 and iOS 26, start/replace/end/restore/dismiss activities and test device settings disabling activities.
3. On hardware with and without Dynamic Island, inspect locked, expanded, compact, minimal, Always-On and stale presentations; test the end intent and cold-start regional deep link.
4. Suspend/terminate the app: the current implementation must become stale and must not claim updated predictions.
5. After the server is deployed, test token rotation, APNs sandbox/production separation, changed ETA, cancelled service, upstream failure, expiry, throttling and revocation. Remote updates cannot be marked complete before these pass.

Primary references: [Apple ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities), [ActivityKit APNs](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications), [Interactive Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities).
