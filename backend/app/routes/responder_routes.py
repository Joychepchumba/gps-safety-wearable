import os
import datetime
import logging
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from supabase import create_client, Client
from app.services.location_service import find_nearby_responders, haversine_distance

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/responders", tags=["responders"])

DEFAULT_SUPABASE_URL = "https://afagwdhpjnnbueiyjmde.supabase.co"
DEFAULT_SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFmYWd3ZGhwam5uYnVlaXlqbWRlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk5MTkzMzUsImV4cCI6MjEwNTQ5NTMzNX0.Qw_rs_KJOZF8RkXWW62QBKnSafzJFkt9YBPqCRo9mlA"

def get_supabase() -> Client:
    url = os.getenv("SUPABASE_URL") or DEFAULT_SUPABASE_URL
    key = (
        os.getenv("SUPABASE_SERVICE_ROLE_KEY")
        or os.getenv("SUPABASE_SERVICE_KEY")
        or os.getenv("SUPABASE_ANON_KEY")
        or DEFAULT_SUPABASE_KEY
    )
    return create_client(url, key)

class ResponderLocationUpdate(BaseModel):
    user_id: str
    latitude: float
    longitude: float
    accuracy_m: Optional[float] = None

@router.post("/location")
def update_responder_location(req: ResponderLocationUpdate, supabase: Client = Depends(get_supabase)):
    """Periodically syncs a community responder's location to enable accurate 2km geo-radius alerts."""
    try:
        supabase.table("realtime_gps_logs").insert({
            "user_id": req.user_id,
            "latitude": req.latitude,
            "longitude": req.longitude,
            "accuracy_m": req.accuracy_m,
            "recorded_at": datetime.datetime.utcnow().isoformat(),
        }).execute()
        return {"success": True, "message": "Location updated"}
    except Exception as e:
        logger.error("[RESPONDER LOC ERROR] %s", e)
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/nearby")
def get_nearby_responders(
    lat: float,
    lng: float,
    radius_m: float = 2000.0,
    supabase: Client = Depends(get_supabase)
):
    """Finds community responders within radius_m (default 2km / 2000m)."""
    responders = find_nearby_responders(supabase, lat, lng, radius_m)
    return {"success": True, "responders": responders}

@router.get("/alerts")
def get_active_community_alerts(
    user_id: str = Query(..., description="ID of the viewing responder"),
    lat: float = Query(..., description="Current responder latitude"),
    lng: float = Query(..., description="Current responder longitude"),
    radius_m: float = Query(2000.0, description="Radius in meters, default 2km"),
    supabase: Client = Depends(get_supabase)
):
    """
    Returns active emergency alerts within 2km of the responder.
    Shares minimal privacy information: user_name, coordinates, distance, and direct maps link.
    """
    try:
        # 1. Fetch active panic events
        res = supabase.table("panic_events") \
            .select("id, user_id, latitude, longitude, trigger_method, triggered_at, status") \
            .eq("status", "active") \
            .neq("user_id", user_id) \
            .order("triggered_at", desc=True) \
            .limit(20) \
            .execute()

        events = res.data or []
        if not events:
            return {"success": True, "alerts": []}

        # 2. Get user names for these events with minimal privacy exposure
        victim_ids = list({e["user_id"] for e in events})
        users_res = supabase.table("users").select("id, full_name").in_("id", victim_ids).execute()
        user_name_map = {u["id"]: u["full_name"] for u in (users_res.data or [])}

        nearby_alerts = []
        for ev in events:
            ev_lat = ev.get("latitude")
            ev_lng = ev.get("longitude")
            if ev_lat is None or ev_lng is None:
                continue

            dist = haversine_distance(lat, lng, float(ev_lat), float(ev_lng))
            if dist <= radius_m:
                full_name = user_name_map.get(ev["user_id"], "SafeLink User")
                # Minimal info: first name or SafeLink User
                display_name = full_name.split()[0] if full_name else "SafeLink User"

                nearby_alerts.append({
                    "panic_event_id": ev["id"],
                    "user_name": display_name,
                    "latitude": ev_lat,
                    "longitude": ev_lng,
                    "distance_m": round(dist, 1),
                    "maps_link": f"https://www.google.com/maps/search/?api=1&query={ev_lat},{ev_lng}",
                    "trigger_method": ev.get("trigger_method", "emergency"),
                    "triggered_at": ev.get("triggered_at"),
                    "status": ev.get("status"),
                })

        return {"success": True, "alerts": nearby_alerts}
    except Exception as e:
        logger.error("[COMMUNITY ALERTS FETCH ERROR] %s", e)
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/alerts/{panic_event_id}/respond")
def respond_to_alert(
    panic_event_id: str,
    user_id: str = Query(...),
    supabase: Client = Depends(get_supabase)
):
    """Allows a community responder to accept and respond to an emergency alert."""
    try:
        now = datetime.datetime.utcnow().isoformat()
        supabase.table("responder_alerts").upsert({
            "panic_event_id": panic_event_id,
            "responder_id": user_id,
            "acknowledged_at": now,
        }, on_conflict="panic_event_id,responder_id").execute()
        return {"success": True, "message": "Response registered. Stay safe and proceed carefully."}
    except Exception as e:
        logger.error("[RESPOND ERROR] %s", e)
        raise HTTPException(status_code=500, detail=str(e))
