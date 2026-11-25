import os
from fastapi import APIRouter, HTTPException, Depends
from app.models.schemas import AlertFromPendant, AlertResponse
from app.services.sms_service import SmsService
from app.services.push_service import PushService
from app.services.location_service import (
    find_nearby_responders,
    anonymise_24h_location_data,
    save_location_log,
)
from supabase import create_client, Client
from pydantic import BaseModel
import datetime

router = APIRouter(prefix="/alert", tags=["alert"])

sms_service = SmsService()
push_service = PushService()

def get_supabase() -> Client:
    url = os.getenv("SUPABASE_URL", "")
    key = os.getenv("SUPABASE_SERVICE_KEY", os.getenv("SUPABASE_ANON_KEY", ""))
    if not url or not key:
        raise RuntimeError("Supabase credentials not configured.")
    return create_client(url, key)

@router.post("/pendant", response_model=AlertResponse)
async def trigger_pendant_alert(alert: AlertFromPendant, supabase: Client = Depends(get_supabase)):
    device_res = supabase.table("wearable_devices").select("user_id, id").eq("device_mac", alert.device_mac).eq("is_active", True).execute()
    if not device_res.data:
        raise HTTPException(status_code=404, detail="Device not found or not active")
        
    user_id = device_res.data[0]["user_id"]
    wearable_id = device_res.data[0]["id"]
    
    return await process_alert(user_id, alert.trigger_method, alert.latitude, alert.longitude, alert.accuracy_m, wearable_id, supabase)

class AppAlertRequest(BaseModel):
    user_id: str
    trigger_method: str
    latitude: float
    longitude: float
    accuracy_m: float = None
    emergency_contacts: list[str] = None

@router.post("/app", response_model=AlertResponse)
async def trigger_app_alert(alert: AppAlertRequest, supabase: Client = Depends(get_supabase)):
    return await process_alert(
        alert.user_id,
        alert.trigger_method,
        alert.latitude,
        alert.longitude,
        alert.accuracy_m,
        None,
        supabase,
        provided_contacts=alert.emergency_contacts
    )

import logging
logger = logging.getLogger(__name__)

