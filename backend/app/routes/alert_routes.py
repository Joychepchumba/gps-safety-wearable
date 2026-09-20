import os
from fastapi import APIRouter, HTTPException, Depends
from app.models.schemas import AlertFromPendant, AlertResponse
from app.services.sms_service import SmsService
from app.services.push_service import PushService
from app.services.location_service import find_nearby_responders
from supabase import create_client, Client
from pydantic import BaseModel
import datetime

router = APIRouter(prefix="/alert", tags=["alert"])

sms_service = SmsService()
push_service = PushService()

def get_supabase() -> Client:
    url = os.getenv("SUPABASE_URL", "")
    key = os.getenv("SUPABASE_SERVICE_KEY", "")
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

@router.post("/app", response_model=AlertResponse)
async def trigger_app_alert(alert: AppAlertRequest, supabase: Client = Depends(get_supabase)):
    return await process_alert(alert.user_id, alert.trigger_method, alert.latitude, alert.longitude, alert.accuracy_m, None, supabase)

async def process_alert(user_id: str, trigger_method: str, lat: float, lng: float, accuracy: float, wearable_id: str, supabase: Client) -> AlertResponse:
    user_res = supabase.table("users").select("full_name").eq("id", user_id).execute()
    user_name = user_res.data[0]["full_name"] if user_res.data else "Unknown User"
    
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
        
    event_res = supabase.table("panic_events").insert(event_data).execute()
    event_id = event_res.data[0]["id"]
    
    contacts_res = supabase.table("emergency_contacts").select("phone_number").eq("user_id", user_id).eq("consent_status", "accepted").execute()
    phones = [c["phone_number"] for c in contacts_res.data]
    
    sms_results = {}
    if phones:
        sms_results = sms_service.notify_emergency_contacts(phones, user_name, lat, lng)
    
    police_res = sms_service.notify_police(user_name, lat, lng)
    sms_results.update(police_res)
    
    supabase.table("panic_events").update({
        "emergency_contacts_notified": True if phones else False,
        "hotline_notified": True
    }).eq("id", event_id).execute()
    
    responders = find_nearby_responders(supabase, lat, lng, 1000.0)
    
    tokens = [r["push_token"] for r in responders if r.get("push_token")]
    if tokens:
        await push_service.notify_responders(tokens, user_name, lat, lng)
        
        alerts_to_insert = [{
            "panic_event_id": event_id,
            "responder_id": r["id"],
            "distance_m": r.get("distance_m")
        } for r in responders]
        
        supabase.table("responder_alerts").insert(alerts_to_insert).execute()
        
        supabase.table("panic_events").update({
            "community_responders_alerted": len(responders)
        }).eq("id", event_id).execute()
    
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
