import os
import json
import secrets
import logging
from datetime import datetime, timedelta
from typing import Optional, List
from fastapi import APIRouter, HTTPException, Depends, Request
from fastapi.responses import HTMLResponse, JSONResponse
from supabase import create_client, Client
from pydantic import BaseModel, Field

from app.core.ngrok_sync import get_ngrok_url
from app.models.schemas import (
    LocationSharingRequest,
    LocationSharingResponse,
    LocationPingRequest,
)

logger = logging.getLogger(__name__)

router = APIRouter(tags=["gps"])

# In-memory fallback cache for sessions when Supabase is temporarily unreachable
_memory_sessions = {}
_memory_gps_logs = {}

def get_supabase() -> Client:
    url = os.getenv("SUPABASE_URL", "")
    key = os.getenv("SUPABASE_SERVICE_ROLE_KEY", os.getenv("SUPABASE_SERVICE_KEY", os.getenv("SUPABASE_ANON_KEY", "")))
    if not url or not key:
        raise RuntimeError("Supabase credentials not configured.")
    return create_client(url, key)

def resolve_effective_base_url(request: Request = None) -> str:
    """
    Resolves the live URL to use for tracking links:
    1. Checks active local ngrok tunnel on port 4040
    2. Checks Supabase app_config table for published live URL
    3. Checks BACKEND_URL environment variable
    4. Falls back to incoming request host
    """
    try:
        ngrok = get_ngrok_url()
        if ngrok and ngrok.startswith("http"):
            return ngrok.rstrip("/")
    except Exception:
        pass

    try:
        sb = get_supabase()
        cfg = sb.table("app_config").select("value").eq("key", "backend_url").maybe_single().execute()
        if cfg and cfg.data and cfg.data.get("value"):
            val = cfg.data["value"].strip().rstrip("/")
            if val.startswith("http"):
                return val
    except Exception:
        pass

    env_url = os.getenv("BACKEND_URL") or os.getenv("API_BASE_URL")
    if env_url and env_url.startswith("http"):
        return env_url.rstrip("/")

    if request:
        return str(request.base_url).rstrip("/")

    return "http://localhost:8000"

def create_or_extend_session(
    supabase: Client,
    user_id: str,
    duration_hours: int = 8,
    is_emergency: bool = False,
    lat: float = None,
    lng: float = None,
    accuracy: float = None,
    activity_name: str = "Emergency SOS",
    request: Request = None
) -> tuple[str, str, datetime]:
    """
    Creates or extends a location sharing session.
    Clamps duration between 1 and 24 hours.
    Returns (session_token, tracking_url, expires_at).
    """
    duration = max(1, min(24, duration_hours))
    expires_at = datetime.utcnow() + timedelta(hours=duration)
    token = secrets.token_hex(16)

    # 1. Store in Supabase
    try:
        # Check if an active session already exists for this user
        existing = supabase.table("location_sharing_sessions")\
            .select("id, session_token, expires_at")\
            .eq("user_id", user_id)\
            .eq("is_active", True)\
            .gt("expires_at", datetime.utcnow().isoformat())\
            .order("created_at", desc=True)\
            .limit(1)\
            .execute()

        if existing.data and is_emergency:
            # For emergency, reuse token and extend expiration
            token = existing.data[0]["session_token"]
            supabase.table("location_sharing_sessions").update({
                "expires_at": expires_at.isoformat(),
                "is_active": True
            }).eq("id", existing.data[0]["id"]).execute()
        else:
            supabase.table("location_sharing_sessions").insert({
                "user_id": user_id,
                "session_token": token,
                "expires_at": expires_at.isoformat(),
                "is_active": True
            }).execute()
    except Exception as e:
        logger.warning(f"[SESSION DB] Could not persist session in Supabase: {e}, using memory store")

    # Memory fallback
    _memory_sessions[token] = {
        "user_id": user_id,
        "session_token": token,
        "expires_at": expires_at,
        "is_active": True,
        "is_emergency": is_emergency,
        "activity_name": activity_name
    }

    # Record initial GPS ping if given
    if lat is not None and lng is not None:
        try:
            supabase.table("realtime_gps_logs").insert({
                "user_id": user_id,
                "latitude": lat,
                "longitude": lng,
                "location_accuracy_m": accuracy or 15.0,
                "recorded_at": datetime.utcnow().isoformat()
            }).execute()
        except Exception as e:
            logger.debug(f"[GPS LOG] Could not log initial GPS: {e}")

        if user_id not in _memory_gps_logs:
            _memory_gps_logs[user_id] = []
        _memory_gps_logs[user_id].append({
            "latitude": lat,
            "longitude": lng,
            "accuracy_m": accuracy or 15.0,
            "speed": 0.0,
            "recorded_at": datetime.utcnow().isoformat()
        })

    base_url = resolve_effective_base_url(request)
    tracking_url = f"{base_url}/gps/track/{user_id}?session_token={token}"
    return token, tracking_url, expires_at

# ─── API ENDPOINTS ─────────────────────────────────────────────────────────────

