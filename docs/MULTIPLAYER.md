# WebRTC multiplayer deployment

The game client is hosted on GitHub Pages; the lobby and TURN services are a
separate Docker deployment. GitHub Pages only serves the Web export. It does
not run WebSocket processes, retain lobby state, or relay restricted NAT traffic.

## What is implemented

- `MultiplayerSession` connects to a `wss://` signaling service, creates and
  joins six-character lobbies, tracks readiness, and relays WebRTC SDP/ICE.
- The client creates a WebRTC mesh using the ICE server list bundled into the
  export at build time.
- `services/multiplayer/` runs the in-memory signaling service behind Caddy
  (TLS/WSS) and coturn (STUN/TURN).
- The `ONLINE LOBBY` menu exposes host, join, ready, and start controls.

The lobby establishes a secure peer mesh. Gameplay state replication (players,
tasks, monster authority, damage, and end-state) remains a separate integration
task; the lobby intentionally does not start a falsely synchronized shift.

## Deploy the signaling and TURN services

1. Provision a small Internet-reachable Linux VM with Docker Compose and open:
   TCP `80`, `443`, `3478`, `5349`; UDP `3478`, `5349`, and `49160-49200`.
2. Create DNS `A`/`AAAA` records for `signal.example.com` and `turn.example.com`
   pointing to that VM. Caddy obtains the signaling certificate automatically.
   Place a TLS `fullchain.pem` and `privkey.pem` for the TURN name in a directory
   on the VM.
3. Copy `services/multiplayer/.env.example` to `.env`, replace every placeholder,
   and set `ALLOWED_ORIGINS` to the exact HTTPS GitHub Pages origin. Use a long,
   random TURN password.
4. From `services/multiplayer/`, run `docker compose up -d --build`.
5. Verify `https://signal.example.com/healthz` returns `{ "ok": true, ... }`.

Use `wss://signal.example.com` as the signaling URL and
`turns:turn.example.com:5349?transport=tcp` as the TURN URL. For production,
prefer short-lived TURN REST credentials over a permanent static username and
password. Browser clients can always inspect their exported configuration, so a
long-lived client-side secret is not a secret.

## Configure the GitHub Pages build

In the repository’s GitHub Actions secrets, add:

| Secret | Example |
|---|---|
| `MULTIPLAYER_SIGNALING_URL` | `wss://signal.example.com` |
| `MULTIPLAYER_STUN_URL` | `stun:turn.example.com:3478` |
| `MULTIPLAYER_TURN_URL` | `turns:turn.example.com:5349?transport=tcp` |
| `MULTIPLAYER_TURN_USERNAME` | Your TURN username |
| `MULTIPLAYER_TURN_CREDENTIAL` | Your TURN password or temporary credential |
| `MULTIPLAYER_MAX_PLAYERS` | `4` |

The Pages workflow writes `config/multiplayer.json` just before export. That
file is ignored by Git. If `MULTIPLAYER_SIGNALING_URL` is not set, it writes an
empty config and the shipped game leaves online lobby controls disabled rather
than attempting an insecure connection.
