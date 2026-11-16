# RUNBOOK.md - tempo-service

## Overview

`tempo-service` looks up a song's BPM from artist and title. It downloads the
30 second iTunes preview, runs Essentia beat detection, and caches the result
in SQLite. It is meant to back `spotify-mcp` when ReccoBeats has no tempo for
a track. That call isn't wired up yet, so for now it is tested by hand.

- **Namespace:** `tempo-service`
- **In-cluster URL:** `http://tempo-service.tempo-service.svc:8000`
- **Image:** `ghcr.io/mosher-labs/tempo-service`, built from
  `Mosher-Labs/tempo-service` `main` by its `Image` workflow and pinned by
  digest in `application.yaml`.
- **Auth:** none. There is no tunnel or Ingress, and
  `manifests/networkpolicy.yaml` admits only the `spotify-mcp` namespace on
  port 8000.
- **Data:** `/data/tempo.db` on a 1Gi ReadWriteOnce volume. Deleting it only
  costs the cache.
- **Outbound:** `itunes.apple.com` and Apple's preview CDN. No keys.

## Testing it

```bash
kubectl -n tempo-service port-forward svc/tempo-service 8000:8000
curl 'http://localhost:8000/bpm?artist=Survivor&title=Eye%20of%20the%20Tiger'
curl 'http://localhost:8000/fits?bpm=75&cadence=150'
```

A cold lookup takes about 7 seconds, because the service waits about 3.5
seconds between iTunes calls. Repeat lookups come from the cache
(`"cached": true`). See the tempo-service README for how to read `trust` and
`readings`.

## Updating the image

Merge to `main` in `Mosher-Labs/tempo-service`. The `Image` workflow pushes
`ghcr.io/mosher-labs/tempo-service:<short sha>`. Read the digest and put
`<short sha>@sha256:<digest>` in `application.yaml`:

```bash
docker buildx imagetools inspect \
  ghcr.io/mosher-labs/tempo-service:<short sha> --format '{{json .Manifest.Digest}}'
```

## Troubleshooting

### Lookups return 503 "iTunes is rate-limiting"

iTunes returned 403 or 429 four times in a row. Wait a few minutes. If it
keeps happening, raise `ITUNES_MIN_GAP_SECONDS` in `application.yaml`.

### Lookups return 404

iTunes has no preview for the song, or no result matched the title closely
enough (a score under 0.75). Check by hand:

```bash
curl -s 'https://itunes.apple.com/search?term=<artist>+<title>&media=music&entity=song'
```

### Pod OOMKilled

The 1Gi limit is a first guess. Check `kubectl top pod -n tempo-service`
during a batch and raise it.