@router.post("/gps/share/start", response_model=LocationSharingResponse)
async def start_location_sharing(
    req: LocationSharingRequest,
    request: Request,
    supabase: Client = Depends(get_supabase)
):
    """
    Initiates real-time location sharing with a duration between 1 and 24 hours.
    Returns live tracking link based on ngrok.
    """
    token, tracking_url, expires_at = create_or_extend_session(
        supabase=supabase,
        user_id=req.user_id,
        duration_hours=req.duration_hours,
        is_emergency=req.is_emergency,
        lat=req.latitude,
        lng=req.longitude,
        accuracy=req.accuracy_m,
        activity_name=req.activity_name or "Location Sharing",
        request=request
    )

    return LocationSharingResponse(
        success=True,
        session_token=token,
        tracking_url=tracking_url,
        expires_at=expires_at.isoformat(),
        duration_hours=req.duration_hours,
        is_emergency=req.is_emergency
    )

class StopSharingRequest(BaseModel):
    user_id: str
    session_token: Optional[str] = None

@router.post("/gps/share/stop")
async def stop_location_sharing(
    req: StopSharingRequest,
    supabase: Client = Depends(get_supabase)
):
    """Cancels active location sharing for the user."""
    try:
        query = supabase.table("location_sharing_sessions").update({
            "is_active": False
        }).eq("user_id", req.user_id)
        if req.session_token:
            query = query.eq("session_token", req.session_token)
        query.execute()
    except Exception as e:
        logger.warning(f"Error terminating DB session: {e}")

    # Terminate memory sessions
    for tok, s in list(_memory_sessions.items()):
        if s["user_id"] == req.user_id:
            s["is_active"] = False

    return {"success": True, "message": "Location sharing stopped."}

@router.get("/gps/share/{user_id}/active")
async def get_active_sharing_status(
    user_id: str,
    request: Request,
    supabase: Client = Depends(get_supabase)
):
    """Checks whether the user currently has an active location sharing session."""
    try:
        res = supabase.table("location_sharing_sessions")\
            .select("id, session_token, expires_at, is_active")\
            .eq("user_id", user_id)\
            .eq("is_active", True)\
            .gt("expires_at", datetime.utcnow().isoformat())\
            .order("created_at", desc=True)\
            .limit(1)\
            .execute()

        if res.data:
            session = res.data[0]
            token = session["session_token"]
            expires_at = datetime.fromisoformat(session["expires_at"].replace("Z", "+00:00")).replace(tzinfo=None)
            remaining_mins = max(0, int((expires_at - datetime.utcnow()).total_seconds() / 60))
            base_url = resolve_effective_base_url(request)
            return {
                "is_active": True,
                "session_token": token,
                "tracking_url": f"{base_url}/gps/track/{user_id}?session_token={token}",
                "expires_at": session["expires_at"],
                "remaining_minutes": remaining_mins
            }
    except Exception as e:
        logger.debug(f"DB active session check notice: {e}")

    # Check memory fallback
    for tok, s in _memory_sessions.items():
        if s["user_id"] == user_id and s["is_active"] and s["expires_at"] > datetime.utcnow():
            remaining_mins = max(0, int((s["expires_at"] - datetime.utcnow()).total_seconds() / 60))
            base_url = resolve_effective_base_url(request)
            return {
                "is_active": True,
                "session_token": tok,
                "tracking_url": f"{base_url}/gps/track/{user_id}?session_token={tok}",
                "expires_at": s["expires_at"].isoformat(),
                "remaining_minutes": remaining_mins
            }

    return {"is_active": False}

@router.post("/gps/ping")
async def record_gps_ping(
    ping: LocationPingRequest,
    supabase: Client = Depends(get_supabase)
):
    """Receives high-frequency GPS pings from the mobile app."""
    try:
        supabase.table("realtime_gps_logs").insert({
            "user_id": ping.user_id,
            "latitude": ping.latitude,
            "longitude": ping.longitude,
            "location_accuracy_m": ping.accuracy_m or 10.0,
            "speed_kmh": ping.speed or 0.0,
            "altitude_m": ping.altitude or 0.0,
            "battery_level": ping.battery_level,
            "recorded_at": datetime.utcnow().isoformat()
        }).execute()
    except Exception as e:
        logger.debug(f"Error saving GPS ping to DB: {e}")

    # Also update memory cache for instant web view
    if ping.user_id not in _memory_gps_logs:
        _memory_gps_logs[ping.user_id] = []
    _memory_gps_logs[ping.user_id].append({
        "latitude": ping.latitude,
        "longitude": ping.longitude,
        "accuracy_m": ping.accuracy_m or 10.0,
        "speed": ping.speed or 0.0,
        "altitude": ping.altitude or 0.0,
        "battery_level": ping.battery_level,
        "recorded_at": datetime.utcnow().isoformat()
    })
    # Keep last 100 points
    if len(_memory_gps_logs[ping.user_id]) > 100:
        _memory_gps_logs[ping.user_id] = _memory_gps_logs[ping.user_id][-100:]

    return {"status": "ok"}

