import math
import logging
from datetime import datetime, timezone, timedelta

logger = logging.getLogger(__name__)

def haversine_distance(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    R = 6371000.0
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lng2 - lng1)
    
    a = math.sin(delta_phi / 2.0) ** 2 + \
        math.cos(phi1) * math.cos(phi2) * \
        math.sin(delta_lambda / 2.0) ** 2
        
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c

def find_nearby_responders(supabase_client, lat: float, lng: float, radius_m: float = 1000.0) -> list[dict]:
    res = supabase_client.table("users") \
        .select("id, full_name, push_token, last_latitude, last_longitude, is_location_anonymised") \
        .eq("is_community_responder", True) \
        .eq("responder_status", "available") \
        .execute()
        
    responders = res.data or []
    if not responders:
        return []
        
    responder_ids = [r["id"] for r in responders]
    
    latest_locations = {}
    
    # 1. First check if user table itself has valid non-anonymised location
    for r in responders:
        if (
            r.get("last_latitude") is not None 
            and r.get("last_longitude") is not None 
            and not r.get("is_location_anonymised", False)
        ):
            latest_locations[r["id"]] = {
                "user_id": r["id"],
                "latitude": r["last_latitude"],
                "longitude": r["last_longitude"]
            }
            
    # 2. For remaining responders, query locations table or realtime_gps_logs
    missing_ids = [uid for uid in responder_ids if uid not in latest_locations]
    if missing_ids:
        try:
            locs_res = supabase_client.table("locations") \
                .select("user_id, latitude, longitude") \
                .in_("user_id", missing_ids) \
                .eq("is_anonymised", False) \
                .not_.is_("latitude", "null") \
                .order("recorded_at", desc=True) \
                .execute()
            for log in (locs_res.data or []):
                uid = log["user_id"]
                if uid not in latest_locations:
                    latest_locations[uid] = log
        except Exception:
            pass
            
        remaining_ids = [uid for uid in missing_ids if uid not in latest_locations]
        if remaining_ids:
            try:
                logs_res = supabase_client.table("realtime_gps_logs") \
                    .select("user_id, latitude, longitude") \
                    .in_("user_id", remaining_ids) \
                    .eq("is_anonymised", False) \
                    .order("recorded_at", desc=True) \
                    .execute()
                for log in (logs_res.data or []):
                    uid = log["user_id"]
                    if uid not in latest_locations:
                        latest_locations[uid] = log
            except Exception:
                pass
            
    nearby = []
    for r in responders:
        loc = latest_locations.get(r["id"])
        if loc and loc.get("latitude") is not None and loc.get("longitude") is not None:
            dist = haversine_distance(lat, lng, loc["latitude"], loc["longitude"])
            if dist <= radius_m:
                r["distance_m"] = dist
                nearby.append(r)
                
    return nearby

def save_location_log(
    supabase_client,
    user_id: str,
    lat: float,
    lng: float,
    accuracy_m: float = None,
    panic_event_id: str = None
) -> dict:
    """Records a location ping to both locations and realtime_gps_logs and updates user last_location."""
    now_iso = datetime.now(timezone.utc).isoformat()
    entry = {
        "user_id": user_id,
        "latitude": lat,
        "longitude": lng,
        "accuracy_m": accuracy_m,
        "recorded_at": now_iso,
        "is_anonymised": False,
    }
    if panic_event_id:
        entry["panic_event_id"] = panic_event_id
        
    results = {"locations_saved": False, "realtime_saved": False, "user_updated": False}
    
    # 1. Insert into locations table
    try:
        supabase_client.table("locations").insert(entry).execute()
        results["locations_saved"] = True
    except Exception as e:
        logger.debug(f"[LocationService] Could not insert into locations table: {e}")

    # 2. Insert into realtime_gps_logs table
    try:
        supabase_client.table("realtime_gps_logs").insert(entry).execute()
        results["realtime_saved"] = True
    except Exception as e:
        logger.debug(f"[LocationService] Could not insert into realtime_gps_logs: {e}")

    # 3. Update public.users
    try:
        supabase_client.table("users").update({
            "last_latitude": lat,
            "last_longitude": lng,
            "last_location_updated_at": now_iso,
            "is_location_anonymised": False
        }).eq("id", user_id).execute()
        results["user_updated"] = True
    except Exception as e:
        logger.debug(f"[LocationService] Could not update users table location: {e}")

    return results

