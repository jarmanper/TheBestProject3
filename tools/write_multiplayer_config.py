#!/usr/bin/env python3
"""Writes the export-only WebRTC config from deployment environment variables."""

import json
import os
import pathlib
import sys


def value(name: str) -> str:
    return os.environ.get(name, "").strip()


signaling_url = value("MULTIPLAYER_SIGNALING_URL")
target = pathlib.Path(__file__).parents[1] / "config" / "multiplayer.json"
target.parent.mkdir(exist_ok=True)

if not signaling_url:
    # Keep ordinary single-player deploys working until the repository owner
    # adds the production endpoint and TURN values as Actions secrets.
    target.write_text("{}\n", encoding="utf-8")
    print("Multiplayer disabled: MULTIPLAYER_SIGNALING_URL is not set.")
    sys.exit(0)

required = [
    "MULTIPLAYER_STUN_URL",
    "MULTIPLAYER_TURN_URL",
    "MULTIPLAYER_TURN_USERNAME",
    "MULTIPLAYER_TURN_CREDENTIAL",
]
missing = [name for name in required if not value(name)]
if missing:
    raise SystemExit("Missing multiplayer deployment values: " + ", ".join(missing))

config = {
    "signaling_url": signaling_url,
    "max_players": int(value("MULTIPLAYER_MAX_PLAYERS") or "4"),
    "ice_servers": [
        {"urls": [value("MULTIPLAYER_STUN_URL")]},
        {
            "urls": [value("MULTIPLAYER_TURN_URL")],
            "username": value("MULTIPLAYER_TURN_USERNAME"),
            "credential": value("MULTIPLAYER_TURN_CREDENTIAL"),
        },
    ],
}
target.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
print("Wrote export-only multiplayer configuration.")
