import os
import datetime
from fastapi import APIRouter, HTTPException, Depends, Query
from supabase import create_client, Client
from app.models.schemas import (
    UserRequest,
    ResponderStatusUpdate,
    SetEmergencyPasswordRequest,
    VerifyEmergencyPasswordRequest,
    UserProfileResponse,
)
from app.core.security import hash_emergency_password, verify_emergency_password

router = APIRouter(prefix="/users", tags=["users"])

def get_supabase() -> Client:
    url = os.getenv("SUPABASE_URL", "")
    key = os.getenv("SUPABASE_SERVICE_KEY", os.getenv("SUPABASE_ANON_KEY", ""))
    return create_client(url, key)

@router.get("/me", response_model=UserProfileResponse)
def get_user_profile(user_id: str = Query(..., description="Supabase Auth User UUID"), supabase: Client = Depends(get_supabase)):
    res = supabase.table("users").select("*").eq("id", user_id).execute()
    if not res.data:
        raise HTTPException(status_code=404, detail="User profile not found")
    
    user = res.data[0]
    return UserProfileResponse(
        id=user["id"],
        full_name=user.get("full_name", ""),
        phone_number=user.get("phone_number", ""),
        email=user.get("email"),
        is_community_responder=user.get("is_community_responder", False),
        responder_status=user.get("responder_status"),
        has_emergency_password=bool(user.get("emergency_password_hash")),
        has_wearable=user.get("has_wearable", False),
        created_at=user.get("created_at"),
    )

@router.put("/emergency-password")
def set_emergency_password(req: SetEmergencyPasswordRequest, supabase: Client = Depends(get_supabase)):
    """Sets or updates the secret emergency duress password/PIN."""
    hashed = hash_emergency_password(req.emergency_password)
    res = supabase.table("users").update({
        "emergency_password_hash": hashed,
        "updated_at": datetime.datetime.utcnow().isoformat()
    }).eq("id", req.user_id).execute()
    
    if not res.data:
        raise HTTPException(status_code=404, detail="User not found")
    return {"success": True, "message": "Emergency duress password set successfully"}

@router.post("/emergency-password/verify")
def check_emergency_password(req: VerifyEmergencyPasswordRequest, supabase: Client = Depends(get_supabase)):
    """Verifies if the submitted password is the secret duress password."""
    res = supabase.table("users").select("emergency_password_hash").eq("id", req.user_id).execute()
    if not res.data or not res.data[0].get("emergency_password_hash"):
        return {"is_emergency_duress": False}
        
    stored_hash = res.data[0]["emergency_password_hash"]
    is_match = verify_emergency_password(req.password_attempt, stored_hash)
    return {"is_emergency_duress": is_match}

@router.post("/register-responder")
def register_responder(req: UserRequest, supabase: Client = Depends(get_supabase)):
    """Opts in the user as a community responder."""
    res = supabase.table("users").update({
        "is_community_responder": True,
        "responder_status": "available",
        "responder_opted_in_at": datetime.datetime.utcnow().isoformat(),
        "updated_at": datetime.datetime.utcnow().isoformat()
    }).eq("id", req.user_id).execute()
    
    if not res.data:
        raise HTTPException(status_code=404, detail="User not found")
    return {"success": True, "user": res.data[0]}

@router.post("/opt-out-responder")
def opt_out_responder(req: UserRequest, supabase: Client = Depends(get_supabase)):
    """Opts out the user from community response."""
    res = supabase.table("users").update({
        "is_community_responder": False,
        "responder_status": "unavailable",
        "responder_opted_out_at": datetime.datetime.utcnow().isoformat(),
        "updated_at": datetime.datetime.utcnow().isoformat()
    }).eq("id", req.user_id).execute()
    
    if not res.data:
        raise HTTPException(status_code=404, detail="User not found")
    return {"success": True, "user": res.data[0]}

@router.patch("/responder-status")
def update_responder_status(req: ResponderStatusUpdate, supabase: Client = Depends(get_supabase)):
    if req.status not in ["available", "responding", "unavailable"]:
        raise HTTPException(status_code=400, detail="Invalid status. Must be 'available', 'responding', or 'unavailable'")
        
    res = supabase.table("users").update({
        "responder_status": req.status,
        "updated_at": datetime.datetime.utcnow().isoformat()
    }).eq("id", req.user_id).execute()
    
    if not res.data:
        raise HTTPException(status_code=404, detail="User not found")
    return {"success": True, "user": res.data[0]}
