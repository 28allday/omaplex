#!/usr/bin/env python3
"""OmaPlex status: one JSON object on stdout for the panel.

    status.py <token-file>                 snapshot
    status.py <token-file> --scan <id>     ask Plex to scan one library

Talks to the local server only (127.0.0.1:32400). Every read is bounded and
every request has a short timeout, so a wedged server can't hang the panel.
The token is read from its file here and sent as a header, never as argv.
"""

import json
import socket
import subprocess
import sys
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:32400"
SERVICE = "plexmediaserver.service"
TIMEOUT = 3
MAX_BODY = 2 * 1024 * 1024
MAX_SESSIONS = 20
MAX_LIBRARIES = 50
MAX_TEXT = 120


def clip(value, limit=MAX_TEXT):
    text = "" if value is None else str(value)
    text = " ".join(text.split())
    return text if len(text) <= limit else text[: limit - 1] + "…"


def read_token(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            token = fh.read(256).strip()
    except OSError:
        return ""
    return token if token.replace("-", "").replace("_", "").isalnum() else ""


def request(path, token=""):
    headers = {"Accept": "application/json", "X-Plex-Product": "OmaPlex"}
    if token:
        headers["X-Plex-Token"] = token
    req = urllib.request.Request(BASE + path, headers=headers)
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        body = resp.read(MAX_BODY + 1)
    if len(body) > MAX_BODY:
        raise ValueError("response too large")
    return json.loads(body.decode("utf-8", "replace")) if body.strip() else {}


def container(data):
    return data.get("MediaContainer", {}) if isinstance(data, dict) else {}


def service_state():
    try:
        out = subprocess.run(
            ["systemctl", "show", SERVICE, "--property=LoadState,ActiveState,UnitFileState"],
            capture_output=True, text=True, timeout=TIMEOUT, check=False,
        ).stdout
    except (OSError, subprocess.TimeoutExpired):
        out = ""
    props = dict(line.split("=", 1) for line in out.splitlines() if "=" in line)
    return {
        "installed": props.get("LoadState", "not-found") == "loaded",
        "activeState": props.get("ActiveState", "inactive"),
        "enabled": props.get("UnitFileState", "") == "enabled",
    }


def server_mode():
    # Dedicated-server mode masks the sleep targets; that's the source of truth.
    try:
        out = subprocess.run(
            ["systemctl", "is-enabled", "suspend.target"],
            capture_output=True, text=True, timeout=TIMEOUT, check=False,
        ).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return False
    return out == "masked"


def power_profile():
    try:
        out = subprocess.run(
            ["busctl", "get-property", "org.freedesktop.UPower.PowerProfiles",
             "/org/freedesktop/UPower/PowerProfiles",
             "org.freedesktop.UPower.PowerProfiles", "ActiveProfile"],
            capture_output=True, text=True, timeout=TIMEOUT, check=False,
        ).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""
    # busctl prints: s "balanced"
    return clip(out.strip().partition(" ")[2].strip('"'), 20)


def lan_address():
    # A UDP "connect" sends nothing; it just asks the kernel which source
    # address it would route from, which is the one other devices can reach.
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("192.0.2.1", 9))
        return sock.getsockname()[0]
    except OSError:
        return ""
    finally:
        sock.close()


def session_row(item):
    kind = item.get("type", "")
    title = item.get("title", "")
    if kind == "episode":
        show = item.get("grandparentTitle", "")
        season, episode = item.get("parentIndex"), item.get("index")
        code = f"S{season:02d}E{episode:02d}" if isinstance(season, int) and isinstance(episode, int) else ""
        subtitle = " · ".join(p for p in (code, title) if p)
        title = show or title
    elif kind == "track":
        subtitle = " · ".join(p for p in (item.get("grandparentTitle", ""), item.get("parentTitle", "")) if p)
    else:
        subtitle = str(item.get("year", "")) if item.get("year") else ""
    duration = item.get("duration") or 0
    offset = item.get("viewOffset") or 0
    player = item.get("Player") or {}
    user = item.get("User") or {}
    transcode = item.get("TranscodeSession") or {}
    decision = transcode.get("videoDecision") or transcode.get("audioDecision") or ""
    return {
        "kind": clip(kind, 20),
        "title": clip(title),
        "subtitle": clip(subtitle),
        "user": clip(user.get("title", ""), 60),
        "player": clip(player.get("title") or player.get("product", ""), 60),
        "state": clip(player.get("state", ""), 20),
        "local": bool(player.get("local")),
        "transcoding": decision == "transcode",
        "progress": round(min(1.0, offset / duration), 3) if duration else 0,
    }


def library_row(item):
    return {
        "id": clip(item.get("key", ""), 12),
        "title": clip(item.get("title", "")),
        "type": clip(item.get("type", ""), 20),
        "scanning": bool(item.get("refreshing")),
        "scannedAt": int(item.get("scannedAt") or 0),
    }


def snapshot(token_path):
    state = service_state()
    result = {
        "ok": True,
        "installed": state["installed"],
        "running": state["activeState"] == "active",
        "starting": state["activeState"] in ("activating", "reloading"),
        "enabled": state["enabled"],
        "address": lan_address(),
        "serverMode": server_mode(),
        "powerProfile": power_profile(),
        "reachable": False,
        "claimed": False,
        "version": "",
        "name": "",
        "tokenSaved": False,
        "tokenValid": False,
        "sessions": [],
        "libraries": [],
        "error": "",
    }
    if not result["running"]:
        return result

    try:
        identity = container(request("/identity"))
    except (OSError, ValueError, urllib.error.URLError):
        # Running but not answering yet: Plex takes a few seconds after start.
        result["starting"] = True
        return result
    result["reachable"] = True
    result["claimed"] = bool(identity.get("claimed"))
    result["version"] = clip(str(identity.get("version", "")).split("-")[0], 40)

    token = read_token(token_path)
    result["tokenSaved"] = bool(token)
    if not token:
        return result

    try:
        root = container(request("/", token))
        result["tokenValid"] = True
        result["name"] = clip(root.get("friendlyName", ""), 60)
        sessions = container(request("/status/sessions", token)).get("Metadata") or []
        result["sessions"] = [session_row(s) for s in sessions[:MAX_SESSIONS] if isinstance(s, dict)]
        libraries = container(request("/library/sections", token)).get("Directory") or []
        result["libraries"] = [library_row(d) for d in libraries[:MAX_LIBRARIES] if isinstance(d, dict)]
    except urllib.error.HTTPError as err:
        if err.code in (401, 403):
            result["error"] = "Plex no longer accepts the saved sign-in. Connect again."
        else:
            result["error"] = f"Plex answered with error {err.code}."
    except (OSError, ValueError, urllib.error.URLError):
        result["error"] = "Couldn't read from Plex."
    return result


def scan(token_path, library_id):
    token = read_token(token_path)
    if not token:
        print("Connect OmaPlex to Plex first.", file=sys.stderr)
        return 1
    if not library_id.isdigit():
        print("Library id must be a number.", file=sys.stderr)
        return 1
    try:
        request(f"/library/sections/{library_id}/refresh", token)
    except urllib.error.HTTPError as err:
        print(f"Plex answered with error {err.code}.", file=sys.stderr)
        return 1
    except (OSError, ValueError, urllib.error.URLError):
        print("Couldn't reach Plex.", file=sys.stderr)
        return 1
    print("Scanning")
    return 0


def main(argv):
    if len(argv) == 2:
        print(json.dumps(snapshot(argv[1])))
        return 0
    if len(argv) == 4 and argv[2] == "--scan":
        return scan(argv[1], argv[3])
    print(__doc__.strip(), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