@router.get("/api/gps/location/{user_id}/latest")
async def get_latest_location(
    user_id: str,
    session_token: str,
    supabase: Client = Depends(get_supabase)
):
    """AJAX endpoint polled by the 3D Mapbox Tracking Page every 6 seconds."""
    # Validate session
    is_valid = False
    try:
        res = supabase.table("location_sharing_sessions")\
            .select("is_active, expires_at")\
            .eq("user_id", user_id)\
            .eq("session_token", session_token)\
            .eq("is_active", True)\
            .gt("expires_at", datetime.utcnow().isoformat())\
            .maybe_single().execute()
        if res and res.data:
            is_valid = True
    except Exception:
        pass

    if not is_valid:
        # Check memory session
        s = _memory_sessions.get(session_token)
        if s and s["user_id"] == user_id and s["is_active"] and s["expires_at"] > datetime.utcnow():
            is_valid = True

    if not is_valid:
        raise HTTPException(status_code=403, detail="Tracking session expired or invalid.")

    # 1. Check latest from realtime_gps_logs
    try:
        log_res = supabase.table("realtime_gps_logs")\
            .select("latitude, longitude, location_accuracy_m, speed_kmh, altitude_m, battery_level, recorded_at")\
            .eq("user_id", user_id)\
            .order("recorded_at", desc=True)\
            .limit(1).execute()

        if log_res.data:
            row = log_res.data[0]
            return {
                "has_data": True,
                "user_id": user_id,
                "latitude": float(row["latitude"]),
                "longitude": float(row["longitude"]),
                "accuracy": float(row.get("location_accuracy_m") or 15.0),
                "speed": float(row.get("speed_kmh") or 0.0),
                "altitude": float(row.get("altitude_m") or 0.0),
                "battery": row.get("battery_level"),
                "recorded_at": row["recorded_at"],
                "session_active": True
            }
    except Exception as e:
        logger.debug(f"DB latest GPS check notice: {e}")

    # 2. Check memory logs
    logs = _memory_gps_logs.get(user_id, [])
    if logs:
        last = logs[-1]
        return {
            "has_data": True,
            "user_id": user_id,
            "latitude": last["latitude"],
            "longitude": last["longitude"],
            "accuracy": last.get("accuracy_m", 15.0),
            "speed": last.get("speed", 0.0),
            "altitude": last.get("altitude", 0.0),
            "battery": last.get("battery_level"),
            "recorded_at": last["recorded_at"],
            "session_active": True
        }

    # 3. Fallback to active panic event
    try:
        ev_res = supabase.table("panic_events")\
            .select("latitude, longitude, location_accuracy_m, triggered_at")\
            .eq("user_id", user_id)\
            .order("triggered_at", desc=True)\
            .limit(1).execute()
        if ev_res.data:
            ev = ev_res.data[0]
            return {
                "has_data": True,
                "user_id": user_id,
                "latitude": float(ev["latitude"]),
                "longitude": float(ev["longitude"]),
                "accuracy": float(ev.get("location_accuracy_m") or 20.0),
                "speed": 0.0,
                "altitude": 0.0,
                "recorded_at": ev["triggered_at"],
                "session_active": True
            }
    except Exception:
        pass

    return {
        "has_data": False,
        "user_id": user_id,
        "session_active": True,
        "message": "Waiting for device GPS coordinates..."
    }

@router.get("/api/gps/location/{user_id}/trail")
async def get_location_trail(
    user_id: str,
    session_token: str,
    hours: int = 8,
    supabase: Client = Depends(get_supabase)
):
    """Returns coordinates breadcrumb trail recorded over the session."""
    since = (datetime.utcnow() - timedelta(hours=hours)).isoformat()
    trail_points = []

    try:
        res = supabase.table("realtime_gps_logs")\
            .select("latitude, longitude, recorded_at")\
            .eq("user_id", user_id)\
            .gte("recorded_at", since)\
            .order("recorded_at", asc=True)\
            .limit(200).execute()
        if res.data:
            trail_points = [
                [float(p["longitude"]), float(p["latitude"])]
                for p in res.data
                if p.get("latitude") and p.get("longitude")
            ]
    except Exception:
        pass

    if not trail_points and user_id in _memory_gps_logs:
        trail_points = [
            [p["longitude"], p["latitude"]]
            for p in _memory_gps_logs[user_id]
        ]

    return {
        "user_id": user_id,
        "trail_count": len(trail_points),
        "coordinates": trail_points
    }

# ─── POLICE STATIONS & DANGER ZONES (KENYA / NAIROBI) ──────────────────────────

POLICE_STATIONS = [
    {"name": "Central Police Station Nairobi", "latitude": -1.2825, "longitude": 36.8188, "phone": "+254 20 2222222"},
    {"name": "Kilimani Police Station", "latitude": -1.2921, "longitude": 36.7876, "phone": "+254 20 2722900"},
    {"name": "Parklands Police Station", "latitude": -1.2618, "longitude": 36.8124, "phone": "+254 20 3743333"},
    {"name": "Muthangari Police Station", "latitude": -1.2785, "longitude": 36.7698, "phone": "+254 20 3870233"},
    {"name": "Gigiri Police Station", "latitude": -1.2335, "longitude": 36.8115, "phone": "+254 20 7120150"},
    {"name": "Langata Police Station", "latitude": -1.3341, "longitude": 36.7589, "phone": "+254 20 891333"},
    {"name": "Kasarani Police Station", "latitude": -1.2223, "longitude": 36.8988, "phone": "+254 20 8561222"},
    {"name": "Industrial Area Police Station", "latitude": -1.3065, "longitude": 36.8423, "phone": "+254 20 558555"},
    {"name": "Karen Police Station", "latitude": -1.3211, "longitude": 36.7092, "phone": "+254 20 882000"}
]

