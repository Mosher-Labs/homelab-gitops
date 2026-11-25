# RUNBOOK.md - spotify-mcp

## Overview

`spotify-mcp` lets Claude (claude.ai, web and mobile) build Spotify playlists
for a workout. It reads your top tracks and liked songs, looks up each
track's tempo and energy, and creates or edits playlists in your account. It
runs on the `bjw-s-labs/app-template` chart with a `cloudflared` sidecar, the
same pattern as `apps/garmin-mcp`.

- **Namespace:** `spotify-mcp`
- **Public URL:** `https://spotify.benniemosher.dev/mcp`
- **Image:** `ghcr.io/mosher-labs/spotify-mcp`, built from
  `Mosher-Labs/spotify-mcp` `main` by its `Image` workflow and pinned by
  digest in `application.yaml`.
- **Auth to the server:** every `/mcp` call must send `SPOTIFY_MCP_HTTP_TOKEN`
  as `X-API-Key` (claude.ai reserves `Authorization`). Cloudflare Access gates
  the rest of the hostname, with a bypass for `/mcp`.
- **Auth to Spotify:** authorization code with PKCE. The refresh token is in
  `/data/token.json` on the volume. There is no client secret anywhere.
  `SPOTIFY_CLIENT_ID` is a public identifier and sits in `application.yaml`.
- **Tempo and energy:** from ReccoBeats (`api.reccobeats.com`, no key), cached
  in `/data/tempo.sqlite3`. Spotify closed its own audio-features endpoint to
  new apps. Tracks ReccoBeats does not know are retried after a week; Claude
  can record a BPM by hand with `set_track_tempo`.
- **Scopes requested:** `user-top-read`, `user-library-read`,
  `user-read-recently-played`, `playlist-read-private`,
  `playlist-modify-private`, `playlist-modify-public`. No playback control.
- **Listening log:** `/data/listening.sqlite3`. See "Listening log and what
  it can and cannot tell you" below.

## Spotify's limits that shape this

Checked against developer.spotify.com on 2026-11-14.

- Development Mode, which this app stays in: up to 5 users, and the **app
  owner needs Spotify Premium** or the app stops working. A family plan
  member's Premium may or may not count. Confirm when you create the app
  (Dashboard, app settings).
- Search returns at most 10 results per request.
- Playlist items are readable only for playlists you own or collaborate on.
- Recently played (`GET /me/player/recently-played`, scope
  `user-read-recently-played`) returns at most 50 items with `played_at`, and
  is not on the February 2026 removal list. I read this in the docs; it has
  not been run against a live Dev Mode app. Podcast episodes are not
  included.
- Batch endpoints such as `GET /tracks?ids=` are gone, so track details come
  from search, top tracks, and liked songs, not from bare IDs.

## Initial deployment

### 1. Build the image

In `Mosher-Labs/spotify-mcp`, merge to `main`. The `Image` workflow pushes
`ghcr.io/mosher-labs/spotify-mcp:<short sha>`. Read the digest and put
`<short sha>@sha256:<digest>` in `application.yaml`:

```bash
crane digest ghcr.io/mosher-labs/spotify-mcp:<short sha>
```

### 2. Create the Spotify app

At <https://developer.spotify.com/dashboard>, create an app:

- Redirect URI: `http://127.0.0.1:8888/callback` exactly. Spotify rejects
  `localhost`, and accepts `http` only for loopback IPs.
- APIs used: Web API.
- Copy the Client ID into `SPOTIFY_CLIENT_ID` in `application.yaml`.
- Under User Management, add your own Spotify name and email.

### 3. Provision the tunnel and seal its token

`spotify-mcp` is an entry in `infrastructure/cloudflare-tunnels/locals.tf`.
Apply that stack as its RUNBOOK describes, then seal the connector token:

```bash
cd infrastructure/cloudflare-tunnels
terraform apply
terraform output -json tunnel_tokens | jq -j '."spotify-mcp"' |
  kubectl create secret generic cloudflared-credentials \
    --namespace spotify-mcp --from-file=tunnel-token=/dev/stdin \
    --dry-run=client -o yaml |
  kubeseal --controller-namespace kube-system \
    --controller-name sealed-secrets-controller --format yaml \
    > ../../apps/spotify-mcp/manifests/cloudflared-sealed-secret.yaml
```

