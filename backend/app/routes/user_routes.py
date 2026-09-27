import os
import datetime
import logging
from fastapi import APIRouter, HTTPException, Depends, Query
from supabase import create_client, Client
from app.models.schemas import (
    UserRequest,
    ResponderStatusUpdate,
    SetEmergencyPasswordRequest,
    VerifyEmergencyPasswordRequest,
    UserProfileResponse,
    CreateUserProfileRequest,
    RegisterUserRequest,
    UpdateUserProfileRequest,
    EmergencyContactCreateRequest,
)
from app.core.security import hash_emergency_password, verify_emergency_password

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/users", tags=["users"])

DEFAULT_SUPABASE_URL = "https://afagwdhpjnnbueiyjmde.supabase.co"
DEFAULT_SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFmYWd3ZGhwam5uYnVlaXlqbWRlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk5MTkzMzUsImV4cCI6MjEwNTQ5NTMzNX0.Qw_rs_KJOZF8RkXWW62QBKnSafzJFkt9YBPqCRo9mlA"

def get_supabase() -> Client:
    url = os.getenv("SUPABASE_URL") or DEFAULT_SUPABASE_URL
    key = os.getenv("SUPABASE_SERVICE_KEY") or os.getenv("SUPABASE_ANON_KEY") or DEFAULT_SUPABASE_KEY
    return create_client(url, key)


@router.post("/register")
def register_user(req: RegisterUserRequest, supabase: Client = Depends(get_supabase)):
    """Primary user registration endpoint called from Flutter app."""
    print("\n" + "=" * 60)
    print(">>> [INCOMING APP REGISTRATION] POST /users/register <<<")
    print(f"  Full Name:       {req.full_name}")
    print(f"  Phone:           {req.phone_number}")
    print(f"  Email:           {req.email}")
    print(f"  Responder Opt-in:{req.is_community_responder}")
    print("=" * 60)

    logger.info("Incoming registration: %s (%s)", req.full_name, req.email)

    user_id = None
    try:
        auth_res = supabase.auth.sign_up({
            "email": req.email.strip(),
            "password": req.password,
            "options": {
                "data": {
                    "full_name": req.full_name.strip(),
                    "phone": req.phone_number.strip(),
                }
            }
        })
        if auth_res.user:
            user_id = auth_res.user.id
            print(f"[AUTH] Supabase Auth account created with ID: {user_id}")
    except Exception as e:
        print(f"[AUTH NOTICE] Supabase Auth sign up notice: {e}")

    if not user_id:
        import uuid
        user_id = str(uuid.uuid4())
        print(f"[AUTH] Using generated UUID: {user_id}")

    user_record = {
        "id": user_id,
        "full_name": req.full_name.strip(),
        "phone_number": req.phone_number.strip(),
        "email": req.email.strip(),
        "is_community_responder": req.is_community_responder,
        "responder_status": "available" if req.is_community_responder else None,
        "responder_opted_in_at": datetime.datetime.utcnow().isoformat() if req.is_community_responder else None,
        "updated_at": datetime.datetime.utcnow().isoformat(),
    }
    if req.emergency_password:
        user_record["emergency_password_hash"] = hash_emergency_password(req.emergency_password)

    try:
        supabase.table("users").upsert(user_record).execute()
        print(">>> [DB INSERT SUCCESS] Successfully saved user to public.users table! <<<")
        print("=" * 60 + "\n")
        return {
            "success": True,
            "user_id": user_id,
            "message": "User registered and profile created in database.",
            "data": user_record
        }
    except Exception as e:
        print(f">>> [DB INSERT ERROR] Failed saving to public.users: {e} <<<")
        print("Tip: Make sure you ran setup_supabase.sql in Supabase SQL editor to allow inserts.")
        print("=" * 60 + "\n")
        return {
            "success": True,
            "user_id": user_id,
            "message": "User registered.",
            "db_error": str(e),
            "data": user_record
        }

@router.post("/profile")
def create_or_sync_user_profile(req: CreateUserProfileRequest, supabase: Client = Depends(get_supabase)):
    """Receives profile info upon registration and ensures public.users table is populated."""
    logger.info("==================================================")
    logger.info("[USER REGISTRATION] Received profile sync request:")
    logger.info("  user_id:  %s", req.user_id)
    logger.info("  name:     %s", req.full_name)
    logger.info("  phone:    %s", req.phone_number)
    logger.info("  email:    %s", req.email)
    logger.info("  responder:%s", req.is_community_responder)
    logger.info("==================================================")

    data = {
        "id": req.user_id,
        "full_name": req.full_name.strip(),
        "phone_number": req.phone_number.strip(),
        "email": req.email.strip() if req.email else None,
        "is_community_responder": req.is_community_responder,
        "responder_status": "available" if req.is_community_responder else None,
        "updated_at": datetime.datetime.utcnow().isoformat(),
    }
    if req.emergency_password:
        data["emergency_password_hash"] = hash_emergency_password(req.emergency_password)

    try:
        res = supabase.table("users").upsert(data).execute()
        logger.info("[DB INSERT SUCCESS] Successfully saved user profile to public.users!")
        return {"success": True, "message": "User profile successfully saved to database.", "data": res.data}
    except Exception as e:
        logger.error("[DB INSERT ERROR] Failed saving user %s to public.users: %s", req.user_id, e)
        raise HTTPException(status_code=500, detail=f"Database insert error: {e}")