async def process_alert(
    user_id: str,
    trigger_method: str,
    lat: float,
    lng: float,
    accuracy: float,
    wearable_id: str,
    supabase: Client,
    provided_contacts: list[str] = None
) -> AlertResponse:
    logger.info("Processing alert for user %s via %s (lat: %s, lng: %s)", user_id, trigger_method, lat, lng)
    try:
        user_res = supabase.table("users").select("full_name").eq("id", user_id).execute()
        user_name = user_res.data[0]["full_name"] if user_res.data else "SafeLink User"
    except Exception as e:
        logger.error("[DB ERROR] Failed to fetch user profile %s: %s", user_id, e)
        user_name = "SafeLink User"
    
    event_data = {
        "user_id": user_id,
        "trigger_method": trigger_method,
        "latitude": lat,
        "longitude": lng,
        "location_accuracy_m": accuracy,
        "status": "active"
    }
    if wearable_id:
        event_data["wearable_device_id"] = wearable_id
        
    try:
        logger.info("[DB INSERT] Inserting into panic_events: %s", event_data)
        event_res = supabase.table("panic_events").insert(event_data).execute()
        event_id = event_res.data[0]["id"]
        logger.info("[DB SUCCESS] Panic event created with ID: %s", event_id)
    except Exception as e:
        logger.error("[DB ERROR] Failed to insert panic_event: %s", e)
        raise HTTPException(status_code=500, detail=f"Database error inserting panic event: {e}")
    
    # 1. Collect emergency contact phone numbers
    phones_to_notify = []
    if provided_contacts:
        phones_to_notify.extend([p for p in provided_contacts if p and p.strip()])

    try:
        # Check database for all contacts registered for this user (not strictly requiring consent_status='accepted')
        contacts_res = supabase.table("emergency_contacts").select("phone_number, consent_status").eq("user_id", user_id).execute()
        for c in contacts_res.data or []:
            if c.get("phone_number") and c.get("consent_status") != "declined":
                phones_to_notify.append(c["phone_number"].strip())
    except Exception as c_err:
        logger.warning("[CONTACTS DB NOTICE] Could not query emergency_contacts: %s", c_err)

    # 2. Format phone numbers into standard E.164 (e.g. 0712345678 -> +254712345678)
    formatted_phones = []
    seen = set()
    for raw in phones_to_notify:
        p = raw.strip().replace(" ", "").replace("-", "")
        if p.startswith("0") and len(p) == 10:
            p = "+254" + p[1:]
        elif p.startswith("254") and len(p) == 12:
            p = "+" + p
        elif not p.startswith("+") and len(p) == 9:
            p = "+254" + p
        if p and p not in seen:
            seen.add(p)
            formatted_phones.append(p)

    sms_results = {}
    if formatted_phones:
        sms_results = sms_service.notify_emergency_contacts(formatted_phones, user_name, lat, lng, panic_event_id=event_id)
        logger.info("[SMS ALERT] Dispatched to user's emergency contacts: %s -> %s", formatted_phones, sms_results)
    else:
        logger.warning("[SMS ALERT] No emergency contacts set for user %s", user_id)
    
    police_res = sms_service.notify_police(user_name, lat, lng, panic_event_id=event_id)
    if police_res:
        sms_results.update(police_res)
    
    supabase.table("panic_events").update({
        "emergency_contacts_notified": True if formatted_phones else False,
        "hotline_notified": True if police_res else False
    }).eq("id", event_id).execute()
    
    responders = find_nearby_responders(supabase, lat, lng, 1000.0)
    
    if responders:
        alerts_to_insert = [{
            "panic_event_id": event_id,
            "responder_id": r["id"],
            "distance_m": r.get("distance_m", 350.0)
        } for r in responders]
        
        try:
            supabase.table("responder_alerts").insert(alerts_to_insert).execute()
            supabase.table("panic_events").update({
                "community_responders_alerted": len(responders)
            }).eq("id", event_id).execute()
            logger.info("[RESPONDERS] Logged alerts for %d community responders", len(responders))
        except Exception as r_err:
            logger.warning("[RESPONDER DB NOTICE] Could not insert responder_alerts: %s", r_err)

    tokens = [r["push_token"] for r in responders if r.get("push_token")]
    if tokens:
        try:
            await push_service.notify_responders(tokens, user_name, lat, lng)
        except Exception as p_err:
            logger.warning("[PUSH NOTICE] Failed sending push to responders: %s", p_err)
    
    return AlertResponse(
        success=True,
        panic_event_id=event_id,
        sms_results=sms_results,
        responders_alerted=len(responders)
    )

class StatusUpdate(BaseModel):
    status: str

@router.patch("/{panic_event_id}/status")
async def update_panic_status(panic_event_id: str, status_update: StatusUpdate, supabase: Client = Depends(get_supabase)):
    valid_statuses = ['active', 'acknowledged', 'resolved', 'false_alarm']
    if status_update.status not in valid_statuses:
        raise HTTPException(status_code=400, detail="Invalid status")
        
    update_data = {"status": status_update.status}
    if status_update.status in ['resolved', 'false_alarm']:
        update_data["resolved_at"] = datetime.datetime.utcnow().isoformat()
        
    res = supabase.table("panic_events").update(update_data).eq("id", panic_event_id).execute()
    if not res.data:
        raise HTTPException(status_code=404, detail="Panic event not found")
        
    return {"success": True, "event": res.data[0]}

from fastapi.responses import HTMLResponse


def get_tracking_html(
    lat: float,
    lng: float,
    user_name: str,
    status: str,
    panic_event_id: str = "",
    mapbox_token: str = "",
) -> str:
    from pathlib import Path
    import html as html_lib
    import json as json_lib

    track_path = Path(__file__).resolve().parent.parent.parent.parent / "docs" / "track.html"
    if track_path.exists():
        template = track_path.read_text(encoding="utf-8")
    else:
        template = """<!DOCTYPE html><html><head><meta charset="utf-8"><title>SafeGuard Tracking</title></head><body><h1>Emergency SOS Tracking</h1></body></html>"""

    js_name = json_lib.dumps(user_name)[1:-1].replace("'", r"\'").replace("</", r"<\/")
    token = mapbox_token or os.getenv("MAPBOX_WEB_TOKEN") or os.getenv("MAPBOX_ACCESS_TOKEN") or "pk.eyJ1Ijoiam95a2lwa2VtYm9pIiwiYSI6ImNtY2J2MmlpZTAxbWIya3NhaWV1aTh5MTkifQ.-nLBrGjd639RrXjdXHq3HA"

    html = template.replace("-1.2907850038543573", f"{lat:.6f}")
    html = html.replace("36.78176897301627", f"{lng:.6f}")
    html = html.replace("'Joy Chepchumba'", f"'{js_name}'")
    html = html.replace("Joy Chepchumba", html_lib.escape(user_name))
    if panic_event_id:
        html = html.replace(
            "const incidentId = params.get('id') || params.get('session') || '';",
            f"const incidentId = '{html_lib.escape(panic_event_id)}';"
        )
    if token:
        html = html.replace(
            "const mapboxToken = 'pk.eyJ1Ijoiam95a2lwa2VtYm9pIiwiYSI6ImNtY2J2MmlpZTAxbWIya3NhaWV1aTh5MTkifQ.-nLBrGjd639RrXjdXHq3HA';",
            f"const mapboxToken = '{token}';"
        )

    return html




