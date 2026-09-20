import os
from fastapi import APIRouter, Depends
from supabase import create_client, Client
from app.services.location_service import find_nearby_responders

router = APIRouter(prefix="/responders", tags=["responders"])

def get_supabase() -> Client:
    url = os.getenv("SUPABASE_URL", "")
    key = os.getenv("SUPABASE_SERVICE_KEY", "")
    return create_client(url, key)

@router.get("/nearby")
def get_nearby_responders(lat: float, lng: float, radius_m: float = 1000.0, supabase: Client = Depends(get_supabase)):
    responders = find_nearby_responders(supabase, lat, lng, radius_m)
    return {"success": True, "responders": responders}