DANGER_ZONES = [
    {"location_name": "Globe Cinema Roundabout", "latitude": -1.2798, "longitude": 36.8205, "severity_level": "High Caution", "description": "Reported snatching & congestion zone at dusk"},
    {"location_name": "Country Bus Station Corridor", "latitude": -1.2862, "longitude": 36.8340, "severity_level": "Caution", "description": "High foot-traffic, bag-snatching alert area"},
    {"location_name": "Muthurwa Footbridge Area", "latitude": -1.2891, "longitude": 36.8375, "severity_level": "Medium Risk", "description": "Poor lighting at night, stick to main lit paths"}
]

@router.get("/police-locations")
async def get_police_locations():
    return POLICE_STATIONS

@router.get("/danger-zones")
async def get_danger_zones():
    return DANGER_ZONES

# ─── 3D MAPBOX WEB TRACKING PAGE ───────────────────────────────────────────────

@router.get("/gps/track/{user_id}", response_class=HTMLResponse)
async def track_user_location_page(
    user_id: str,
    session_token: str,
    request: Request,
    supabase: Client = Depends(get_supabase)
):
    """
    Renders an ultra-modern 3D Mapbox tracking interface for emergency contacts
    and guardians. Supports 3D buildings extrusion, auto-centering, dynamic compass
    pitch, police station proximity, and live emergency dispatch metrics.
    """
    # 1. Verify session
    is_valid = False
    expires_at_dt = None
    is_emergency = False
    activity_name = "Real-Time Tracking"

    try:
        res = supabase.table("location_sharing_sessions")\
            .select("is_active, expires_at")\
            .eq("user_id", user_id)\
            .eq("session_token", session_token)\
            .eq("is_active", True)\
            .maybe_single().execute()

        if res and res.data:
            exp_str = res.data["expires_at"]
            expires_at_dt = datetime.fromisoformat(exp_str.replace("Z", "+00:00")).replace(tzinfo=None)
            if expires_at_dt > datetime.utcnow():
                is_valid = True
    except Exception:
        pass

    # Check memory session fallback
    if not is_valid:
        s = _memory_sessions.get(session_token)
        if s and s["user_id"] == user_id and s["is_active"] and s["expires_at"] > datetime.utcnow():
            is_valid = True
            expires_at_dt = s["expires_at"]
            is_emergency = s.get("is_emergency", False)
            activity_name = s.get("activity_name", "Real-Time Tracking")

    # If session is invalid or expired, return polished error page
    if not is_valid:
        return HTMLResponse(
            status_code=404,
            content="""
            <!DOCTYPE html>
            <html lang="en">
            <head>
                <meta charset="UTF-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <title>SafeLink • Session Inactive</title>
                <link rel="preconnect" href="https://fonts.googleapis.com">
                <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;600;800&display=swap" rel="stylesheet">
                <style>
                    * { box-sizing: border-box; margin: 0; padding: 0; font-family: 'Plus Jakarta Sans', sans-serif; }
                    body { background: #0b0f19; color: #fff; display: flex; align-items: center; justify-content: center; min-height: 100vh; padding: 24px; }
                    .card { background: #161e2e; border: 1px solid rgba(255,255,255,0.08); border-radius: 24px; padding: 40px 28px; max-width: 440px; text-align: center; box-shadow: 0 20px 40px rgba(0,0,0,0.5); }
                    .icon { width: 72px; height: 72px; background: rgba(239, 68, 68, 0.15); border-radius: 50%; display: flex; align-items: center; justify-content: center; margin: 0 auto 20px; font-size: 32px; color: #ef4444; }
                    h2 { font-size: 22px; font-weight: 800; margin-bottom: 12px; }
                    p { color: #94a3b8; font-size: 14px; line-height: 1.6; margin-bottom: 24px; }
                    .btn { display: inline-block; background: #2563eb; color: #fff; padding: 14px 28px; border-radius: 14px; text-decoration: none; font-weight: 700; font-size: 14px; }
                </style>
            </head>
            <body>
                <div class="card">
                    <div class="icon">⌛</div>
                    <h2>Tracking Session Ended</h2>
                    <p>This live location sharing link has expired or has been stopped by the user for safety and privacy.</p>
                    <a href="tel:999" class="btn" style="background: #dc2626; margin-bottom: 10px; display: block;">📞 Call Police (999)</a>
                </div>
            </body>
            </html>
            """
        )

    # 2. Get User Name
    user_name = "SafeLink User"
    try:
        u_res = supabase.table("users").select("full_name").eq("id", user_id).maybe_single().execute()
        if u_res and u_res.data and u_res.data.get("full_name"):
            user_name = u_res.data["full_name"].strip()
    except Exception:
        pass

    # 3. Check for active emergency
    try:
        ev = supabase.table("panic_events")\
            .select("id, status, triggered_at")\
            .eq("user_id", user_id)\
            .eq("status", "active")\
            .limit(1).execute()
        if ev and ev.data:
            is_emergency = True
            activity_name = "🚨 EMERGENCY DISTRESS ALERT"
    except Exception:
        pass

    # 4. Get latest position
    latest_lat = -1.2825
    latest_lng = 36.8222
    latest_accuracy = 15.0
    latest_speed = 0.0
    latest_time_str = "Just now"

    try:
        gps_row = supabase.table("realtime_gps_logs")\
            .select("latitude, longitude, location_accuracy_m, speed_kmh, recorded_at")\
            .eq("user_id", user_id)\
            .order("recorded_at", desc=True)\
            .limit(1).execute()
        if gps_row and gps_row.data:
            r = gps_row.data[0]
            latest_lat = float(r["latitude"])
            latest_lng = float(r["longitude"])
            latest_accuracy = float(r.get("location_accuracy_m") or 15.0)
            latest_speed = float(r.get("speed_kmh") or 0.0)
            latest_time_str = r.get("recorded_at", "Just now")
    except Exception:
        pass

    # Fallback to memory
    if latest_lat == -1.2825 and user_id in _memory_gps_logs and _memory_gps_logs[user_id]:
        m = _memory_gps_logs[user_id][-1]
        latest_lat = m["latitude"]
        latest_lng = m["longitude"]
        latest_accuracy = m.get("accuracy_m", 15.0)
        latest_speed = m.get("speed", 0.0)
        latest_time_str = m.get("recorded_at", "Just now")

    # Mapbox Access Token
    mapbox_token = os.getenv("MAPBOX_WEB_TOKEN") or os.getenv("MAPBOX_TOKEN") or os.getenv("MAPBOX_ACCESS_TOKEN") or "pk.eyJ1Ijoiam95a2lwa2VtYm9pIiwiYSI6ImNtY2J2MmlpZTAxbWIya3NhaWV1aTh5MTkifQ.-nLBrGjd639RrXjdXHq3HA"

    expires_display = expires_at_dt.strftime("%I:%M %p UTC") if expires_at_dt else "Temporary Session"

    # HTML 3D Mapbox Page
    html_content = f"""
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <title>SafeLink Live • Tracking {user_name}</title>
        <script src="https://api.mapbox.com/mapbox-gl-js/v2.15.0/mapbox-gl.js"></script>
        <link href="https://api.mapbox.com/mapbox-gl-js/v2.15.0/mapbox-gl.css" rel="stylesheet" />
        <link rel="preconnect" href="https://fonts.googleapis.com">
        <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800;900&display=swap" rel="stylesheet">
        <style>
            :root {{
                --bg: #090d16;
                --card-bg: rgba(18, 24, 38, 0.88);
                --card-border: rgba(255, 255, 255, 0.1);
                --accent-primary: #38bdf8;
                --emergency-red: #ef4444;
                --emergency-glow: rgba(239, 68, 68, 0.4);
                --success-green: #10b981;
                --text-main: #f8fafc;
                --text-muted: #94a3b8;
            }}
            * {{ box-sizing: border-box; margin: 0; padding: 0; -webkit-tap-highlight-color: transparent; }}
            body {{
                font-family: 'Plus Jakarta Sans', -apple-system, sans-serif;
                background: var(--bg);
                color: var(--text-main);
                overflow: hidden;
                width: 100vw;
                height: 100vh;
                position: relative;
            }}
            #map {{
                position: absolute;
                top: 0;
                left: 0;
                width: 100%;
                height: 100%;
                z-index: 1;
            }}

            /* Top Glassmorphism Status Bar */
            .top-overlay {{
                position: absolute;
                top: 16px;
                left: 16px;
                right: 16px;
                z-index: 10;
                max-width: 520px;
                margin: 0 auto;
                pointer-events: none;
            }}
            .glass-card {{
                pointer-events: auto;
                background: var(--card-bg);
                backdrop-filter: blur(16px);
                -webkit-backdrop-filter: blur(16px);
                border: 1px solid var(--card-border);
                border-radius: 20px;
                padding: 16px 18px;
                box-shadow: 0 16px 40px rgba(0,0,0,0.6);
                transition: all 0.3s ease;
            }}

            .emergency-banner {{
                background: linear-gradient(135deg, rgba(239, 68, 68, 0.25) 0%, rgba(185, 28, 28, 0.15) 100%);
                border-color: rgba(239, 68, 68, 0.5);
                box-shadow: 0 12px 30px var(--emergency-glow);
            }}

            .header-row {{
                display: flex;
                align-items: center;
                justify-content: space-between;
            }}
            .user-info {{
                display: flex;
                align-items: center;
                gap: 12px;
            }}
            .avatar-beacon {{
                position: relative;
                width: 44px;
                height: 44px;
                border-radius: 50%;
                background: #1e293b;
                display: flex;
                align-items: center;
                justify-content: center;
                font-weight: 800;
                font-size: 18px;
                border: 2px solid {'#ef4444' if is_emergency else '#38bdf8'};
            }}
            .beacon-pulse {{
                position: absolute;
                width: 100%;
                height: 100%;
                border-radius: 50%;
                border: 2px solid {'#ef4444' if is_emergency else '#38bdf8'};
                animation: pulse-ring 2s infinite;
            }}
            @keyframes pulse-ring {{
                0% {{ transform: scale(1); opacity: 0.9; }}
                100% {{ transform: scale(1.8); opacity: 0; }}
            }}
            .title-h1 {{
                font-size: 17px;
                font-weight: 900;
                letter-spacing: -0.2px;
            }}
            .status-badge {{
                display: inline-flex;
                align-items: center;
                gap: 6px;
                font-size: 11px;
                font-weight: 800;
                text-transform: uppercase;
                letter-spacing: 0.8px;
                color: {'#ef4444' if is_emergency else '#10b981'};
                margin-top: 2px;
            }}
            .status-dot {{
                width: 8px;
                height: 8px;
                border-radius: 50%;
                background: {'#ef4444' if is_emergency else '#10b981'};
                box-shadow: 0 0 10px {'#ef4444' if is_emergency else '#10b981'};
            }}

            /* Quick Metrics Grid */
            .metrics-grid {{
                display: grid;
                grid-template-columns: repeat(3, 1fr);
                gap: 10px;
                margin-top: 14px;
                padding-top: 12px;
                border-top: 1px solid rgba(255,255,255,0.08);
            }}
            .metric-item {{
                background: rgba(255,255,255,0.04);
                padding: 8px 10px;
                border-radius: 12px;
                text-align: center;
            }}
            .metric-label {{
                font-size: 10px;
                font-weight: 600;
                color: var(--text-muted);
                text-transform: uppercase;
                letter-spacing: 0.5px;
            }}
            .metric-val {{
                font-size: 13px;
                font-weight: 800;
                color: #fff;
                margin-top: 2px;
            }}

            /* Bottom Action Bar */
            .bottom-overlay {{
                position: absolute;
                bottom: 24px;
                left: 16px;
                right: 16px;
                z-index: 10;
                max-width: 520px;
                margin: 0 auto;
                pointer-events: none;
            }}
            .action-row {{
                pointer-events: auto;
                display: flex;
                gap: 10px;
            }}
            .btn-action {{
                flex: 1;
                display: flex;
                align-items: center;
                justify-content: center;
                gap: 8px;
                padding: 14px 16px;
                border-radius: 16px;
                font-size: 14px;
                font-weight: 800;
                text-decoration: none;
                cursor: pointer;
                border: none;
                transition: transform 0.15s, opacity 0.2s;
                box-shadow: 0 10px 25px rgba(0,0,0,0.4);
            }}
            .btn-action:active {{ transform: scale(0.97); }}
            .btn-emergency {{
                background: linear-gradient(135deg, #ef4444 0%, #b91c1c 100%);
                color: white;
            }}
            .btn-maps {{
                background: rgba(30, 41, 59, 0.95);
                backdrop-filter: blur(10px);
                color: white;
                border: 1px solid rgba(255,255,255,0.15);
            }}
            .btn-recenter {{
                width: 48px;
                flex: 0 0 48px;
                background: rgba(30, 41, 59, 0.95);
                border: 1px solid rgba(255,255,255,0.15);
                color: var(--accent-primary);
                font-size: 20px;
            }}

            /* 3D Map Floating Controls (Right Side) */
            .map-controls-side {{
                position: absolute;
                right: 16px;
                top: 50%;
                transform: translateY(-50%);
                z-index: 10;
                display: flex;
                flex-direction: column;
                gap: 10px;
            }}
            .side-btn {{
                width: 44px;
                height: 44px;
                border-radius: 14px;
                background: var(--card-bg);
                backdrop-filter: blur(12px);
                border: 1px solid var(--card-border);
                color: #fff;
                display: flex;
                align-items: center;
                justify-content: center;
                cursor: pointer;
                font-size: 18px;
                box-shadow: 0 8px 20px rgba(0,0,0,0.4);
            }}

            /* Custom Marker Styling */
            .pulse-marker {{
                width: 40px;
                height: 40px;
                border-radius: 50%;
                background: {'#ef4444' if is_emergency else '#38bdf8'};
                border: 3px solid #ffffff;
                box-shadow: 0 0 25px {'rgba(239, 68, 68, 0.8)' if is_emergency else 'rgba(56, 189, 248, 0.8)'};
                position: relative;
                cursor: pointer;
            }}
            .pulse-marker::after {{
                content: '';
                position: absolute;
                top: -12px;
                left: -12px;
                width: 58px;
                height: 58px;
                border-radius: 50%;
                border: 3px solid {'#ef4444' if is_emergency else '#38bdf8'};
                animation: marker-pulse 1.8s infinite;
            }}
            @keyframes marker-pulse {{
                0% {{ transform: scale(0.6); opacity: 1; }}
                100% {{ transform: scale(1.6); opacity: 0; }}
            }}
            .police-marker {{
                background: #0284c7;
                width: 28px;
                height: 28px;
                border-radius: 50%;
                border: 2px solid #fff;
                display: flex;
                align-items: center;
                justify-content: center;
                font-size: 14px;
                box-shadow: 0 4px 10px rgba(0,0,0,0.5);
            }}
        </style>
    </head>
    <body>
        <div id="map"></div>

        <!-- Top Floating Status Overlay -->
        <div class="top-overlay">
            <div class="glass-card {'emergency-banner' if is_emergency else ''}">
                <div class="header-row">
                    <div class="user-info">
                        <div class="avatar-beacon">
                            <div class="beacon-pulse"></div>
                            <span>{user_name[0] if user_name else 'S'}</span>
                        </div>
                        <div>
                            <div class="title-h1">{user_name}</div>
                            <div class="status-badge">
                                <span class="status-dot"></span>
                                <span id="status-text">{'🚨 EMERGENCY SOS ACTIVE' if is_emergency else '🟢 LIVE TRACKING ACTIVE'}</span>
                            </div>
                        </div>
                    </div>
                    <div style="text-align: right;">
                        <span id="countdown-label" style="font-size: 10px; font-weight: 700; color: var(--text-muted);">AUTO-REFRESH</span>
                        <div id="refresh-timer" style="font-size: 14px; font-weight: 900; color: var(--accent-primary);">6s</div>
                    </div>
                </div>

                <div class="metrics-grid">
                    <div class="metric-item">
                        <div class="metric-label">Last Ping</div>
                        <div class="metric-val" id="metric-time">Live</div>
                    </div>
                    <div class="metric-item">
                        <div class="metric-label">Accuracy</div>
                        <div class="metric-val" id="metric-accuracy">±{int(latest_accuracy)}m</div>
                    </div>
                    <div class="metric-item">
                        <div class="metric-label">Session</div>
                        <div class="metric-val" style="color: #38bdf8;">Until {expires_display}</div>
                    </div>
                </div>
            </div>
        </div>

        <!-- Side Controls -->
        <div class="map-controls-side">
            <button class="side-btn" id="btn-pitch" title="Toggle 3D Tilt">3D</button>
            <button class="side-btn" id="btn-style" title="Toggle Satellite">🗺️</button>
            <button class="side-btn" id="btn-refresh" title="Refresh Now">🔄</button>
        </div>

        <!-- Bottom Action Controls -->
        <div class="bottom-overlay">
            <div class="action-row">
                <a href="tel:999" class="btn-action btn-emergency">
                    <span>🚨</span> Call Police 999
                </a>
                <a id="btn-open-maps" href="https://www.google.com/maps/dir/?api=1&destination={latest_lat},{latest_lng}" target="_blank" class="btn-action btn-maps">
                    <span>🧭</span> Google Maps
                </a>
                <button class="btn-action btn-recenter" id="btn-recenter" title="Center on Victim">
                    🎯
                </button>
            </div>
        </div>

        <script>
            mapboxgl.accessToken = '{mapbox_token}';
            
            let currentLat = {latest_lat};
            let currentLng = {latest_lng};
            let currentAccuracy = {latest_accuracy};
            let is3D = true;
            let currentStyleIndex = 0;
            const mapStyles = [
                'mapbox://styles/mapbox/dark-v11',
                'mapbox://styles/mapbox/satellite-streets-v12',
                'mapbox://styles/mapbox/navigation-night-v1'
            ];

            let userMarker = null;
            let map = null;
            let refreshInterval = null;
            let countdownSeconds = 6;

            function initMap() {{
                map = new mapboxgl.Map({{
                    container: 'map',
                    style: mapStyles[currentStyleIndex],
                    center: [currentLng, currentLat],
                    zoom: 16.5,
                    pitch: 60, // 3D tilt
                    bearing: -20,
                    antialias: true
                }});

                map.addControl(new mapboxgl.NavigationControl({{ visualizePitch: true }}), 'bottom-right');

                map.on('load', () => {{
                    setup3DBuildings();
                    setupUserMarker();
                    setupAccuracyCircle();
                    fetchPoliceLocations();
                    fetchLocationTrail();
                    startAutoRefresh();
                }});
            }}

            function setup3DBuildings() {{
                if (map.getLayer('3d-buildings')) return;
                const layers = map.getStyle().layers;
                let labelLayerId;
                for (let i = 0; i < layers.length; i++) {{
                    if (layers[i].type === 'symbol' && layers[i].layout['text-field']) {{
                        labelLayerId = layers[i].id;
                        break;
                    }}
                }}

                map.addLayer({{
                    'id': '3d-buildings',
                    'source': 'composite',
                    'source-layer': 'building',
                    'filter': ['==', 'extrude', 'true'],
                    'type': 'fill-extrusion',
                    'minzoom': 14,
                    'paint': {{
                        'fill-extrusion-color': '#1e293b',
                        'fill-extrusion-height': ['interpolate', ['linear'], ['zoom'], 14, 0, 15.05, ['get', 'height']],
                        'fill-extrusion-base': ['interpolate', ['linear'], ['zoom'], 14, 0, 15.05, ['get', 'min_height']],
                        'fill-extrusion-opacity': 0.75
                    }}
                }}, labelLayerId);
            }}

            function setupUserMarker() {{
                const el = document.createElement('div');
                el.className = 'pulse-marker';
                userMarker = new mapboxgl.Marker(el)
                    .setLngLat([currentLng, currentLat])
                    .addTo(map);

                const popup = new mapboxgl.Popup({{ offset: 25 }})
                    .setHTML(`
                        <div style="padding: 10px; color: #000;">
                            <strong>{user_name}</strong><br>
                            <span style="font-size: 12px; color: #ef4444;">{'EMERGENCY SOS BROADCAST' if is_emergency else 'Live Location Sharing'}</span>
                        </div>
                    `);
                userMarker.setPopup(popup);
            }}

            function setupAccuracyCircle() {{
                if (map.getSource('accuracy-source')) return;

                map.addSource('accuracy-source', {{
                    type: 'geojson',
                    data: createGeoJSONCircle([currentLng, currentLat], currentAccuracy / 1000)
                }});

                map.addLayer({{
                    id: 'accuracy-layer',
                    type: 'fill',
                    source: 'accuracy-source',
                    paint: {{
                        'fill-color': '{'#ef4444' if is_emergency else '#38bdf8'}',
                        'fill-opacity': 0.15
                    }}
                }});
            }}

            function createGeoJSONCircle(center, radiusInKm, points = 64) {{
                const coords = {{ latitude: center[1], longitude: center[0] }};
                const km = radiusInKm;
                const ret = [];
                const distanceX = km / (111.320 * Math.cos(coords.latitude * Math.PI / 180));
                const distanceY = km / 110.574;
                for (let i = 0; i < points; i++) {{
                    const theta = (i / points) * (2 * Math.PI);
                    const x = distanceX * Math.cos(theta);
                    const y = distanceY * Math.sin(theta);
                    ret.push([coords.longitude + x, coords.latitude + y]);
                }}
                ret.push(ret[0]);
                return {{
                    type: "FeatureCollection",
                    features: [{{ type: "Feature", geometry: {{ type: "Polygon", coordinates: [ret] }} }}]
                }};
            }}

            async function fetchLocationUpdate() {{
                try {{
                    const res = await fetch(`/api/gps/location/{user_id}/latest?session_token={session_token}`);
                    if (!res.ok) return;
                    const data = await res.json();
                    if (data.has_data && data.latitude && data.longitude) {{
                        currentLat = data.latitude;
                        currentLng = data.longitude;
                        currentAccuracy = data.accuracy || 15.0;

                        // Update Marker
                        if (userMarker) {{
                            userMarker.setLngLat([currentLng, currentLat]);
                        }}

                        // Update Accuracy circle
                        if (map.getSource('accuracy-source')) {{
                            map.getSource('accuracy-source').setData(createGeoJSONCircle([currentLng, currentLat], currentAccuracy / 1000));
                        }}

                        // Update Metrics UI
                        document.getElementById('metric-accuracy').innerText = `±${{Math.round(currentAccuracy)}}m`;
                        document.getElementById('metric-time').innerText = new Date(data.recorded_at).toLocaleTimeString([], {{hour: '2-digit', minute:'2-digit', second:'2-digit'}});
                        document.getElementById('btn-open-maps').href = `https://www.google.com/maps/dir/?api=1&destination=${{currentLat}},${{currentLng}}`;
                    }}
                }} catch (e) {{
                    console.warn('Location poll error:', e);
                }}
            }}

            async function fetchLocationTrail() {{
                try {{
                    const res = await fetch(`/api/gps/location/{user_id}/trail?session_token={session_token}`);
                    if (!res.ok) return;
                    const data = await res.json();
                    if (data.coordinates && data.coordinates.length > 1) {{
                        if (map.getSource('trail-source')) {{
                            map.getSource('trail-source').setData({{
                                type: 'Feature',
                                geometry: {{ type: 'LineString', coordinates: data.coordinates }}
                            }});
                        }} else {{
                            map.addSource('trail-source', {{
                                type: 'geojson',
                                data: {{
                                    type: 'Feature',
                                    geometry: {{ type: 'LineString', coordinates: data.coordinates }}
                                }}
                            }});
                            map.addLayer({{
                                id: 'trail-line',
                                type: 'line',
                                source: 'trail-source',
                                layout: {{ 'line-join': 'round', 'line-cap': 'round' }},
                                paint: {{
                                    'line-color': '{'#ef4444' if is_emergency else '#38bdf8'}',
                                    'line-width': 4,
                                    'line-opacity': 0.8
                                }}
                            }});
                        }}
                    }}
                }} catch (e) {{}}
            }}

            async function fetchPoliceLocations() {{
                try {{
                    const res = await fetch('/police-locations');
                    if (!res.ok) return;
                    const list = await res.json();
                    list.forEach(p => {{
                        const el = document.createElement('div');
                        el.className = 'police-marker';
                        el.innerText = '👮';
                        new mapboxgl.Marker(el)
                            .setLngLat([p.longitude, p.latitude])
                            .setPopup(new mapboxgl.Popup({{ offset: 15 }}).setHTML(`
                                <div style="color: #000; padding: 6px;">
                                    <strong>${{p.name}}</strong><br>
                                    <a href="tel:${{p.phone}}" style="color: #0284c7; font-weight: bold;">📞 ${{p.phone}}</a>
                                </div>
                            `))
                            .addTo(map);
                    }});
                }} catch (e) {{}}
            }}

            function startAutoRefresh() {{
                countdownSeconds = 6;
                if (refreshInterval) clearInterval(refreshInterval);
                refreshInterval = setInterval(() => {{
                    countdownSeconds--;
                    document.getElementById('refresh-timer').innerText = `${{countdownSeconds}}s`;
                    if (countdownSeconds <= 0) {{
                        countdownSeconds = 6;
                        fetchLocationUpdate();
                    }}
                }}, 1000);
            }}

            // Controls listeners
            document.getElementById('btn-recenter').addEventListener('click', () => {{
                map.flyTo({{
                    center: [currentLng, currentLat],
                    zoom: 17,
                    pitch: is3D ? 60 : 0,
                    duration: 1500
                }});
            }});

            document.getElementById('btn-pitch').addEventListener('click', () => {{
                is3D = !is3D;
                map.easeTo({{
                    pitch: is3D ? 60 : 0,
                    duration: 1000
                }});
                document.getElementById('btn-pitch').innerText = is3D ? '3D' : '2D';
            }});

            document.getElementById('btn-refresh').addEventListener('click', () => {{
                fetchLocationUpdate();
                countdownSeconds = 6;
            }});

            document.getElementById('btn-style').addEventListener('click', () => {{
                currentStyleIndex = (currentStyleIndex + 1) % mapStyles.length;
                map.setStyle(mapStyles[currentStyleIndex]);
                map.once('style.load', () => {{
                    setup3DBuildings();
                    setupAccuracyCircle();
                    fetchLocationTrail();
                }});
            }});

            window.onload = initMap;
        </script>
    </body>
    </html>
    """

    return HTMLResponse(content=html_content)