The MCP token is already sealed in `manifests/spotify-mcp-sealed-secret.yaml`.
Save its plaintext in 1Password ("Mosher Home" vault, item "Spotify MCP
Homelab") before you delete the local copy.

### 4. Merge

ArgoCD syncs `apps/spotify-mcp/application.yaml`. The pod stays not Ready
(`/readyz` returns 503) until step 5.

### 5. Log in to Spotify once

```bash
kubectl exec -it -n spotify-mcp deploy/spotify-mcp -c app -- spotify-mcp-auth
kubectl rollout restart -n spotify-mcp deploy/spotify-mcp
```

It prints a URL. Open it in a browser and approve. The browser then fails to
load `http://127.0.0.1:8888/callback?...`, which is expected. Copy that full
address from the address bar and paste it at the prompt.

### 6. Add the connector in Claude

In claude.ai, Settings, Connectors, Add custom connector:

- URL: `https://spotify.benniemosher.dev/mcp`
- Authentication: "No sign-in required" (any OAuth option drops custom
  headers).
- Request header: name `X-API-Key`, value the `SPOTIFY_MCP_HTTP_TOKEN`, with
  no `Bearer` prefix.

## Listening log and what it can and cannot tell you

**How it works.** Spotify keeps only the last 50 plays. When an activity is
saved to Strava (Garmin syncs there), a Strava webhook makes the server fetch
those plays and log the ones inside the activity's time window. See "Strava
trigger" below. You can also ask Claude to log a workout by hand, with more
detail. Claude passes the activity ID, start and end (with timezone offset)
from Garmin or Strava, and optionally type, planned intensity, average pace, HR and
cadence, a 1 to 10 effort, and per-segment pace, HR and cadence.
`log_workout_listening` then:

1. matches plays with `played_at` from the start to 5 minutes past the end,
2. stores them with the workout's data (logging the same ID again replaces it),
3. adds the plays that were not skipped to one running playlist called
   "Workouts", skipping tracks already in it.

One running playlist is the default because it dedupes across workouts and
stays a single list of songs that have carried you. Pass
`per_workout_playlist` for a separate playlist of one workout.

**Using it.** `get_track_history` and `get_workout_music_stats` return plain
aggregates: per track, plays, workouts, skip rate, and the average effort,
cadence, HR and pace of the workouts it played in; per tempo band, the skip
rate and average cadence; a "keepers" list (never skipped, played in 2 or more
workouts, best average effort first) and an "often skipped" list.
`candidate_tracks` drops tracks skipped in at least half of 2 or more logged
plays. Nothing is a model. Every number traces to rows in the log.

**Privacy.** The log lives only on the pod's volume. It holds track IDs,
names, artists, timestamps and the workout numbers Claude passes in. It goes
nowhere except back to Claude when a tool is called. Delete
`/data/listening.sqlite3` to erase it, and revoke access under "Revoking
Spotify access" below.

**Caveats, read before trusting a conclusion.**

- **Skips are inferred.** Spotify gives no play length, only `played_at`. The
  time between consecutive plays stands in for how long a track played. A play
  under 75% of the track counts as skipped. A pause shows up as a completed
  play, and the first play after a gap has no neighbor, so its status is
  unknown, not skipped.
- **Which end `played_at` marks is unverified.** The server assumes it is when
  the play finished. After about 20 consecutive plays, `listening_status`
  compares both readings against the gaps and the server switches to the
  better fit (`timestamp_fit`, `played_at_reading_in_use`). Check it once
  after the first week.
- **Very short plays may not appear at all.** I believe Spotify records a play
  only after about 30 seconds. I did not find that in the docs. If true, the
  quickest skips are invisible, so skip rates run low.
- **Correlation is not cause.** A track "coinciding with a good effort" may
  just have played during a good day, a downhill, or a tempo segment Claude
  had already planned the playlist around. Small samples mislead: a track in
  two workouts is a hint. Effort and segment numbers are only as good as what
  Claude passes in.
- **Gaps.** Plays roll off once 50 newer ones exist. At about 3.5 minutes a
  track that is about three hours of listening, counted from the start of the
  workout to when the webhook fires. A one-hour run leaves about two hours of
  margin; a 2.5-hour long run leaves under 30 minutes. A late Garmin sync, or
  the pod being down through Strava's three delivery attempts, eats into it.
  When the fetch does not reach back to the start, the event result in
  `listening_status` (`strava_last_event`) carries `possible_gap`. If that
  shows up, set `SPOTIFY_MCP_POLL_SECONDS: "3600"` in `application.yaml`.
- **Learning is advisory.** Claude should treat the lists as inputs and keep
  your explicit requests ahead of them.

## Strava trigger

The server logs workout listening when Strava sends an activity `create`
event to `https://spotify.benniemosher.dev/strava/webhook`. Strava does not
sign events, so the server checks the event's `subscription_id` and
`owner_id`, then fetches the activity from Strava's API for its start and
elapsed time. It answers 200 at once and does the work after, since Strava
wants a reply within two seconds and tries a delivery three times at most.
Logging is idempotent on the activity ID.

- `update`: renames a logged workout. On an activity that was never logged
  (the pod was down), it logs it. Editing the title in Strava is the retry.
- `delete`: drops the workout only if Strava returns 404 for it. Plays and
  the "Workouts" playlist are kept.
- Cloudflare Access bypasses `/strava/webhook`, like `/mcp`
  (`infrastructure/cloudflare-tunnels/locals.tf`). The app's `X-API-Key` gate
  also leaves that one path open. `/mcp` still needs the key.

Docs: <https://developers.strava.com/docs/webhooks/> and
<https://developers.strava.com/docs/authentication/> (checked 2026-11-25).

### Setting it up

1. **Create the Strava API app** at <https://www.strava.com/settings/api>.
   Set "Authorization Callback Domain" to `localhost`. Save the Client ID and
   Client Secret in 1Password ("Mosher Home" vault, item "Strava API
   spotify-mcp"), with a verify token from `openssl rand -hex 16`.
2. **Seal the Strava secret.** The pod treats it as optional, so it starts
   without it.

   ```bash
   kubectl create secret generic spotify-mcp-strava \
     --namespace spotify-mcp \
     --from-literal=STRAVA_CLIENT_ID=<client id> \
     --from-file=STRAVA_CLIENT_SECRET=/dev/stdin \
     --from-literal=STRAVA_WEBHOOK_VERIFY_TOKEN=<verify token> \
     --dry-run=client -o yaml <<< "$(op read 'op://<vault>/<item>/client secret')" |
   kubeseal --controller-namespace kube-system \
     --controller-name sealed-secrets-controller --format yaml \
     > apps/spotify-mcp/manifests/spotify-mcp-strava-sealed-secret.yaml
   ```

3. **Apply the tunnel stack** so Access lets Strava through:
   `cd infrastructure/cloudflare-tunnels && terraform plan && terraform apply`.
   The plan should add one `cloudflare_zero_trust_access_application`
   (`spotify-mcp-bypass--strava-webhook`) and change nothing else.
4. **Ship the image** with the webhook and description writing
   (`Mosher-Labs/spotify-mcp` PRs #6 and #7) and
   pin its digest in `application.yaml` (step 1 of "Initial deployment"). Merge, and
   let ArgoCD sync.
5. **Log in to Strava once.** It asks for `activity:read_all` (includes "Only
   You" activities) and `activity:write` (needed to write activity
   descriptions). Leave every box ticked; the login fails if either is
   unticked. A token saved before the image asked for `activity:write` can
   read but not write, so run this step again to replace it.

   ```bash
   kubectl exec -it -n spotify-mcp deploy/spotify-mcp -c app -- spotify-mcp-strava-auth
   kubectl rollout restart -n spotify-mcp deploy/spotify-mcp
   ```

   The browser then fails to load `http://localhost/exchange_token?...`. Paste
   that full address at the prompt.
6. **Create the subscription** (one per Strava app). Strava calls the webhook
   with a GET before it answers, so steps 3 to 5 must be done first.

   ```bash
   curl -X POST https://www.strava.com/api/v3/push_subscriptions \
     -F client_id=<client id> \
     -F client_secret="$(op read 'op://<vault>/<item>/client secret')" \
     -F callback_url=https://spotify.benniemosher.dev/strava/webhook \
     -F verify_token=<verify token>
   ```

   It returns `{"id": N}`. The server looks the ID up on its own; to pin it,
   add `STRAVA_SUBSCRIPTION_ID` to the sealed secret.
7. **Check it.** Save any activity, then ask Claude for `listening_status`
   and look at `strava_last_event`, or read the pod log for a `strava:` line.

To see or remove the subscription:

```bash
curl -G https://www.strava.com/api/v3/push_subscriptions \
  -d client_id=<client id> -d client_secret=<secret>
curl -X DELETE \
  "https://www.strava.com/api/v3/push_subscriptions/<id>?client_id=<client id>&client_secret=<secret>"
```

## Rotating the MCP token

```bash
openssl rand -hex 32 | tr -d '\n' > /tmp/spotify-mcp-token
kubectl create secret generic spotify-mcp-secrets \
  --namespace spotify-mcp \
  --from-file=SPOTIFY_MCP_HTTP_TOKEN=/tmp/spotify-mcp-token \
  --dry-run=client -o yaml |
kubeseal --controller-namespace kube-system \
  --controller-name sealed-secrets-controller --format yaml \
  > apps/spotify-mcp/manifests/spotify-mcp-sealed-secret.yaml
```

Commit, merge, restart the deployment, update the connector, and delete
`/tmp/spotify-mcp-token`.

## Revoking Spotify access

Remove the app at <https://www.spotify.com/account/apps/>, then delete
`/data/token.json` or re-run step 5.

## Troubleshooting

### Pod not Ready

`kubectl logs -n spotify-mcp deploy/spotify-mcp -c app`. "not logged in" from
`/readyz` means step 5 has not run.

### Spotify returns 403

In Development Mode that means the account is not on the app's user list, or
the app owner's Premium lapsed.

### Spotify returns 429

The Development Mode request quota was hit. Wait for the `Retry-After`.

### Claude reports 401

The connector's header does not match `SPOTIFY_MCP_HTTP_TOKEN`. Re-enter it.

### A workout was not logged from Strava

`kubectl logs -n spotify-mcp deploy/spotify-mcp -c app | grep strava:`.
`ignored ... owner_id` means `spotify-mcp-strava-auth` logged in as another
athlete; `subscription_id does not match` means the subscription was
recreated, so restart the pod. `status: error` is retried by the next event
for that activity, so edit its title in Strava.

### A track has no tempo

ReccoBeats does not know it. Ask Claude to record one with `set_track_tempo`,
or leave it out.