def anonymise_24h_location_data(supabase_client) -> dict:
    """
    Anonymises GPS coordinates older than 24 hours across:
      1. public.panic_events (resolved or triggered > 24 hours ago)
      2. public.locations (recorded > 24 hours ago)
      3. public.realtime_gps_logs (recorded > 24 hours ago)
      4. public.users (last known location > 24 hours ago)
      
    Complies with REQ-F10 and Chapter 5 privacy specifications.
    """
    now = datetime.now(timezone.utc)
    cutoff = now - timedelta(hours=24)
    cutoff_iso = cutoff.isoformat()
    now_iso = now.isoformat()

    stats = {
        "success": True,
        "anonymised_at": now_iso,
        "cutoff_threshold": cutoff_iso,
        "panic_events_anonymised": 0,
        "locations_anonymised": 0,
        "realtime_gps_logs_anonymised": 0,
        "users_anonymised": 0
    }

    # First attempt RPC if available on Postgres
    try:
        rpc_res = supabase_client.rpc("anonymise_24h_location_data", {}).execute()
        if rpc_res and rpc_res.data:
            logger.info(f"[ANONYMISATION] Postgres RPC executed: {rpc_res.data}")
            return rpc_res.data
    except Exception as e:
        logger.debug(f"[ANONYMISATION] RPC call skipped or not present: {e}")

    # Direct fallback execution for panic_events
    try:
        # Anonymise resolved events > 24h old
        res_resolved = supabase_client.table("panic_events") \
            .update({
                "latitude": None,
                "longitude": None,
                "location_accuracy_m": None,
                "is_location_anonymised": True,
                "anonymised_at": now_iso
            }) \
            .lt("resolved_at", cutoff_iso) \
            .eq("is_location_anonymised", False) \
            .execute()
        count_res = len(res_resolved.data) if res_resolved.data else 0
        
        # Anonymise old triggered events > 24h old
        res_trig = supabase_client.table("panic_events") \
            .update({
                "latitude": None,
                "longitude": None,
                "location_accuracy_m": None,
                "is_location_anonymised": True,
                "anonymised_at": now_iso
            }) \
            .lt("triggered_at", cutoff_iso) \
            .eq("is_location_anonymised", False) \
            .execute()
        count_trig = len(res_trig.data) if res_trig.data else 0
        stats["panic_events_anonymised"] = count_res + count_trig
    except Exception as e:
        logger.warning(f"[ANONYMISATION] Error anonymising panic_events: {e}")

    # Direct fallback execution for locations table
    try:
        res_loc = supabase_client.table("locations") \
            .update({
                "latitude": None,
                "longitude": None,
                "accuracy_m": None,
                "is_anonymised": True,
                "anonymised_at": now_iso
            }) \
            .lt("recorded_at", cutoff_iso) \
            .eq("is_anonymised", False) \
            .execute()
        stats["locations_anonymised"] = len(res_loc.data) if res_loc.data else 0
    except Exception as e:
        logger.debug(f"[ANONYMISATION] Note: locations table update: {e}")

    # Direct fallback execution for realtime_gps_logs table
    try:
        res_gps = supabase_client.table("realtime_gps_logs") \
            .update({
                "latitude": None,
                "longitude": None,
                "accuracy_m": None,
                "is_anonymised": True
            }) \
            .lt("recorded_at", cutoff_iso) \
            .eq("is_anonymised", False) \
            .execute()
        stats["realtime_gps_logs_anonymised"] = len(res_gps.data) if res_gps.data else 0
    except Exception as e:
        logger.debug(f"[ANONYMISATION] Note: realtime_gps_logs update: {e}")

    # Direct fallback execution for users table
    try:
        # Check users where last_location_updated_at < 24h ago
        res_users = supabase_client.table("users") \
            .update({
                "last_latitude": None,
                "last_longitude": None,
                "is_location_anonymised": True,
                "anonymised_at": now_iso
            }) \
            .lt("last_location_updated_at", cutoff_iso) \
            .not_.is_("last_latitude", "null") \
            .execute()
        stats["users_anonymised"] = len(res_users.data) if res_users.data else 0
    except Exception as e:
        # If last_location_updated_at column doesn't exist yet on live DB, handle gracefully
        logger.debug(f"[ANONYMISATION] Note: users table location anonymisation: {e}")

    return stats