@router.get("/event/{panic_event_id}")
async def get_panic_event(panic_event_id: str, supabase: Client = Depends(get_supabase)):
    """Polled by the live tracking page every few seconds for the latest position/status."""
    res = supabase.table("panic_events").select("id,latitude,longitude,status,location_accuracy_m").eq("id", panic_event_id).execute()
    if not res.data:
        raise HTTPException(status_code=404, detail="Panic event not found")
    return {"success": True, "event": res.data[0]}


@router.get("/history")
async def get_user_alert_history(user_id: str = None, supabase: Client = Depends(get_supabase)):
    """Retrieves alert history for a user with fallback sample events if none exist."""
    events = []
    if user_id:
        try:
            res = supabase.table("panic_events").select("*").eq("user_id", user_id).order("triggered_at", desc=True).limit(50).execute()
            events = res.data or []
        except Exception as e:
            logger.warning("[ALERT HISTORY SELECT NOTICE] %s", e)

    # If no events found or database not initialized, return realistic demonstration history
    if not events:
        now = datetime.datetime.utcnow()
        events = [
            {
                "id": "demo-event-001",
                "user_id": user_id or "user_demo",
                "triggered_at": (now - datetime.timedelta(hours=2, minutes=15)).isoformat(),
                "trigger_method": "app_shake",
                "status": "resolved",
                "resolved_at": (now - datetime.timedelta(hours=2, minutes=1)).isoformat(),
                "latitude": -1.2921,
                "longitude": 36.8219,
                "location_accuracy_m": 8.5,
                "is_location_anonymised": False,
                "emergency_contacts_notified": True,
                "hotline_notified": False,
                "community_responders_alerted": 2,
                "notes": "Emergency resolved by community responder",
                "created_at": (now - datetime.timedelta(hours=2, minutes=15)).isoformat(),
                "updated_at": (now - datetime.timedelta(hours=2, minutes=1)).isoformat(),
            },
            {
                "id": "demo-event-002",
                "user_id": user_id or "user_demo",
                "triggered_at": (now - datetime.timedelta(days=1, hours=5)).isoformat(),
                "trigger_method": "voice_keyword",
                "status": "resolved",
                "resolved_at": (now - datetime.timedelta(days=1, hours=4, minutes=50)).isoformat(),
                "latitude": -1.2864,
                "longitude": 36.8172,
                "location_accuracy_m": 12.0,
                "is_location_anonymised": False,
                "emergency_contacts_notified": True,
                "hotline_notified": False,
                "community_responders_alerted": 1,
                "notes": "Voice SOS triggered successfully",
                "created_at": (now - datetime.timedelta(days=1, hours=5)).isoformat(),
                "updated_at": (now - datetime.timedelta(days=1, hours=4, minutes=50)).isoformat(),
            },
            {
                "id": "demo-event-003",
                "user_id": user_id or "user_demo",
                "triggered_at": (now - datetime.timedelta(days=3, hours=10)).isoformat(),
                "trigger_method": "app",
                "status": "false_alarm",
                "resolved_at": (now - datetime.timedelta(days=3, hours=9, minutes=58)).isoformat(),
                "latitude": -1.3001,
                "longitude": 36.7905,
                "location_accuracy_m": 15.0,
                "is_location_anonymised": True,
                "emergency_contacts_notified": False,
                "hotline_notified": False,
                "community_responders_alerted": 0,
                "notes": "User cancelled countdown within grace period",
                "created_at": (now - datetime.timedelta(days=3, hours=10)).isoformat(),
                "updated_at": (now - datetime.timedelta(days=3, hours=9, minutes=58)).isoformat(),
            }
        ]

    return {"success": True, "data": events}


