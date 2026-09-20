import math

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
        .select("id, full_name, push_token") \
        .eq("is_community_responder", True) \
        .eq("responder_status", "available") \
        .execute()
        
    responders = res.data
    if not responders:
        return []
        
    responder_ids = [r["id"] for r in responders]
    
    logs_res = supabase_client.table("realtime_gps_logs") \
        .select("user_id, latitude, longitude") \
        .in_("user_id", responder_ids) \
        .order("recorded_at", desc=True) \
        .execute()
        
    latest_locations = {}
    for log in logs_res.data:
        uid = log["user_id"]
        if uid not in latest_locations:
            latest_locations[uid] = log
            
    nearby = []
    for r in responders:
        loc = latest_locations.get(r["id"])
        if loc:
            dist = haversine_distance(lat, lng, loc["latitude"], loc["longitude"])
            if dist <= radius_m:
                r["distance_m"] = dist
                nearby.append(r)
                
    return nearby