@router.get("/me", response_model=UserProfileResponse)
def get_user_profile(user_id: str = Query(..., description="Supabase Auth User UUID"), supabase: Client = Depends(get_supabase)):
    try:
        logger.info("[DB SELECT] Fetching profile for user_id=%s", user_id)
        res = supabase.table("users").select("*").eq("id", user_id).execute()
    except Exception as e:
        logger.error("[DB ERROR] Error fetching user %s: %s", user_id, e)
        raise HTTPException(status_code=500, detail=f"Database query error: {e}")
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
    try:
        logger.info("[DB UPDATE] Setting emergency password for user_id=%s", req.user_id)
        res = supabase.table("users").update({
            "emergency_password_hash": hashed,
            "updated_at": datetime.datetime.utcnow().isoformat()
        }).eq("id", req.user_id).execute()
    except Exception as e:
        logger.error("[DB ERROR] Failed to update emergency password for user %s: %s", req.user_id, e)
        raise HTTPException(status_code=500, detail=f"Database error updating emergency password: {e}")
    
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

@router.patch("/profile")
@router.put("/profile")
def update_user_profile(req: UpdateUserProfileRequest, supabase: Client = Depends(get_supabase)):
    """Allows user to update profile details (name, phone, responder status, duress password)."""
    update_data = {"updated_at": datetime.datetime.utcnow().isoformat()}
    if req.full_name is not None and req.full_name.strip():
        update_data["full_name"] = req.full_name.strip()
    if req.phone_number is not None and req.phone_number.strip():
        update_data["phone_number"] = req.phone_number.strip()
    if req.is_community_responder is not None:
        update_data["is_community_responder"] = req.is_community_responder
        update_data["responder_status"] = "available" if req.is_community_responder else "unavailable"
        if req.is_community_responder:
            update_data["responder_opted_in_at"] = datetime.datetime.utcnow().isoformat()
        else:
            update_data["responder_opted_out_at"] = datetime.datetime.utcnow().isoformat()
    if req.emergency_password:
        update_data["emergency_password_hash"] = hash_emergency_password(req.emergency_password)

    try:
        res = supabase.table("users").update(update_data).eq("id", req.user_id).execute()
        logger.info("[PROFILE UPDATE] Successfully updated profile for user_id=%s", req.user_id)
        return {"success": True, "message": "Profile updated successfully", "data": res.data}
    except Exception as e:
        logger.error("[PROFILE UPDATE ERROR] Error updating user %s: %s", req.user_id, e)
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/contacts")
def get_user_contacts(user_id: str = Query(..., description="User ID"), supabase: Client = Depends(get_supabase)):
    """Fetches emergency contacts for the user with backend resilience."""
    try:
        res = supabase.table("emergency_contacts").select("*").eq("user_id", user_id).order("created_at").execute()
        return {"success": True, "data": res.data or []}
    except Exception as e:
        logger.error("[CONTACTS SELECT ERROR] %s", e)
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/contacts")
def add_user_contact(req: EmergencyContactCreateRequest, supabase: Client = Depends(get_supabase)):
    """Adds a new emergency contact via backend (bypasses client-side RLS hurdles)."""
    contact_data = {
        "user_id": req.user_id,
        "contact_name": req.contact_name.strip(),
        "phone_number": req.phone_number.strip(),
        "email": req.email.strip() if req.email and req.email.strip() else None,
        "consent_status": "pending",
        "created_at": datetime.datetime.utcnow().isoformat(),
        "updated_at": datetime.datetime.utcnow().isoformat(),
    }
    try:
        res = supabase.table("emergency_contacts").insert(contact_data).execute()
        logger.info("[CONTACT INSERT SUCCESS] Added emergency contact: %s for user: %s", req.contact_name, req.user_id)
        return {"success": True, "message": "Emergency contact added successfully", "data": res.data}
    except Exception as e:
        logger.error("[CONTACT INSERT ERROR] %s", e)
        raise HTTPException(status_code=500, detail=str(e))

@router.delete("/contacts/{contact_id}")
def delete_user_contact(contact_id: str, user_id: str = Query(None), supabase: Client = Depends(get_supabase)):
    """Deletes an emergency contact."""
    try:
        query = supabase.table("emergency_contacts").delete().eq("id", contact_id)
        if user_id:
            query = query.eq("user_id", user_id)
        query.execute()
        return {"success": True, "message": "Contact deleted successfully"}
    except Exception as e:
        logger.error("[CONTACT DELETE ERROR] %s", e)
        raise HTTPException(status_code=500, detail=str(e))