class LocationUpdate(BaseModel):
    latitude: float
    longitude: float
    accuracy_m: float = None


@router.post("/{panic_event_id}/location")
async def update_panic_location(panic_event_id: str, loc: LocationUpdate, supabase: Client = Depends(get_supabase)):
    """Called by the app while an alert is active so the tracking link follows the user live."""
    data = {"latitude": loc.latitude, "longitude": loc.longitude}
    if loc.accuracy_m is not None:
        data["location_accuracy_m"] = loc.accuracy_m
    res = supabase.table("panic_events").update(data).eq("id", panic_event_id).eq("status", "active").execute()
    return {"success": bool(res.data)}


@router.get("/track/live", response_class=HTMLResponse)
async def view_live_tracking(lat: float = -1.2907850038543573, lng: float = 36.78176897301627, name: str = "SafeGuard User"):
    mapbox_token = os.getenv("MAPBOX_WEB_TOKEN") or os.getenv("MAPBOX_ACCESS_TOKEN") or os.getenv("MAPBOX_TOKEN") or "pk.eyJ1Ijoiam95a2lwa2VtYm9pIiwiYSI6ImNtY2J2MmlpZTAxbWIya3NhaWV1aTh5MTkifQ.-nLBrGjd639RrXjdXHq3HA"
    return get_tracking_html(
        lat=lat,
        lng=lng,
        user_name=name,
        status="ACTIVE",
        panic_event_id="",
        mapbox_token=mapbox_token,
    )


@router.get("/track/{panic_event_id}", response_class=HTMLResponse)
async def view_3d_tracking(panic_event_id: str, supabase: Client = Depends(get_supabase)):
    mapbox_token = os.getenv("MAPBOX_WEB_TOKEN") or os.getenv("MAPBOX_ACCESS_TOKEN") or os.getenv("MAPBOX_TOKEN") or "pk.eyJ1Ijoiam95a2lwa2VtYm9pIiwiYSI6ImNtY2J2MmlpZTAxbWIya3NhaWV1aTh5MTkifQ.-nLBrGjd639RrXjdXHq3HA"
    
    lat = -1.2907850038543573
    lng = 36.78176897301627
    status = "ACTIVE"
    user_name = "SafeGuard User in Distress"
    
    try:
        event_res = supabase.table("panic_events").select("*").eq("id", panic_event_id).execute()
        if event_res.data:
            event = event_res.data[0]
            lat = event.get("latitude", lat)
            lng = event.get("longitude", lng)
            status = event.get("status", "active").upper()
            user_id = event.get("user_id")
            if user_id:
                try:
                    u_res = supabase.table("users").select("full_name").eq("id", user_id).execute()
                    if u_res.data:
                        user_name = u_res.data[0].get("full_name", user_name)
                except Exception:
                    pass
    except Exception as err:
        logger.warning(f"Notice querying panic event {panic_event_id}: {err}")

    return get_tracking_html(
        lat=lat,
        lng=lng,
        user_name=user_name,
        status=status,
        panic_event_id=panic_event_id,
        mapbox_token=mapbox_token,
    )


@router.post("/anonymise-locations")
async def trigger_location_anonymisation(supabase: Client = Depends(get_supabase)):
    """Triggers 24-hour location anonymisation for locations, users, and panic events."""
    result = anonymise_24h_location_data(supabase)
    return {"success": True, "result": result}


@router.get("/anonymisation-status")
async def get_anonymisation_status(supabase: Client = Depends(get_supabase)):
    """Checks the current anonymisation state across tables."""
    now = datetime.datetime.now(datetime.timezone.utc)
    cutoff = now - datetime.timedelta(hours=24)
    cutoff_iso = cutoff.isoformat()
    
    # Check unanonymised old panic events
    pe_old = []
    try:
        res = supabase.table("panic_events") \
            .select("id, status, triggered_at, is_location_anonymised") \
            .lt("triggered_at", cutoff_iso) \
            .eq("is_location_anonymised", False) \
            .execute()
        pe_old = res.data or []
    except Exception:
        pass
        
    return {
        "status": "active",
        "current_time_utc": now.isoformat(),
        "24h_cutoff_utc": cutoff_iso,
        "pending_panic_events_to_anonymise": len(pe_old),
    }





