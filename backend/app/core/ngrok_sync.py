import os
import json
import time
import shutil
import logging
import subprocess
import urllib.request
from pathlib import Path

logger = logging.getLogger("ngrok_sync")

def get_ngrok_url() -> str | None:
    """Queries ngrok local API on port 4040 for active HTTPS tunnel."""
    try:
        req = urllib.request.Request("http://127.0.0.1:4040/api/tunnels")
        with urllib.request.urlopen(req, timeout=2) as response:
            data = json.loads(response.read().decode())
            tunnels = data.get("tunnels", [])
            for t in tunnels:
                if t.get("proto") == "https":
                    return t.get("public_url")
    except Exception:
        return None
    return None

def start_ngrok(port: int = 8000) -> str | None:
    """Attempts to start ngrok if it's not already running."""
    url = get_ngrok_url()
    if url:
        return url

    logger.info("ngrok not running on port 4040. Attempting to start ngrok...")

    # Look for ngrok in standard npm location or system PATH
    npm_ngrok = Path(os.environ.get("APPDATA", "")) / "npm" / "node_modules" / "ngrok" / "bin" / "ngrok.exe"
    ngrok_cmd = None
    if npm_ngrok.exists():
        ngrok_cmd = str(npm_ngrok)
    elif shutil.which("ngrok"):
        ngrok_cmd = "ngrok"

    if not ngrok_cmd:
        logger.warning("ngrok executable not found in PATH or npm directory.")
        return None

    try:
        # Launch ngrok in background
        subprocess.Popen(
            [ngrok_cmd, "http", str(port)],
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0) if os.name == "nt" else 0,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
    except Exception as e:
        logger.warning(f"Could not launch ngrok: {e}")
        return None

    # Wait up to 10 seconds for ngrok to bind
    for _ in range(10):
        time.sleep(1)
        url = get_ngrok_url()
        if url:
            return url

    return None

def sync_launch_json(ngrok_url: str):
    """Updates .vscode/launch.json with the live ngrok URL."""
    try:
        root_dir = Path(__file__).resolve().parent.parent.parent.parent
        launch_json = root_dir / ".vscode" / "launch.json"
        if not launch_json.exists():
            return

        with open(launch_json, "r", encoding="utf-8") as f:
            data = json.load(f)

        changed = False
        for cfg in data.get("configurations", []):
            args = cfg.get("args", [])
            new_args = [a for a in args if not a.startswith("--dart-define=BACKEND_URL=")]
            new_args.append(f"--dart-define=BACKEND_URL={ngrok_url}")
            if new_args != args:
                cfg["args"] = new_args
                changed = True

        if changed:
            with open(launch_json, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=4)
            logger.info("Updated .vscode/launch.json with live ngrok URL.")
    except Exception as e:
        logger.debug(f"Could not update launch.json: {e}")

def sync_to_supabase(ngrok_url: str):
    """Upserts the live backend URL into Supabase app_config table if possible."""
    try:
        from supabase import create_client
        url = os.getenv("SUPABASE_URL", "")
        key = os.getenv("SUPABASE_SERVICE_KEY", os.getenv("SUPABASE_ANON_KEY", ""))
        if not url or not key:
            return
        client = create_client(url, key)
        client.table("app_config").upsert({
            "key": "backend_url",
            "value": ngrok_url,
            "updated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        }).execute()
        logger.info(f"Published live ngrok URL to Supabase app_config: {ngrok_url}")
    except Exception as e:
        # Table might not exist yet or permissions not set
        logger.debug(f"Could not push URL to Supabase app_config: {e}")

def run_auto_sync(port: int = 8000) -> str | None:
    """Finds or starts ngrok and synchronizes everywhere."""
    ngrok_url = get_ngrok_url()
    if not ngrok_url:
        ngrok_url = start_ngrok(port)

    if ngrok_url:
        sync_launch_json(ngrok_url)
        sync_to_supabase(ngrok_url)
        return ngrok_url
    return None
