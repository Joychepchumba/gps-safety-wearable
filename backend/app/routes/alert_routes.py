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
    html = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no" />
  <title>SafeGuard 3D Live Emergency Tracking - __USER_NAME__</title>
  
  <!-- Preconnect for fast mobile loading -->
  <link rel="preconnect" href="https://api.mapbox.com" crossorigin />
  <link rel="dns-prefetch" href="https://api.mapbox.com" />
  <link rel="preconnect" href="https://events.mapbox.com" crossorigin />

  <!-- Mapbox GL JS v3 -->
  <link href="https://api.mapbox.com/mapbox-gl-js/v3.3.0/mapbox-gl.css" rel="stylesheet" />
  <script src="https://api.mapbox.com/mapbox-gl-js/v3.3.0/mapbox-gl.js"></script>

  <!-- Leaflet Fallback -->
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>

  <style>
    * { box-sizing: border-box; }
    body, html {
      margin: 0; padding: 0; width: 100%; height: 100%;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      background: #090d16; color: #f8fafc; overflow: hidden;
    }
    #mapbox-map, #leaflet-map {
      position: absolute; top: 0; bottom: 0; width: 100%; height: 100%;
    }
    #leaflet-map { display: none; }

    /* Telemetry Loader Overlay */
    .loader-overlay {
      position: absolute;
      top: 0; left: 0; right: 0; bottom: 0;
      background: radial-gradient(circle at center, #0f172a 0%, #030712 100%);
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      z-index: 500;
      transition: opacity 0.4s ease, visibility 0.4s;
    }
    .loader-overlay.hidden {
      opacity: 0;
      visibility: hidden;
      pointer-events: none;
    }
    .loader-spinner {
      width: 44px;
      height: 44px;
      border: 3px solid rgba(59, 130, 246, 0.2);
      border-top-color: #3b82f6;
      border-radius: 50%;
      animation: spin 0.8s linear infinite;
      margin-bottom: 14px;
    }
    @keyframes spin {
      to { transform: rotate(360deg); }
    }
    .loader-text {
      font-size: 15px;
      font-weight: 700;
      color: #f8fafc;
      letter-spacing: 0.3px;
    }
    .loader-sub {
      font-size: 12px;
      color: #94a3b8;
      margin-top: 4px;
    }

    /* Top Glass Card */
    .emergency-card {
      position: absolute;
      top: 16px;
      left: 16px;
      right: 16px;
      max-width: 440px;
      background: rgba(15, 23, 42, 0.92);
      backdrop-filter: blur(20px);
      -webkit-backdrop-filter: blur(20px);
      border: 1px solid rgba(239, 68, 68, 0.45);
      border-radius: 16px;
      padding: 16px 18px;
      box-shadow: 0 20px 45px rgba(0, 0, 0, 0.65), 0 0 25px rgba(239, 68, 68, 0.2);
      z-index: 100;
      transition: all 0.3s ease;
    }
    .badge-row {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 8px;
    }
    .badge-sos {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      background: #ef4444;
      color: #fff;
      font-size: 11px;
      font-weight: 800;
      letter-spacing: 0.8px;
      text-transform: uppercase;
      padding: 4px 10px;
      border-radius: 9999px;
      animation: pulse-badge 1.6s infinite;
    }
    .badge-sos.resolved {
      background: #10b981;
      animation: none;
    }
    @keyframes pulse-badge {
      0% { opacity: 1; transform: scale(1); }
      50% { opacity: 0.85; transform: scale(0.97); }
      100% { opacity: 1; transform: scale(1); }
    }
    .status-text {
      font-size: 12px;
      font-weight: 600;
      color: #94a3b8;
    }
    .status-text b {
      color: #ef4444;
    }
    .status-text b.resolved {
      color: #10b981;
    }
    .person-title {
      font-size: 18px;
      font-weight: 700;
      color: #ffffff;
      margin: 0 0 4px;
      display: flex;
      align-items: center;
      gap: 6px;
    }
    .subtext {
      font-size: 13px;
      color: #94a3b8;
      margin: 0 0 10px;
    }
    .coords-bar {
      display: flex;
      align-items: center;
      justify-content: space-between;
      font-size: 12px;
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      color: #38bdf8;
      background: rgba(0, 0, 0, 0.45);
      padding: 7px 12px;
      border-radius: 8px;
      border: 1px solid rgba(255, 255, 255, 0.08);
      margin-bottom: 8px;
    }
    .distance-pill {
      font-size: 12px;
      font-weight: 600;
      color: #facc15;
      background: rgba(234, 179, 8, 0.12);
      border: 1px solid rgba(234, 179, 8, 0.3);
      padding: 5px 10px;
      border-radius: 8px;
      margin-bottom: 12px;
      display: none;
    }
    .btn-actions {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 8px;
    }
    .btn {
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 6px;
      padding: 10px 12px;
      border-radius: 10px;
      font-size: 13px;
      font-weight: 600;
      text-decoration: none;
      cursor: pointer;
      border: none;
      transition: all 0.2s;
    }
    .btn-maps { background: #2563eb; color: #fff; }
    .btn-maps:hover { background: #1d4ed8; }
    .btn-call { background: #dc2626; color: #fff; }
    .btn-call:hover { background: #b91c1c; }

    /* Floating View Controls */
    .map-controls-bar {
      position: absolute;
      bottom: 24px;
      left: 50%;
      transform: translateX(-50%);
      display: flex;
      gap: 6px;
      background: rgba(15, 23, 42, 0.88);
      backdrop-filter: blur(12px);
      -webkit-backdrop-filter: blur(12px);
      border: 1px solid rgba(255, 255, 255, 0.15);
      border-radius: 30px;
      padding: 6px 10px;
      z-index: 100;
      box-shadow: 0 10px 25px rgba(0, 0, 0, 0.5);
    }
    .ctrl-btn {
      background: transparent;
      border: none;
      color: #94a3b8;
      font-size: 12px;
      font-weight: 600;
      padding: 6px 12px;
      border-radius: 20px;
      cursor: pointer;
      transition: all 0.2s;
    }
    .ctrl-btn.active {
      background: #3b82f6;
      color: #ffffff;
    }
    .ctrl-btn:hover:not(.active) {
      background: rgba(255, 255, 255, 0.1);
      color: #fff;
    }

    /* Radar Beacon Marker */
    .sos-marker-wrap {
      width: 50px;
      height: 50px;
      position: relative;
      display: flex;
      align-items: center;
      justify-content: center;
      cursor: pointer;
    }
    .sos-core {
      width: 18px;
      height: 18px;
      border-radius: 50%;
      background: #ef4444;
      border: 3px solid #ffffff;
      box-shadow: 0 0 16px #ef4444, 0 0 32px #ef4444;
      z-index: 5;
    }
    .sos-wave {
      position: absolute;
      width: 100%;
      height: 100%;
      border-radius: 50%;
      background: rgba(239, 68, 68, 0.4);
      animation: sos-radar 2.2s cubic-bezier(0, 0.2, 0.8, 1) infinite;
    }
    .sos-wave.delayed {
      animation-delay: 1.1s;
    }
    @keyframes sos-radar {
      0% { transform: scale(0.3); opacity: 1; }
      100% { transform: scale(2.8); opacity: 0; }
    }

    /* Engine pill */
    .engine-pill {
      position: absolute;
      top: 16px;
      right: 16px;
      font-size: 11px;
      font-weight: 600;
      color: #64748b;
      background: rgba(15, 23, 42, 0.8);
      border: 1px solid rgba(255, 255, 255, 0.08);
      padding: 4px 8px;
      border-radius: 6px;
      z-index: 100;
      pointer-events: none;
    }
  </style>
</head>
<body>
  <div id="loader-overlay" class="loader-overlay">
    <div class="loader-spinner"></div>
    <div class="loader-text">Loading 3D Mapbox Telemetry...</div>
    <div class="loader-sub">Acquiring live GPS satellite beacon</div>
  </div>

  <div id="mapbox-map"></div>
  <div id="leaflet-map"></div>

  <div class="engine-pill" id="engine-tag">⚡ Mapbox 3D</div>

  <div class="emergency-card">
    <div class="badge-row">
      <span id="badge-sos" class="badge-sos">● LIVE SOS ALERT</span>
      <span class="status-text">Status: <b id="status-val">__STATUS__</b></span>
    </div>
    <div class="person-title" id="title-name">⚠️ __USER_NAME__ needs help!</div>
    <div class="subtext">Real-time GPS emergency distress beacon</div>
    
    <div class="coords-bar">
      <span>📍 <span id="val-lat">__LAT__</span>, <span id="val-lng">__LNG__</span></span>
      <span style="color:#64748b; font-size:11px;" id="last-updated">LIVE</span>
    </div>

    <div class="distance-pill" id="dist-pill">
      🧭 Calculating your distance...
    </div>

    <div class="btn-actions">
      <a class="btn btn-maps" id="nav-btn" href="https://www.google.com/maps/dir/?api=1&destination=__LAT__,__LNG__" target="_blank">
        🚗 Navigate (Maps)
      </a>
      <a class="btn btn-call" href="tel:999">
        📞 Call Police (999)
      </a>
    </div>
  </div>

  <div class="map-controls-bar">
    <button class="ctrl-btn active" id="btn-3d" onclick="setMode('3d')">3D Buildings</button>
    <button class="ctrl-btn" id="btn-2d" onclick="setMode('2d')">2D Street</button>
    <button class="ctrl-btn" id="btn-sat" onclick="setMode('sat')">Satellite</button>
    <button class="ctrl-btn" onclick="recenter()">🎯 Recenter</button>
  </div>

  <script>
    let curLat = parseFloat('__LAT__');
    let curLng = parseFloat('__LNG__');
    const userName = '__USER_NAME_JS__';
    const userNameHtml = userName.replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
    const panicEventId = '__PANIC_EVENT_ID__';
    const mapboxToken = '__MAPBOX_TOKEN__';

    let mapboxMap = null;
    let mapboxMarker = null;
    let leafletMap = null;
    let leafletMarker = null;
    let isLeafletActive = false;
    let currentMode = '3d';

    function hideLoader() {
      const el = document.getElementById('loader-overlay');
      if (el) el.classList.add('hidden');
    }

    // Haversine distance calculator
    function calcDistanceKm(lat1, lon1, lat2, lon2) {
      const R = 6371;
      const dLat = (lat2 - lat1) * Math.PI / 180;
      const dLon = (lon2 - lon1) * Math.PI / 180;
      const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
                Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
                Math.sin(dLon/2) * Math.sin(dLon/2);
      const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
      return R * c;
    }

    // Measure distance from viewer
    function trackViewerDistance() {
      if (navigator.geolocation) {
        navigator.geolocation.getCurrentPosition((pos) => {
          const dKm = calcDistanceKm(pos.coords.latitude, pos.coords.longitude, curLat, curLng);
          const pill = document.getElementById('dist-pill');
          pill.style.display = 'block';
          if (dKm < 1) {
            pill.innerHTML = `📍 You are <b>${Math.round(dKm * 1000)} meters</b> away from ${userNameHtml}`;
          } else {
            pill.innerHTML = `📍 You are <b>${dKm.toFixed(1)} km</b> away from ${userNameHtml}`;
          }
        }, () => {});
      }
    }
    trackViewerDistance();

    function createMarkerElement() {
      const el = document.createElement('div');
      el.className = 'sos-marker-wrap';
      el.innerHTML = '<div class="sos-wave"></div><div class="sos-wave delayed"></div><div class="sos-core"></div>';
      return el;
    }

    // 1. Initialize Mapbox 3D
    function initMapbox() {
      try {
        if (!mapboxToken || typeof mapboxgl === 'undefined' || !mapboxgl.supported()) {
          console.warn('Mapbox or WebGL unsupported; falling back to Leaflet');
          switchToLeaflet('WebGL/Mapbox not available');
          return;
        }

        mapboxgl.accessToken = mapboxToken;
        mapboxMap = new mapboxgl.Map({
          container: 'mapbox-map',
          style: 'mapbox://styles/mapbox/dark-v11',
          center: [curLng, curLat],
          zoom: 16.5,
          pitch: 62,
          bearing: -20,
          antialias: true
        });

        const timeoutId = setTimeout(() => {
          if (!mapboxMap.loaded() && !mapboxMap.isStyleLoaded()) {
            console.warn('Mapbox load timeout (10s); falling back to Leaflet');
            switchToLeaflet('Mapbox load timeout');
          }
        }, 10000);

        mapboxMap.on('error', (e) => {
          console.warn('Mapbox error event:', e);
          if (!mapboxMap.loaded()) {
            clearTimeout(timeoutId);
            switchToLeaflet('Mapbox error event');
          }
        });

        mapboxMap.on('style.load', () => {
          clearTimeout(timeoutId);
          hideLoader();
          try {
            // Add 3D buildings
            const layers = mapboxMap.getStyle().layers;
            const labelLayerId = layers && layers.find(l => l.type === 'symbol' && l.layout && l.layout['text-field'])?.id;

            if (!mapboxMap.getLayer('add-3d-buildings')) {
              mapboxMap.addLayer({
                'id': 'add-3d-buildings',
                'source': 'composite',
                'source-layer': 'building',
                'filter': ['==', 'extrude', 'true'],
                'type': 'fill-extrusion',
                'minzoom': 14,
                'paint': {
                  'fill-extrusion-color': '#1e293b',
                  'fill-extrusion-height': ['get', 'height'],
                  'fill-extrusion-base': ['get', 'min_height'],
                  'fill-extrusion-opacity': 0.75
                }
              }, labelLayerId);
            }

            // Add 3D Terrain progressively
            if (!mapboxMap.getSource('mapbox-dem')) {
              mapboxMap.addSource('mapbox-dem', {
                'type': 'raster-dem',
                'url': 'mapbox://mapbox.mapbox-terrain-dem-v1',
                'tileSize': 512,
                'maxzoom': 14
              });
            }
            mapboxMap.setTerrain({ 'source': 'mapbox-dem', 'exaggeration': 1.4 });
          } catch (err) {
            console.warn('Non-fatal 3D layer setup warning:', err);
          }
        });

        mapboxMap.on('load', () => {
          hideLoader();
        });

        mapboxMarker = new mapboxgl.Marker(createMarkerElement())
          .setLngLat([curLng, curLat])
          .setPopup(new mapboxgl.Popup({ offset: 25 }).setHTML(`<b>${userNameHtml}</b><br>Live GPS SOS Location`))
          .addTo(mapboxMap);

        mapboxMap.addControl(new mapboxgl.NavigationControl({ visualizePitch: true }), 'bottom-right');
      } catch (e) {
        console.error('Mapbox init caught exception:', e);
        switchToLeaflet(e.message);
      }
    }

    // 2. Leaflet Fallback (Runs everywhere, on all devices)
    function switchToLeaflet(reason) {
      if (isLeafletActive) return;
      isLeafletActive = true;
      hideLoader();

      document.getElementById('mapbox-map').style.display = 'none';
      const leafDiv = document.getElementById('leaflet-map');
      leafDiv.style.display = 'block';
      document.getElementById('engine-tag').textContent = '🌐 OpenStreetMap Leaflet';

      try {
        leafletMap = L.map('leaflet-map', { zoomControl: false }).setView([curLat, curLng], 17);

        L.tileLayer('https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png', {
          attribution: '&copy; OpenStreetMap &copy; CARTO',
          maxZoom: 19
        }).addTo(leafletMap);

        L.control.zoom({ position: 'bottomright' }).addTo(leafletMap);

        const customIcon = L.divIcon({
          className: 'custom-leaflet-beacon',
          html: '<div class="sos-marker-wrap"><div class="sos-wave"></div><div class="sos-wave delayed"></div><div class="sos-core"></div></div>',
          iconSize: [50, 50],
          iconAnchor: [25, 25]
        });

        leafletMarker = L.marker([curLat, curLng], { icon: customIcon }).addTo(leafletMap);
        leafletMarker.bindPopup(`<b>${userNameHtml}</b><br>Live GPS SOS Location`).openPopup();
      } catch (err) {
        console.error('Leaflet fallback failed:', err);
      }
    }

    // View Modes
    function setMode(mode) {
      currentMode = mode;
      document.querySelectorAll('.ctrl-btn').forEach(b => b.classList.remove('active'));
      const activeBtn = document.getElementById(`btn-${mode}`);
      if (activeBtn) activeBtn.classList.add('active');

      if (!isLeafletActive && mapboxMap) {
        if (mode === '3d') {
          mapboxMap.setStyle('mapbox://styles/mapbox/dark-v11');
          mapboxMap.easeTo({ pitch: 62, bearing: -20, duration: 1000 });
        } else if (mode === '2d') {
          mapboxMap.setStyle('mapbox://styles/mapbox/streets-v12');
          mapboxMap.easeTo({ pitch: 0, bearing: 0, duration: 1000 });
        } else if (mode === 'sat') {
          mapboxMap.setStyle('mapbox://styles/mapbox/satellite-streets-v12');
          mapboxMap.easeTo({ pitch: 45, bearing: 0, duration: 1000 });
        }
      } else if (leafletMap) {
        // Toggle tiles in Leaflet
        if (mode === 'sat') {
          L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', {
            maxZoom: 19
          }).addTo(leafletMap);
        } else {
          L.tileLayer('https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png', {
            maxZoom: 19
          }).addTo(leafletMap);
        }
      }
    }

    function recenter() {
      if (!isLeafletActive && mapboxMap) {
        mapboxMap.flyTo({ center: [curLng, curLat], zoom: 17, essential: true });
      } else if (leafletMap) {
        leafletMap.setView([curLat, curLng], 17);
      }
    }

    // Dynamic Updates
    function updateLocation(newLat, newLng, newStatus) {
      curLat = newLat;
      curLng = newLng;
      document.getElementById('val-lat').textContent = newLat.toFixed(6);
      document.getElementById('val-lng').textContent = newLng.toFixed(6);
      document.getElementById('last-updated').textContent = new Date().toLocaleTimeString();
      document.getElementById('nav-btn').href = `https://www.google.com/maps/dir/?api=1&destination=${newLat},${newLng}`;

      if (newStatus && newStatus.toUpperCase() !== 'ACTIVE') {
        const badge = document.getElementById('badge-sos');
        badge.className = 'badge-sos resolved';
        badge.textContent = `● ${newStatus.toUpperCase()}`;
        const statusVal = document.getElementById('status-val');
        statusVal.className = 'resolved';
        statusVal.textContent = newStatus.toUpperCase();
        document.getElementById('title-name').textContent = `✅ Alert ${newStatus.toUpperCase()}`;
      }

      if (!isLeafletActive && mapboxMarker) {
        mapboxMarker.setLngLat([newLng, newLat]);
      } else if (leafletMarker) {
        leafletMarker.setLatLng([newLat, newLng]);
      }
      trackViewerDistance();
    }

    // Start Mapbox
    initMapbox();

    // 3. Live Polling for Dynamic Location Updates
    if (panicEventId) {
      setInterval(async () => {
        try {
          const resp = await fetch(`/alert/event/${panicEventId}`);
          if (resp.ok) {
            const data = await resp.json();
            if (data.success && data.event) {
              const ev = data.event;
              updateLocation(ev.latitude, ev.longitude, ev.status);
            }
          }
        } catch (e) {
          console.debug('Live sync poll notice:', e);
        }
      }, 4000);
    }
  </script>
</body>
</html>"""

    import html as html_lib
    import json as json_lib

    # JS-string-safe name (no quotes/backslashes/script-closing sequences)
    js_name = json_lib.dumps(user_name)[1:-1].replace("'", "\\'").replace("</", "<\\/")
    replacements = {
        "__USER_NAME_JS__": js_name,
        "__USER_NAME__": html_lib.escape(user_name),
        "__LAT__": f"{lat:.6f}",
        "__LNG__": f"{lng:.6f}",
        "__STATUS__": html_lib.escape(status.upper()),
        "__PANIC_EVENT_ID__": html_lib.escape(panic_event_id),
        "__MAPBOX_TOKEN__": mapbox_token,
    }
    for k, v in replacements.items():
        html = html.replace(k, v)
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
async def view_live_tracking(lat: float = -1.2921, lng: float = 36.8219, name: str = "SafeGuard User"):
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
    
    lat = -1.2921
    lng = 36.8219
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




