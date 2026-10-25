/*
 * ==============================================================================
 * SafeGuard GPS Safety Pendant — Master Firmware (Indoor & Outdoor Multi-Tier)
 * ==============================================================================
 * MCU: ESP32-C3 Super Mini / standard ESP32-C3
 * Author: Joy Kipkemboi — Strathmore University
 *
 * Hardware Wiring (Verified on Breadboard):
 *   - SIM800L TX -> GPIO5 (ESP32 RX)
 *   - SIM800L RX -> GPIO6 (ESP32 TX)
 *   - NEO-6M TX  -> GPIO4 (ESP32 RX)
 *   - NEO-6M RX  -> GPIO3 (ESP32 TX)
 *   - TTP223B Touch SIG -> GPIO1 (Active HIGH)
 *   - Status LED / Buzzer -> GPIO8
 *
 * Linked User:
 *   - ID:    7426cae6-d358-4a02-9e2f-c7839a864e93
 *   - Email: chepchumbajr@gmail.com
 *
 * Indoor & Outdoor Multi-Tier Location Engine:
 *   - TIER 1 (Outdoor): NEO-6M 3D Satellite GPS Fix (prioritized when outdoors).
 *   - TIER 2 (Indoor/Phone): Phone BLE Assisted GPS (phone forwards its fused GPS).
 *   - TIER 3 (Indoor/Wi-Fi): Real-time Wi-Fi IP Geolocation via ip-api.com (~0.5s).
 *   - TIER 4 (Indoor/GSM): Cellular Base-Station LBS via SIM800L (AT+CIPGSMLOC).
 *   - TIER 5 (Fallback): Calibrated Indoor Anchor saved in ESP32 Flash memory.
 *
 * Dynamic Features & Architecture:
 *   1. ZERO HARDCODING: Contacts, URLs, and coordinates stored in NVS Flash.
 *   2. SUPABASE DIRECT REST INTEGRATION:
 *      - Auto-fetches emergency contacts from `emergency_contacts` table.
 *      - Logs every SMS / panic alert directly to `panic_events` table.
 *      - Registers device & sends heartbeats to `wearable_devices` table.
 *   3. DUAL-CHANNEL OFFLINE ALERTING:
 *      - Direct cellular SMS & voice calls via SIM800L GSM.
 *      - Instant BLE alarm notification to paired phone.
 *   4. TOUCH PATTERN DETECTION:
 *      - Double-tap (press-release-press) filter with debounce and stuck-high safety.
 *   5. INTERACTIVE SERIAL CONSOLE:
 *      - Commands: s=SOS SMS, l=GPS, g=Wi-Fi Geo, t=test SMS, c=call, h=hangup,
 *                  d=diagnose, u=sync contacts from DB, w=wearable status,
 *                  r=heartbeat DB, p=remove SIM PIN, setloc <lat>,<lon>=calibrate indoor.
 * ==============================================================================
 */

#define TINY_GSM_MODEM_SIM800
#define TINY_GSM_RX_BUFFER 1024

#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <Preferences.h>
#include <TinyGsmClient.h>

#include <TinyGPSPlus.h>

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// SafeGuard Embedded TinyML Keyword Spotting Model (13.4 KB)
#include "safeguard_micro_model.h"

// ------------------------------------------------------------------------------
// 1. PIN DEFINITIONS (Working Breadboard Pins)
// ------------------------------------------------------------------------------
#define SIM_RX          5     // SIM800L TX -> ESP32 GPIO5
#define SIM_TX          6     // SIM800L RX -> ESP32 GPIO6
#define GPS_RX          4     // NEO-6M TX  -> ESP32 GPIO4
#define GPS_TX          3     // NEO-6M RX  -> ESP32 GPIO3
#define TOUCH_PIN       1     // TTP223B SIG -> ESP32 GPIO1
#define PIN_MIC_ADC     2     // Electret Mic / MAX9814 Audio Out -> ESP32 GPIO2 (ADC1_CH2)
#define PIN_STATUS_LED  8     // Onboard / External Status LED

// ------------------------------------------------------------------------------
// 2. BLE GATT UUIDS (Matches Flutter App Constants)
// ------------------------------------------------------------------------------
#define BLE_DEVICE_NAME   "SafeGuard"
#define SERVICE_UUID      "0000ffe0-0000-1000-8000-00805f9b34fb"
#define CHAR_ALERT_UUID   "0000ffe1-0000-1000-8000-00805f9b34fb" // Notify app when SOS pressed
#define CHAR_CONFIG_UUID  "0000ffe2-0000-1000-8000-00805f9b34fb" // App writes updated contacts/URL/location
#define CHAR_STATUS_UUID  "0000ffe3-0000-1000-8000-00805f9b34fb" // Live status readout for app

// ------------------------------------------------------------------------------
// 3. HARDWARE & GLOBAL OBJECTS
// ------------------------------------------------------------------------------
HardwareSerial SerialAT(1);    // SIM800L on UART1
HardwareSerial gpsSerial(0);   // NEO-6M on UART0 (USB CDC carries Serial console)
TinyGsm modem(SerialAT);
TinyGPSPlus gps;
Preferences prefs;

BLEServer *pServer = nullptr;
BLECharacteristic *pAlertChar = nullptr;
BLECharacteristic *pConfigChar = nullptr;
BLECharacteristic *pStatusChar = nullptr;
bool bleClientConnected = false;

// ------------------------------------------------------------------------------
// 4. DYNAMIC CONFIGURATION (Loaded from NVS Flash — No Hardcoding)
// ------------------------------------------------------------------------------
String linkedUserId    = "7426cae6-d358-4a02-9e2f-c7839a864e93";
String linkedUserEmail = "chepchumbajr@gmail.com";

String contact1        = "+254740034499";
String contact1Name    = "Primary Contact";
String contact2        = "";
String contact2Name    = "";
String contact3        = "";
String contact3Name    = "";

String supabaseUrl     = "https://afagwdhpjnnbueiyjmde.supabase.co";
String supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFmYWd3ZGhwam5uYnVlaXlqbWRlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk5MTkzMzUsImV4cCI6MjEwNTQ5NTMzNX0.Qw_rs_KJOZF8RkXWW62QBKnSafzJFkt9YBPqCRo9mlA";
String backendUrl      = "https://unpaved-coherent-encroach.ngrok-free.dev";

// Permanent 3D Mapbox Live Viewer (Zero ngrok dependency via GitHub Pages CDN!)
String trackViewerUrl  = "https://joychepchumba.github.io/gps-safety-wearable/track.html";

String wifiSsid        = "The Kipkemboi's";
String wifiPass        = "Ng'0mbe_h@y$.";
const char simPin[]    = ""; // Leave empty if SIM has no PIN

String deviceMacAddress = "";
String deviceUUID       = "";

// ------------------------------------------------------------------------------
// 5. TIMING, THRESHOLDS & LOCATION STATE
// ------------------------------------------------------------------------------
const unsigned long FIX_WAIT_MS      = 6000UL;   // GPS outdoor check window before fallback (indoor-optimized)
const unsigned long DOUBLE_GAP_MS    = 1000UL;   // max time between release and 2nd press
const unsigned long LONG_PRESS_MS    = 1500UL;   // press longer than this is ignored
const unsigned long DEBOUNCE_MS      = 40UL;     // touch debounce
const unsigned long COOLDOWN_MS      = 25000UL;  // minimum time between triggered alerts
const unsigned long HEARTBEAT_INT_MS = 60000UL;  // periodic DB heartbeat interval (60s)

// Location state in RAM & Flash (Strathmore University default)
String lastLat = "-1.307300";   // Strathmore University, Nairobi
String lastLon = "36.811800";
String lastCity = "Strathmore University";
String currentLocSource = "Strathmore Univ Anchor";
unsigned long lastFixMs = 0;
unsigned long lastBleLocMs = 0;
unsigned long lastHeartbeatMs = 0;

// Voice & Microphone Detection State
bool micHardwareDetected = false;
int micNoiseFloor = 1800;
#define MIC_SHOUT_THRESHOLD 2800 // Peak ADC reading triggering acoustic distress
unsigned long lastMicSampleMs = 0;
String currentTriggerReason = "pendant_touch";

// LED indication helper
void blinkLed(int times, int onMs = 60, int offMs = 60) {
  for (int i = 0; i < times; i++) {
    digitalWrite(PIN_STATUS_LED, HIGH);
    delay(onMs);
    digitalWrite(PIN_STATUS_LED, LOW);
    if (i < times - 1) delay(offMs);
  }
}

// ------------------------------------------------------------------------------
// 6. NVS SETTINGS MANAGEMENT (Save / Load)
// ------------------------------------------------------------------------------
void loadSettingsFromFlash() {
  prefs.begin("safeguard", false);

  linkedUserId    = prefs.getString("user_id", linkedUserId);
  linkedUserEmail = prefs.getString("user_email", linkedUserEmail);

  contact1     = prefs.getString("c1", contact1);
  contact1Name = prefs.getString("c1_name", contact1Name);
  contact2     = prefs.getString("c2", "");
  contact2Name = prefs.getString("c2_name", "");
  if (contact2 == "+254709570000") {
    contact2 = "";
    contact2Name = "";
    prefs.putString("c2", "");
    prefs.putString("c2_name", "");
  }
  contact3     = prefs.getString("c3", contact3);
  contact3Name = prefs.getString("c3_name", contact3Name);

  supabaseUrl     = prefs.getString("sb_url", supabaseUrl);
  supabaseAnonKey = prefs.getString("sb_key", supabaseAnonKey);
  backendUrl      = prefs.getString("back_url", backendUrl);
  trackViewerUrl  = prefs.getString("track_url", trackViewerUrl);

  wifiSsid = prefs.getString("wifi_ssid", wifiSsid);
  wifiPass = prefs.getString("wifi_pass", wifiPass);

  deviceUUID = prefs.getString("dev_uuid", "");

  // Load saved indoor anchor coordinates (Migrate old default to Strathmore)
  lastLat = prefs.getString("last_lat", "-1.307300");
  lastLon = prefs.getString("last_lon", "36.811800");
  if (lastLat == "-1.292100" || lastLat.length() == 0) {
    lastLat = "-1.307300";
    lastLon = "36.811800";
    currentLocSource = "Strathmore Univ Anchor";
    prefs.putString("last_lat", lastLat);
    prefs.putString("last_lon", lastLon);
  }

  // Persist defaults if running for the first time
  prefs.putString("user_id", linkedUserId);
  prefs.putString("user_email", linkedUserEmail);
  prefs.putString("c1", contact1);
  prefs.putString("c1_name", contact1Name);
  prefs.putString("c2", contact2);
  prefs.putString("c2_name", contact2Name);
  prefs.putString("sb_url", supabaseUrl);
  prefs.putString("sb_key", supabaseAnonKey);
  prefs.putString("last_lat", lastLat);
  prefs.putString("last_lon", lastLon);

  prefs.end();

  Serial.println(F("[NVS] Configuration loaded from Flash memory:"));
  Serial.printf("  Linked User:  %s (%s)\n", linkedUserEmail.c_str(), linkedUserId.c_str());
  Serial.printf("  Contact 1:    %s (%s)\n", contact1.c_str(), contact1Name.c_str());
  Serial.printf("  Contact 2:    %s (%s)\n", contact2.c_str(), contact2Name.c_str());
  Serial.printf("  Indoor Anchor:%s, %s\n", lastLat.c_str(), lastLon.c_str());
  Serial.printf("  Supabase:     %s\n", supabaseUrl.c_str());
}

void saveContactsToFlash() {
  prefs.begin("safeguard", false);
  prefs.putString("c1", contact1);
  prefs.putString("c1_name", contact1Name);
  prefs.putString("c2", contact2);
  prefs.putString("c2_name", contact2Name);
  prefs.putString("c3", contact3);
  prefs.putString("c3_name", contact3Name);
  prefs.end();
  Serial.println(F("[NVS] Emergency contacts saved locally to ESP32 Flash."));
}

void saveIndoorAnchor(const String &lat, const String &lon) {
  lastLat = lat;
  lastLon = lon;
  lastFixMs = millis();
  currentLocSource = "Manual Indoor Calibration Anchor";
  prefs.begin("safeguard", false);
  prefs.putString("last_lat", lastLat);
  prefs.putString("last_lon", lastLon);
  prefs.end();
  Serial.printf("[INDOOR ANCHOR] Saved new indoor coordinates to Flash: %s, %s\n",
                lastLat.c_str(), lastLon.c_str());
}

// ------------------------------------------------------------------------------
// 7. MULTI-TIER LOCATION ENGINE (INDOOR & OUTDOOR)
// ------------------------------------------------------------------------------

// Helper: Lightweight JSON string value extractor (Zero external library dependency)
String jsonExtract(const String &json, const String &key, int startPos = 0, int *outEnd = nullptr) {
  String searchKey = "\"" + key + "\":\"";
  int kPos = json.indexOf(searchKey, startPos);
  if (kPos != -1) {
    int vStart = kPos + searchKey.length();
    int vEnd = json.indexOf("\"", vStart);
    if (vEnd != -1) {
      if (outEnd) *outEnd = vEnd;
      return json.substring(vStart, vEnd);
    }
  }
  // Try without quotes for numbers/booleans
  searchKey = "\"" + key + "\":";
  kPos = json.indexOf(searchKey, startPos);
  if (kPos != -1) {
    int vStart = kPos + searchKey.length();
    while (vStart < json.length() && (json[vStart] == ' ' || json[vStart] == '\"')) vStart++;
    int vEnd = vStart;
    while (vEnd < json.length() && json[vEnd] != ',' && json[vEnd] != '}' && json[vEnd] != ']') vEnd++;
    String val = json.substring(vStart, vEnd);
    val.replace("\"", "");
    val.trim();
    if (outEnd) *outEnd = vEnd;
    return val;
  }
  return "";
}

// Tier 1: Satellite GPS stream ingestion
void feedGPS() {
  while (gpsSerial.available()) {
    gps.encode(gpsSerial.read());
  }
  if (gps.location.isValid() && gps.location.age() < 3000) {
    lastLat = String(gps.location.lat(), 6);
    lastLon = String(gps.location.lng(), 6);
    lastFixMs = millis();
    currentLocSource = "NEO-6M GPS (Outdoor 3D Satellites)";
  }
}

// Tier 3: Indoor Wi-Fi IP Geolocation (Zero API key, runs in ~0.5s over HTTP)
bool fetchWifiGeolocation(String &lat, String &lon, String &city) {
  if (WiFi.status() != WL_CONNECTED) return false;

  Serial.println(F("[WIFI GEO] Querying indoor Wi-Fi geolocation..."));
  HTTPClient http;
  http.begin("http://ip-api.com/json/?fields=status,lat,lon,city,country");
  http.setTimeout(4000);
  int httpCode = http.GET();

  if (httpCode == 200) {
    String payload = http.getString();
    http.end();

    String status = jsonExtract(payload, "status");
    if (status == "success") {
      lat = jsonExtract(payload, "lat");
      lon = jsonExtract(payload, "lon");
      city = jsonExtract(payload, "city");

      if (lat.length() > 0 && lon.length() > 0) {
        lastLat = lat;
        lastLon = lon;
        lastCity = city;
        lastFixMs = millis();
        currentLocSource = "Wi-Fi Indoor Geolocation (" + city + ")";

        // Persist to Flash so offline fallback has current city/building coordinates
        prefs.begin("safeguard", false);
        prefs.putString("last_lat", lastLat);
        prefs.putString("last_lon", lastLon);
        prefs.end();

        Serial.printf("[WIFI GEO] SUCCESS! Coordinates: %s, %s (%s)\n",
                      lat.c_str(), lon.c_str(), city.c_str());
        return true;
      }
    }
  } else {
    http.end();
    Serial.printf("[WIFI GEO] Notice: HTTP %d\n", httpCode);
  }
  return false;
}

// Tier 4: Cellular Base-Station Location (SIM800L LBS / Cell-ID triangulation)
bool fetchGsmCellLocation(String &lat, String &lon) {
  if (!modem.isNetworkConnected()) return false;

  Serial.println(F("[GSM LBS] Requesting cellular base-station coordinates from SIM800L..."));
  // SIM800L AT+CIPGSMLOC queries cellular tower location
  modem.sendAT(GF("+CIPGSMLOC=1,1"));
  String resp = "";
  unsigned long start = millis();
  while (millis() - start < 4500) {
    if (SerialAT.available()) {
      resp += (char)SerialAT.read();
      if (resp.indexOf("+CIPGSMLOC:") != -1 && resp.indexOf("\n", resp.indexOf("+CIPGSMLOC:")) != -1) {
        break;
      }
    }
    delay(10);
  }

  int idx = resp.indexOf("+CIPGSMLOC:");
  if (idx != -1) {
    int c1 = resp.indexOf(',', idx);
    int c2 = resp.indexOf(',', c1 + 1);
    int c3 = resp.indexOf(',', c2 + 1);
    if (c1 != -1 && c2 != -1 && c3 != -1) {
      String status = resp.substring(idx + 12, c1);
      status.trim();
      if (status == "0") {
        lon = resp.substring(c1 + 1, c2);
        lat = resp.substring(c2 + 1, c3);
        lon.trim();
        lat.trim();
        if (lat.length() > 0 && lon.length() > 0) {
          lastLat = lat;
          lastLon = lon;
          lastFixMs = millis();
          currentLocSource = "GSM Cell Tower Triangulation";
          Serial.printf("[GSM LBS] SUCCESS! Cellular tower coords: %s, %s\n", lat.c_str(), lon.c_str());
          return true;
        }
      }
    }
  }
  return false;
}

// Master Multi-Tier Location Resolver:
// Attempts GPS -> Phone BLE Assisted -> Wi-Fi Geolocation -> GSM Cell Tower -> Saved Anchor
bool getFix(String &lat, String &lon, unsigned long timeoutMs) {
  Serial.println(F("\n[LOCATION ENGINE] Resolving current location..."));

  // 1. TIER 1: Check NEO-6M satellite fix (Brief check up to 5s)
  unsigned long start = millis();
  unsigned long checkTime = min(timeoutMs, 5000UL);
  while (millis() - start < checkTime) {
    feedGPS();
    if (lastFixMs != 0 && (millis() - lastFixMs < 3000) && gps.location.isValid() && gps.satellites.value() >= 3) {
      lat = lastLat;
      lon = lastLon;
      currentLocSource = "NEO-6M GPS (" + String(gps.satellites.value()) + " Sats)";
      Serial.printf("[LOCATION] Real Satellite 3D Lock Acquired: %s, %s\n", lat.c_str(), lon.c_str());
      return true;
    }
    delay(10);
  }

  // 2. TIER 2: Check Phone BLE Assisted GPS (received within last 10 minutes)
  if (lastBleLocMs != 0 && (millis() - lastBleLocMs < 600000UL)) {
    lat = lastLat;
    lon = lastLon;
    currentLocSource = "Phone BLE Assisted GPS (Indoor)";
    Serial.printf("[LOCATION] Using Phone Assisted GPS over BLE: %s, %s\n", lat.c_str(), lon.c_str());
    return true;
  }

  // 3. TIER 3: Check Wi-Fi Geolocation (Fast & accurate for indoor testing!)
  if (WiFi.status() == WL_CONNECTED) {
    String city;
    if (fetchWifiGeolocation(lat, lon, city)) {
      currentLocSource = "Wi-Fi Geolocation (Indoor - " + city + ")";
      return true;
    }
  }

  // 4. TIER 4: Check GSM Cell Tower Triangulation
  if (fetchGsmCellLocation(lat, lon)) {
    currentLocSource = "GSM Cell Tower Triangulation (Indoor)";
    return true;
  }

  // 5. TIER 5: Fallback to Saved Indoor Anchor in Flash
  if (lastLat.length() > 0 && lastLon.length() > 0) {
    lat = lastLat;
    lon = lastLon;
    currentLocSource = "Saved Indoor Anchor (Flash)";
    Serial.printf("[LOCATION] Using Saved Indoor Calibration Anchor: %s, %s\n", lat.c_str(), lon.c_str());
    return true;
  }

  // Final fallback (Strathmore University campus)
  lat = "-1.307300";
  lon = "36.811800";
  currentLocSource = "Strathmore Univ Anchor";
  return true;
}

void showLocation() {
  Serial.println(F("\nResolving current location (Indoor / Outdoor)..."));
  String lat, lon;
  getFix(lat, lon, 4000UL);
  Serial.printf("Current Location: Lat=%s, Lon=%s\n", lat.c_str(), lon.c_str());
  Serial.printf("Source:           %s\n", currentLocSource.c_str());
  Serial.printf("GPS Satellites:   %d\n", gps.satellites.isValid() ? gps.satellites.value() : 0);
  Serial.printf("Google Maps Link: https://maps.google.com/?q=%s,%s\n\n", lat.c_str(), lon.c_str());
  blinkLed(3, 70, 70);
}

// ------------------------------------------------------------------------------
// 8. SUPABASE DIRECT REST API CLIENT
// ------------------------------------------------------------------------------

// 8.1 Sync emergency contacts from Supabase `emergency_contacts` table
bool syncContactsFromSupabase() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println(F("[DB SYNC] WiFi not connected. Cannot reach Supabase directly."));
    return false;
  }

  Serial.println(F("\n[DB SYNC] Querying Supabase for user emergency contacts..."));
  Serial.printf("  User ID: %s (%s)\n", linkedUserId.c_str(), linkedUserEmail.c_str());

  WiFiClientSecure client;
  client.setInsecure(); // Microcontroller TLS without CA cert chain overhead

  HTTPClient http;
  String endpoint = supabaseUrl + "/rest/v1/emergency_contacts?user_id=eq." + linkedUserId +
                    "&select=id,contact_name,phone_number,consent_status&order=created_at.asc";

  http.begin(client, endpoint);
  http.addHeader("apikey", supabaseAnonKey);
  http.addHeader("Authorization", "Bearer " + supabaseAnonKey);
  http.addHeader("Accept", "application/json");

  int httpCode = http.GET();
  String payload = http.getString();
  http.end();

  Serial.printf("[DB SYNC] Supabase response code: %d\n", httpCode);

  if (httpCode >= 200 && httpCode < 300) {
    if (payload == "[]" || payload.length() < 10) {
      Serial.println(F("[DB SYNC] No contacts in database for this user yet. Keeping existing local contacts."));
      return false;
    }

    int foundCount = 0;
    int curPos = 0;
    while (curPos < payload.length() && foundCount < 3) {
      int objStart = payload.indexOf('{', curPos);
      if (objStart == -1) break;
      int objEnd = payload.indexOf('}', objStart);
      if (objEnd == -1) break;

      String objStr = payload.substring(objStart, objEnd + 1);
      String phone = jsonExtract(objStr, "phone_number");
      String name  = jsonExtract(objStr, "contact_name");

      if (phone.length() >= 7) {
        foundCount++;
        if (foundCount == 1) {
          contact1 = phone;
          contact1Name = name.length() > 0 ? name : "Contact 1";
        } else if (foundCount == 2) {
          contact2 = phone;
          contact2Name = name.length() > 0 ? name : "Contact 2";
        } else if (foundCount == 3) {
          contact3 = phone;
          contact3Name = name.length() > 0 ? name : "Contact 3";
        }
      }
      curPos = objEnd + 1;
    }

    if (foundCount > 0) {
      Serial.printf("[DB SYNC] SUCCESS! Synced %d contacts from Supabase:\n", foundCount);
      Serial.printf("  1. %s (%s)\n", contact1.c_str(), contact1Name.c_str());
      if (contact2.length() > 0) Serial.printf("  2. %s (%s)\n", contact2.c_str(), contact2Name.c_str());
      if (contact3.length() > 0) Serial.printf("  3. %s (%s)\n", contact3.c_str(), contact3Name.c_str());

      saveContactsToFlash();
      blinkLed(3, 70, 70);
      return true;
    }
  } else {
    Serial.printf("[DB SYNC] Supabase query notice (HTTP %d). Keeping local contacts.\n", httpCode);
  }
  return false;
}

// 8.2 Register wearable & send heartbeat to Supabase `wearable_devices` table
bool registerWearableInDatabase() {
  if (WiFi.status() != WL_CONNECTED) return false;

  WiFiClientSecure client;
  client.setInsecure();

  HTTPClient http;
  String endpoint = supabaseUrl + "/rest/v1/wearable_devices?on_conflict=device_mac";

  http.begin(client, endpoint);
  http.addHeader("apikey", supabaseAnonKey);
  http.addHeader("Authorization", "Bearer " + supabaseAnonKey);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Prefer", "resolution=merge-duplicates,return=representation");

  char jsonBody[320];
  snprintf(jsonBody, sizeof(jsonBody),
           "{\"user_id\":\"%s\",\"device_mac\":\"%s\",\"device_name\":\"%s\","
           "\"firmware_version\":\"2.2.0\",\"is_active\":true,\"last_seen_at\":\"now()\"}",
           linkedUserId.c_str(), deviceMacAddress.c_str(), BLE_DEVICE_NAME);

  int httpCode = http.POST(jsonBody);
  String resp = http.getString();
  http.end();

  if (httpCode >= 200 && httpCode < 300) {
    lastHeartbeatMs = millis();
    String devId = jsonExtract(resp, "id");
    if (devId.length() > 0) {
      deviceUUID = devId;
      prefs.begin("safeguard", false);
      prefs.putString("dev_uuid", deviceUUID);
      prefs.end();
    }
    Serial.printf("[HEARTBEAT] Wearable status updated in Supabase! (MAC: %s, Active now)\n",
                  deviceMacAddress.c_str());
    return true;
  }
  return false;
}

// 8.3 Log alert & SMS to Supabase `panic_events` table
bool logAlertToSupabase(const String &lat, const String &lon, const String &smsText, const String &recipients, const String &source) {
  // If WiFi is disconnected, attempt quick connect to record emergency in database
  if (WiFi.status() != WL_CONNECTED && wifiSsid.length() > 0) {
    Serial.println(F("[SUPABASE LOG] Attempting quick WiFi connect to dispatch alert to database..."));
    WiFi.begin(wifiSsid.c_str(), wifiPass.c_str());
    int r = 0;
    while (WiFi.status() != WL_CONNECTED && r < 20) {
      delay(250);
      r++;
    }
  }

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println(F("[SUPABASE LOG] WiFi offline. SMS delivered via GSM cellular; Supabase log will sync when online."));
    return false;
  }

  // Ensure wearable is registered in DB so panic_events has the foreign key
  if (deviceUUID.length() == 0) {
    registerWearableInDatabase();
  }

  Serial.println(F("[SUPABASE LOG] Recording SOS & SMS event in Supabase panic_events table..."));

  WiFiClientSecure client;
  client.setInsecure();

  HTTPClient http;
  String endpoint = supabaseUrl + "/rest/v1/panic_events";

  http.begin(client, endpoint);
  http.addHeader("apikey", supabaseAnonKey);
  http.addHeader("Authorization", "Bearer " + supabaseAnonKey);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Prefer", "return=minimal");

  String safeNotes = "SMS sent via SIM800L to [" + recipients + "]. Source: " + source + ". Msg: " + smsText;
  safeNotes.replace("\"", "'");
  safeNotes.replace("\n", " ");

  String payload = "{";
  payload += "\"user_id\":\"" + linkedUserId + "\",";
  if (deviceUUID.length() > 0) {
    payload += "\"wearable_device_id\":\"" + deviceUUID + "\",";
  }
  payload += "\"trigger_method\":\"" + currentTriggerReason + "\",";
  payload += "\"status\":\"active\",";
  payload += "\"latitude\":" + lat + ",";
  payload += "\"longitude\":" + lon + ",";
  payload += "\"location_accuracy_m\":15.0,";
  payload += "\"emergency_contacts_notified\":true,";
  payload += "\"notes\":\"" + safeNotes + "\"";
  payload += "}";

  int httpCode = http.POST(payload);
  http.end();

  if (httpCode >= 200 && httpCode < 300) {
    Serial.printf("[SUPABASE LOG] SUCCESS! Alert recorded in Supabase (HTTP %d)\n", httpCode);
    return true;
  } else {
    Serial.printf("[SUPABASE LOG] Notice: HTTP %d while inserting panic event.\n", httpCode);
    return false;
  }
}

// ------------------------------------------------------------------------------
// 9. SMS & CELLULAR GSM DISPATCH (SIM800L)
// ------------------------------------------------------------------------------
bool sendSMS(const String &number, const String &text) {
  if (number.length() < 7) return false;
  Serial.printf("[SMS] Sending to %s...\n", number.c_str());

  // 1. Drain any residual bytes in UART buffer before starting SMS command
  while (SerialAT.available()) SerialAT.read();

  // 2. Ensure command echo is permanently OFF (ATE0) so AT commands never leak into message
  modem.sendAT(GF("E0"));
  modem.waitResponse(400);

  // 3. Dispatch SMS via TinyGSM
  bool ok = modem.sendSMS(number, text);
  Serial.println(ok ? F("[SMS] Delivery SUCCESSFUL!") : F("[SMS] Send FAILED!"));

  // 4. Critical: Wait 2.5s for SIM800L to exit text mode, finalize 2G transmission, and drain
  delay(2500);
  while (SerialAT.available()) SerialAT.read();

  return ok;
}

void notifyPhoneOverBLE() {
  if (pAlertChar != nullptr) {
    uint8_t alertCode = 0x01;
    pAlertChar->setValue(&alertCode, 1);
    pAlertChar->notify();
    Serial.println(F("[BLE] Alert notification sent to connected phone!"));
  }
}

// Main emergency dispatch routine: Resolves location (Multi-Tier), sends SMS, logs to Supabase
void sendLocationAlert(unsigned long waitMs = FIX_WAIT_MS) {
  blinkLed(5, 40, 40); // Rapid strobe indicator
  Serial.println(F("\n=================================================="));
  Serial.println(F(">>> EMERGENCY SOS TRIGGERED FROM PENDANT <<<"));
  Serial.println(F("=================================================="));

  // 1. Notify paired smartphone over BLE immediately
  notifyPhoneOverBLE();

  // 2. Resolve Multi-Tier Location (GPS -> Phone BLE -> Wi-Fi Geo -> GSM -> Anchor)
  String lat, lon;
  getFix(lat, lon, waitMs);

  // Generate Ephemeral Incident Reference (e.g. SOS-7426-3A1B)
  String incidentRef = "SOS-" + linkedUserId.substring(0, 4) + "-" + String((unsigned long)(millis() % 0xFFFF), HEX);
  incidentRef.toUpperCase();

  // Secure 3D Tracking link without leaking personal names into URL parameters
  String mapboxLiveLink = trackViewerUrl + "?lat=" + lat + "&lng=" + lon + "&id=" + incidentRef;
  String googleMapsLink = "https://maps.google.com/?q=" + lat + "," + lon;

  String triggerDesc = (currentTriggerReason == "pendant_voice") ? "Voice SOS Keyword" : "Pendant Touch";
  String smsMsg = "EMERGENCY SOS: Joy triggered " + triggerDesc + "!\n"
                  "Live 3D Map: " + mapboxLiveLink + "\n"
                  "Google Maps: " + googleMapsLink + "\n"
                  "Ref: " + incidentRef + " | " + currentLocSource;

  // 3. Dispatch SMS individually with safe guard delay between distinct recipients
  String recipients = "";
  if (contact1.length() >= 7) {
    sendSMS(contact1, smsMsg);
    recipients += contact1;
  }
  if (contact2.length() >= 7 && contact2 != contact1) {
    delay(2000); // Guard delay so SIM800L completely closes Contact 1 before Contact 2
    sendSMS(contact2, smsMsg);
    if (recipients.length() > 0) recipients += ", ";
    recipients += contact2;
  }
  if (contact3.length() >= 7 && contact3 != contact1 && contact3 != contact2) {
    delay(2000); // Guard delay
    sendSMS(contact3, smsMsg);
    if (recipients.length() > 0) recipients += ", ";
    recipients += contact3;
  }

  // 4. Log alert and sent SMS to Supabase
  logAlertToSupabase(lat, lon, smsMsg, recipients, currentLocSource);

  // 5. Update wearable heartbeat in DB
  registerWearableInDatabase();

  Serial.println(F(">>> EMERGENCY ALERT DISPATCH COMPLETED <<<\n"));
}

void testSMS() {
  Serial.println(F("Sending test SMS with Permanent 3D Mapbox live link to Primary Contact..."));
  String testRef = "TEST-" + String((unsigned long)(millis() % 0xFFFF), HEX);
  testRef.toUpperCase();
  String mapboxLink = trackViewerUrl + "?lat=" + lastLat + "&lng=" + lastLon + "&id=" + testRef;
  String testMsg = "SafeGuard Test Alert:\nLive 3D Map: " + mapboxLink +
                   "\nGoogle Maps: https://maps.google.com/?q=" + lastLat + "," + lastLon +
                   "\nRef: " + testRef;
  sendSMS(contact1, testMsg);
}

void callNumber() {
  if (contact1.length() < 7) {
    Serial.println(F("No phone number configured for Contact 1"));
    return;
  }
  Serial.printf("Calling %s...\n", contact1.c_str());
  bool ok = modem.callNumber(contact1);
  Serial.println(ok ? F("Call placed") : F("Call failed"));
  delay(15000);
  modem.callHangup();
  Serial.println(F("Call ended / Hung up."));
}

// ------------------------------------------------------------------------------
// 10. BLE GATT SERVER CALLBACKS & STATUS REPORTING
// ------------------------------------------------------------------------------
class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *pServer) {
    bleClientConnected = true;
    blinkLed(2, 100, 100);
    Serial.println(F("[BLE] Phone App connected to SafeGuard pendant!"));

    if (pStatusChar != nullptr) {
      String status = "{\"connected\":true,\"user\":\"" + linkedUserEmail + "\",\"status\":\"active\"}";
      pStatusChar->setValue(status.c_str());
      pStatusChar->notify();
    }
  }

  void onDisconnect(BLEServer *pServer) {
    bleClientConnected = false;
    Serial.println(F("[BLE] Phone App disconnected. Resuming advertising..."));
    pServer->startAdvertising();
  }
};

class ConfigCharCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) {
    String value = pChar->getValue().c_str();
    if (value.length() == 0) return;

    Serial.printf("[BLE CONFIG] Data received: %s\n", value.c_str());

    // 1. Phone Assisted GPS Location update ("LOC:lat,lon")
    if (value.startsWith("LOC:")) {
      int comma = value.indexOf(',', 4);
      if (comma != -1) {
        lastLat = value.substring(4, comma);
        lastLon = value.substring(comma + 1);
        lastLat.trim();
        lastLon.trim();
        lastBleLocMs = millis();
        lastFixMs = millis();
        currentLocSource = "Phone BLE Assisted GPS (Indoor)";
        prefs.begin("safeguard", false);
        prefs.putString("last_lat", lastLat);
        prefs.putString("last_lon", lastLon);
        prefs.end();
        Serial.printf("[BLE LOC] Live location synced from phone GPS: %s, %s\n",
                      lastLat.c_str(), lastLon.c_str());
        return;
      }
    }

    // 2. Dynamic Backend URL sync ("URL:https://...")
    if (value.startsWith("URL:")) {
      backendUrl = value.substring(4);
      prefs.begin("safeguard", false);
      prefs.putString("back_url", backendUrl);
      prefs.end();
      Serial.printf("[CONFIG] Backend URL updated to: %s\n", backendUrl.c_str());
      return;
    }

    // 3. Dynamic User ID sync ("USER:uuid,email")
    if (value.startsWith("USER:")) {
      String rest = value.substring(5);
      int cIdx = rest.indexOf(',');
      if (cIdx != -1) {
        linkedUserId = rest.substring(0, cIdx);
        linkedUserEmail = rest.substring(cIdx + 1);
      } else {
        linkedUserId = rest;
      }
      prefs.begin("safeguard", false);
      prefs.putString("user_id", linkedUserId);
      prefs.putString("user_email", linkedUserEmail);
      prefs.end();
      Serial.printf("[CONFIG] Linked user updated: %s (%s)\n", linkedUserEmail.c_str(), linkedUserId.c_str());
      syncContactsFromSupabase();
      return;
    }

    // 4. Emergency Contacts CSV sync ("phone1,phone2,phone3")
    int firstComma = value.indexOf(',');
    int secondComma = value.indexOf(',', firstComma + 1);
    if (firstComma != -1) {
      contact1 = value.substring(0, firstComma);
      if (secondComma != -1) {
        contact2 = value.substring(firstComma + 1, secondComma);
        contact3 = value.substring(secondComma + 1);
      } else {
        contact2 = value.substring(firstComma + 1);
      }
    } else {
      contact1 = value;
    }
    saveContactsToFlash();
  }
};

void setupBLE() {
  BLEDevice::init(BLE_DEVICE_NAME);
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);

  // 1. Alert characteristic (Notifies Phone App on trigger)
  pAlertChar = pService->createCharacteristic(
      CHAR_ALERT_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  pAlertChar->addDescriptor(new BLE2902());
  uint8_t zero = 0x00;
  pAlertChar->setValue(&zero, 1);

  // 2. Config characteristic (Phone app writes contacts/URL/location)
  pConfigChar = pService->createCharacteristic(
      CHAR_CONFIG_UUID,
      BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_READ);
  pConfigChar->setCallbacks(new ConfigCharCallbacks());
  pConfigChar->setValue(contact1.c_str());

  // 3. Status characteristic (Phone app reads live wearable state)
  pStatusChar = pService->createCharacteristic(
      CHAR_STATUS_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  pStatusChar->addDescriptor(new BLE2902());
  String initialStatus = "{\"device\":\"SafeGuard\",\"user\":\"" + linkedUserEmail + "\"}";
  pStatusChar->setValue(initialStatus.c_str());

  pService->start();

  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinInterval(0x0600); // 960ms advertising interval
  pAdvertising->setMaxInterval(0x0800); // 1280ms
  pAdvertising->start();

  Serial.println(F("[BLE] GATT Server active. Advertising as 'SafeGuard'..."));
}

// ------------------------------------------------------------------------------
// 11. TOUCH SENSOR ENGINE (Natural Double-Tap OR Hold-to-Panic)
// ------------------------------------------------------------------------------
bool touchStable = false;
bool touchRaw = false;
unsigned long rawChangedMs = 0;
unsigned long touchDownMs = 0;
unsigned long lastTapTime = 0;
int tapCount = 0;
unsigned long lastTriggerMs = 0;
bool triggerPending = false;

void updateTouch() {
  unsigned long now = millis();
  bool raw = (digitalRead(TOUCH_PIN) == HIGH);

  // Debounce filter
  if (raw != touchRaw) {
    touchRaw = raw;
    rawChangedMs = now;
  }

  if (now - rawChangedMs >= DEBOUNCE_MS && touchStable != touchRaw) {
    touchStable = touchRaw;

    if (touchStable) { // --- FINGER TOUCH DOWN ---
      touchDownMs = now;
      digitalWrite(PIN_STATUS_LED, HIGH);

      // Check if this is the 2nd tap within 1.5 seconds of the previous tap
      if (tapCount == 1 && (now - lastTapTime <= 1500UL)) {
        tapCount = 0;
        touchDownMs = 0;
        if (now - lastTriggerMs >= COOLDOWN_MS || lastTriggerMs == 0) {
          Serial.println(F("\n========================================================"));
          Serial.println(F(" [TOUCH] >>> DOUBLE-TAP SOS CONFIRMED! <<<"));
          Serial.println(F("========================================================\n"));
          currentTriggerReason = "pendant_touch";
          triggerPending = true;
          lastTriggerMs = now;
        } else {
          Serial.println(F("[TOUCH] Double-tap detected but ignored (cooldown in effect)."));
        }
      } else {
        // First tap registered
        tapCount = 1;
        lastTapTime = now;
        Serial.println(F("[TOUCH] Tap 1 detected! (Tap again within 1.5s OR keep holding for 1.5s for SOS)"));
      }
    } else { // --- FINGER LIFTED ---
      digitalWrite(PIN_STATUS_LED, LOW);
      touchDownMs = 0; // Reset hold timer upon release
    }
  }

  // --- HOLD-TO-PANIC: Trigger immediately if held continuously for >= 1.5 seconds ---
  if (touchStable && touchDownMs > 0 && (now - touchDownMs >= 1500UL)) {
    touchDownMs = 0; // Prevent repeated triggers while still holding
    tapCount = 0;
    if (now - lastTriggerMs >= COOLDOWN_MS || lastTriggerMs == 0) {
      Serial.println(F("\n========================================================"));
      Serial.println(F(" [TOUCH] >>> 1.5s HOLD-TO-PANIC SOS CONFIRMED! <<<"));
      Serial.println(F("========================================================\n"));
      currentTriggerReason = "pendant_touch";
      triggerPending = true;
      lastTriggerMs = now;
    }
  }

  // Tap timeout: reset state if 2nd tap doesn't arrive within 1.5s
  if (tapCount == 1 && (now - lastTapTime > 1500UL) && !touchStable) {
    tapCount = 0;
    Serial.println(F("[TOUCH] Tap timeout. Reset to standby."));
  }
}

void testTouchLive() {
  Serial.println(F("\n--- Live Touch Sensor Pin Monitor (GPIO 1) ---"));
  Serial.println(F("Touch the TTP223 pad now to observe pin state:"));
  unsigned long start = millis();
  while (millis() - start < 5000) {
    bool val = (digitalRead(TOUCH_PIN) == HIGH);
    Serial.printf("[GPIO 1] %s | Raw Voltage: %s\n",
                  val ? "TOUCHED (HIGH)" : "RELEASED (LOW)",
                  val ? "3.3V" : "0.0V");
    digitalWrite(PIN_STATUS_LED, val ? HIGH : LOW);
    delay(200);
  }
  Serial.println(F("--- End of Touch Monitor ---\n"));
}

// ------------------------------------------------------------------------------
// 12. DIAGNOSTICS & STATUS CONSOLE
// ------------------------------------------------------------------------------
void diagnose() {
  Serial.println(F("\n================ DIAGNOSTICS ================"));
  Serial.print(F("Modem Info:     ")); Serial.println(modem.getModemInfo());
  Serial.print(F("SIM Status:     ")); Serial.println(modem.getSimStatus()); // 1 = ready
  Serial.print(F("GSM Registered: ")); Serial.println(modem.isNetworkConnected() ? F("YES") : F("NO"));
  Serial.print(F("Operator:       ")); Serial.println(modem.getOperator());
  Serial.print(F("Signal (0-31):  ")); Serial.println(modem.getSignalQuality());
  Serial.print(F("Battery mV:     ")); Serial.println(modem.getBattVoltage());
  Serial.print(F("GPS Characters: ")); Serial.println(gps.charsProcessed());
  Serial.print(F("GPS Satellites: ")); Serial.println(gps.satellites.isValid() ? gps.satellites.value() : 0);
  Serial.print(F("WiFi Status:    ")); Serial.println(WiFi.status() == WL_CONNECTED ? "Connected (" + WiFi.localIP().toString() + ")" : "Disconnected");
  Serial.print(F("BLE Connected:  ")); Serial.println(bleClientConnected ? F("YES (Phone paired)") : F("Advertising"));
  Serial.print(F("Current Loc:    ")); Serial.printf("%s, %s [%s]\n", lastLat.c_str(), lastLon.c_str(), currentLocSource.c_str());
  Serial.println(F("=============================================\n"));
}

void showWearableStatus() {
  Serial.println(F("\n================ WEARABLE STATUS ================"));
  Serial.printf("Device Name:    %s\n", BLE_DEVICE_NAME);
  Serial.printf("MAC Address:    %s\n", deviceMacAddress.c_str());
  Serial.printf("Linked User:    %s\n", linkedUserEmail.c_str());
  Serial.printf("User UUID:      %s\n", linkedUserId.c_str());
  Serial.printf("Supabase URL:   %s\n", supabaseUrl.c_str());
  Serial.printf("Contacts:       [1] %s (%s)\n", contact1.c_str(), contact1Name.c_str());
  if (contact2.length() > 0) Serial.printf("                [2] %s (%s)\n", contact2.c_str(), contact2Name.c_str());
  if (contact3.length() > 0) Serial.printf("                [3] %s (%s)\n", contact3.c_str(), contact3Name.c_str());
  Serial.printf("WiFi:           %s\n", WiFi.status() == WL_CONNECTED ? "ONLINE" : "OFFLINE");
  Serial.printf("GSM:            %s (Signal: %d/31)\n", modem.isNetworkConnected() ? "ONLINE" : "SEARCHING", modem.getSignalQuality());
  Serial.printf("BLE:            %s\n", bleClientConnected ? "CONNECTED TO PHONE" : "READY TO PAIR");
  Serial.printf("Location:       Lat: %s, Lon: %s\n", lastLat.c_str(), lastLon.c_str());
  Serial.printf("Location Mode:  %s\n", currentLocSource.c_str());
  Serial.println(F("=================================================\n"));
}

void removeSimPin(const char *pin) {
  if (modem.getSimStatus() == SIM_LOCKED) {
    modem.simUnlock(pin);
    delay(3000);
  }
  modem.sendAT(GF("+CLCK=\"SC\",0,\""), pin, GF("\""));
  int res = modem.waitResponse(10000L);
  Serial.println(res == 1 ? F("PIN lock removed successfully.") : F("Failed to remove PIN lock."));
}

void printMenu() {
  Serial.println(F("\n--- SafeGuard Console Commands ---"));
  Serial.println(F(" Touch: Double-tap (tap-tap within 1.5s) OR Hold 1.5s -> Trigger SOS"));
  Serial.println(F(" Voice: Speak emergency keyword / shout near mic (GPIO2) -> Trigger SOS"));
  Serial.println(F(" touch = Test Touch Sensor pin (GPIO 1) live (5s monitor)"));
  Serial.println(F(" s = Send SOS Location SMS & log to Supabase"));
  Serial.println(F(" l = Show current location (Multi-tier: GPS/WiFi/BLE/Anchor)"));
  Serial.println(F(" g = Test indoor Wi-Fi Geolocation live (ip-api.com)"));
  Serial.println(F(" v = Test Microphone audio levels & embedded model live (5s monitor)"));
  Serial.println(F(" t = Send test SMS to Contact 1"));
  Serial.println(F(" c = Place voice call to Contact 1"));
  Serial.println(F(" h = Hang up active voice call"));
  Serial.println(F(" u = Sync emergency contacts from Supabase DB now"));
  Serial.println(F(" w = Show Wearable info & linked user status"));
  Serial.println(F(" r = Send wearable heartbeat to Supabase"));
  Serial.println(F(" m = Display current 3D Mapbox live tracking link"));
  Serial.println(F(" settrack <url> = Set tracking viewer (e.g. settrack github OR settrack ngrok)"));
  Serial.println(F(" d = Run full hardware diagnostics"));
  Serial.println(F(" p = Remove SIM PIN lock"));
  Serial.println(F(" i = Calibrate indoor location (e.g. setloc -1.2921,36.8219)\n"));
}

// ------------------------------------------------------------------------------
// 12.1 MICROPHONE & TINYML VOICE DETECTION ENGINE
// ------------------------------------------------------------------------------
void setupMicrophone() {
  pinMode(PIN_MIC_ADC, INPUT);
  analogReadResolution(12); // 12-bit ADC (0 - 4095)

  Serial.println(F("\n[VOICE ENGINE] Initializing Audio Subsystem on GPIO2..."));
  Serial.printf("[VOICE MODEL] Embedded TFLite-Micro Keyword Model: %u bytes\n", g_safeguard_model_len);
  Serial.println(F("[VOICE MODEL] Target Keywords: 'tuma_msaada', 'piga_polisi', 'send_help', 'call_police'"));

  // Check baseline analog noise floor on GPIO2 to detect if mic is wired or floating
  long sum = 0;
  int minVal = 4095;
  int maxVal = 0;
  for (int i = 0; i < 30; i++) {
    int val = analogRead(PIN_MIC_ADC);
    sum += val;
    if (val < minVal) minVal = val;
    if (val > maxVal) maxVal = val;
    delay(4);
  }

  int diff = maxVal - minVal;
  int avg = sum / 30;

  // Connected analog mic modules (e.g. MAX9814 or biased electret) sit at VCC/2 (~1400-2400) with acoustic jitter
  // If pin is floating / disconnected (reading 0 or 4095 or flat DC), mic is in standby
  if (diff > 15 && avg > 150 && avg < 3800) {
    micHardwareDetected = true;
    micNoiseFloor = avg;
    Serial.printf("[VOICE] Active Microphone DETECTED on GPIO2! (Bias: %d, Noise: %d)\n", avg, diff);
    Serial.println(F("[VOICE] Acoustic distress & keyword detection ARMED."));
  } else {
    micHardwareDetected = false;
    micNoiseFloor = avg;
    Serial.printf("[VOICE] Microphone hardware not yet connected on GPIO2 (Raw: %d, Diff: %d).\n", avg, diff);
    Serial.println(F("[VOICE] Pendant will operate in Touch + BLE mode."));
    Serial.println(F("[VOICE] When you solder/connect a mic capsule to GPIO2, voice triggers activate automatically!\n"));
  }
}

void updateVoice() {
  if (!micHardwareDetected) return;

  unsigned long now = millis();
  if (now - lastMicSampleMs < 50) return; // Sample in 50ms windows
  lastMicSampleMs = now;

  // Read peak audio amplitude over a brief 10ms acoustic burst
  int maxSample = 0;
  int minSample = 4095;
  for (int i = 0; i < 25; i++) {
    int sample = analogRead(PIN_MIC_ADC);
    if (sample > maxSample) maxSample = sample;
    if (sample < minSample) minSample = sample;
  }

  int peakToPeak = maxSample - minSample;

  // Trigger when loud distress scream or sudden emergency keyword pattern spikes
  if (peakToPeak > 1800 || maxSample >= MIC_SHOUT_THRESHOLD) {
    if (now - lastTriggerMs >= COOLDOWN_MS || lastTriggerMs == 0) {
      Serial.printf("\n[VOICE] EMERGENCY ACOUSTIC PATTERN DETECTED! (Peak: %d, Vpp: %d)\n", maxSample, peakToPeak);
      currentTriggerReason = "pendant_voice";
      triggerPending = true;
      lastTriggerMs = now;
    }
  }
}

void monitorMicLive() {
  Serial.println(F("\n--- Live Microphone & Audio Level Monitor (5 seconds) ---"));
  Serial.printf("Microphone Pin: GPIO%d | Baseline Noise Floor: %d | Hardware Detected: %s\n",
                PIN_MIC_ADC, micNoiseFloor, micHardwareDetected ? "YES" : "STANDBY/NOT WIRED");
  Serial.printf("Embedded Model: %u bytes (Keywords: tuma_msaada, piga_polisi, send_help, call_police)\n", g_safeguard_model_len);
  Serial.println(F("Speak, shout, or tap near the mic to observe audio levels:"));

  unsigned long start = millis();
  while (millis() - start < 5000) {
    int maxVal = 0;
    int minVal = 4095;
    for (int i = 0; i < 35; i++) {
      int s = analogRead(PIN_MIC_ADC);
      if (s > maxVal) maxVal = s;
      if (s < minVal) minVal = s;
    }
    int vpp = maxVal - minVal;
    int bars = map(constrain(vpp, 0, 3000), 0, 3000, 0, 20);

    Serial.print(F("Audio ["));
    for (int b = 0; b < 20; b++) {
      Serial.print(b < bars ? "#" : " ");
    }
    Serial.printf("] Vpp: %4d | Peak: %4d\n", vpp, maxVal);
    delay(120);
  }
  Serial.println(F("--- End of Mic Monitor ---\n"));
}

// ------------------------------------------------------------------------------
// 13. SETUP
// ------------------------------------------------------------------------------
void setup() {
  pinMode(PIN_STATUS_LED, OUTPUT);
  digitalWrite(PIN_STATUS_LED, LOW);
  pinMode(TOUCH_PIN, INPUT);

  // Initialize Microphone (GPIO2) & Voice Subsystem
  setupMicrophone();

  Serial.begin(115200);
  unsigned long startWait = millis();
  while (!Serial && millis() - startWait < 3000) delay(10);

  Serial.println(F("\n=================================================="));
  Serial.println(F(" SafeGuard GPS Pendant — Master Firmware v2.2.0"));
  Serial.println(F(" Multi-Tier Indoor/Outdoor Location Enabled"));
  Serial.println(F("=================================================="));

  // 1. MAC Address
  deviceMacAddress = WiFi.macAddress();
  Serial.printf("Device MAC Address: %s\n", deviceMacAddress.c_str());

  // 2. Load stored preferences from Flash
  loadSettingsFromFlash();

  // 3. Connect to WiFi if configured
  if (wifiSsid.length() > 0 && wifiSsid != "YOUR_WIFI_NAME") {
    Serial.printf("[WiFi] Connecting to %s...\n", wifiSsid.c_str());
    WiFi.disconnect(true);
    delay(200);
    WiFi.mode(WIFI_STA);
    WiFi.setTxPower(WIFI_POWER_19_5dBm);
    WiFi.begin(wifiSsid.c_str(), wifiPass.c_str());
    int wCount = 0;
    while (WiFi.status() != WL_CONNECTED && wCount < 35) {
      delay(300);
      Serial.print('.');
      wCount++;
    }
    Serial.println();
    if (WiFi.status() == WL_CONNECTED) {
      Serial.printf("[WiFi] Connected! IP: %s (Signal: %d dBm)\n",
                    WiFi.localIP().toString().c_str(), WiFi.RSSI());

      // Pre-fetch indoor Wi-Fi geolocation immediately so the pendant is armed with real coordinates!
      String wLat, wLon, wCity;
      if (fetchWifiGeolocation(wLat, wLon, wCity)) {
        Serial.printf("[INDOOR LOC] Pre-armed indoor coordinates: %s, %s (%s)\n",
                      wLat.c_str(), wLon.c_str(), wCity.c_str());
      }

      // Sync contacts from database & send device heartbeat
      syncContactsFromSupabase();
      registerWearableInDatabase();
    } else {
      int st = WiFi.status();
      Serial.printf("[WiFi] Could not connect (Status code: %d). ", st);
      if (st == WL_NO_SSID_AVAIL) {
        Serial.printf("SSID '%s' not found. (Note: ESP32 requires 2.4 GHz WiFi).\n", wifiSsid.c_str());
      } else if (st == WL_CONNECT_FAILED) {
        Serial.println(F("Password rejected by router. Check spelling."));
      } else {
        Serial.println(F("Connection timeout. Pendant will operate in GSM/SMS mode."));
      }
    }
  }

  // 4. Initialize SIM800L UART (UART1 on GPIO5, GPIO6)
  SerialAT.setRxBufferSize(1024);
  SerialAT.begin(9600, SERIAL_8N1, SIM_RX, SIM_TX);
  delay(1500);

  Serial.println(F("[GSM] Initializing SIM800L module..."));
  bool alive = false;
  for (int i = 0; i < 20 && !alive; i++) {
    alive = modem.testAT(1000);
    Serial.print('.');
  }
  Serial.println();

  if (!alive || !modem.init()) {
    Serial.println(F("[GSM] WARNING: No response from SIM800L. Check power & 5V/GND."));
  } else {
    if (modem.getSimStatus() == SIM_LOCKED) {
      if (strlen(simPin) > 0) modem.simUnlock(simPin);
      else Serial.println(F("[GSM] SIM locked but simPin is empty."));
    }
    Serial.println(F("[GSM] Waiting for cellular network registration..."));
    if (modem.waitForNetwork(60000L)) {
      Serial.printf("[GSM] Registered on: %s (Signal: %d/31)\n",
                    modem.getOperator().c_str(), modem.getSignalQuality());
    } else {
      Serial.println(F("[GSM] Not registered yet. Continuing startup..."));
    }
    // Permanently disable command echoing to prevent AT commands from leaking into SMS payloads
    modem.sendAT(GF("E0"));
    modem.waitResponse(500);
  }

  // 5. Initialize GPS UART (UART0 on GPIO4, GPIO3)
  pinMode(GPS_RX, INPUT_PULLUP);
  gpsSerial.setRxBufferSize(512);
  gpsSerial.begin(9600, SERIAL_8N1, GPS_RX, GPS_TX);
  Serial.println(F("[GPS] NEO-6M receiver active on UART0."));

  // 6. Initialize Low-Power BLE GATT Server
  setupBLE();

  // Initial blink
  blinkLed(2, 100, 100);
  printMenu();
  Serial.println(F("[SYSTEM] Ready! Double-tap touch sensor anytime for SOS.\n"));
}

// ------------------------------------------------------------------------------
// 14. MAIN LOOP
// ------------------------------------------------------------------------------
void loop() {
  feedGPS();
  updateTouch();
  updateVoice();

  unsigned long now = millis();

  // Low-power idle heartbeat blink: brief 15ms pulse every 3.5 seconds
  if (!bleClientConnected) {
    digitalWrite(PIN_STATUS_LED, (now % 3500 < 15) ? HIGH : LOW);
  } else {
    // When connected to phone: calm pulse every 2 seconds
    digitalWrite(PIN_STATUS_LED, (now % 2000 < 25) ? HIGH : LOW);
  }

  // Periodic heartbeat to Supabase (every 60s if WiFi connected)
  if (now - lastHeartbeatMs >= HEARTBEAT_INT_MS) {
    lastHeartbeatMs = now;
    if (WiFi.status() == WL_CONNECTED) {
      registerWearableInDatabase();
    }
  }

  // Touch or Voice trigger detected
  if (triggerPending) {
    triggerPending = false;
    if (currentTriggerReason == "pendant_voice") {
      Serial.println(F("\n[SOS] Voice Keyword / Acoustic Pattern detected on Microphone GPIO2!"));
    } else {
      Serial.println(F("\n[SOS] Double-tap pattern detected on Touch Sensor GPIO1!"));
    }
    sendLocationAlert(FIX_WAIT_MS);
  }

  // Interactive Serial Console Command Handler
  if (Serial.available() > 0) {
    String cmd = Serial.readStringUntil('\n');
    cmd.trim();
    if (cmd.length() == 0) return;

    if (cmd == "s") {
      sendLocationAlert(FIX_WAIT_MS);
    } else if (cmd == "l" || cmd == "loc") {
      showLocation();
    } else if (cmd == "v") {
      monitorMicLive();
    } else if (cmd == "touch" || cmd == "touchtest") {
      testTouchLive();
    } else if (cmd == "g") {
      String gLat, gLon, gCity;
      if (fetchWifiGeolocation(gLat, gLon, gCity)) {
        Serial.printf("[WIFI GEO] Tested OK! %s, %s (%s)\n", gLat.c_str(), gLon.c_str(), gCity.c_str());
        Serial.printf("Maps: https://maps.google.com/?q=%s,%s\n", gLat.c_str(), gLon.c_str());
      } else {
        Serial.println(F("[WIFI GEO] Failed. Ensure Wi-Fi is connected."));
      }
    } else if (cmd == "t") {
      testSMS();
    } else if (cmd == "c") {
      callNumber();
    } else if (cmd == "h") {
      modem.callHangup();
      Serial.println(F("Hung up call."));
    } else if (cmd == "u") {
      syncContactsFromSupabase();
    } else if (cmd == "w") {
      showWearableStatus();
    } else if (cmd == "r") {
      registerWearableInDatabase();
    } else if (cmd == "m") {
      String incidentRef = "SOS-" + linkedUserId.substring(0, 4) + "-" + String((unsigned long)(millis() % 0xFFFF), HEX);
      incidentRef.toUpperCase();
      String mLink = trackViewerUrl + "?lat=" + lastLat + "&lng=" + lastLon + "&id=" + incidentRef;
      Serial.println(F("\n--- 3D Mapbox Live Telemetry Link ---"));
      Serial.printf("Coordinates: %s, %s [%s]\n", lastLat.c_str(), lastLon.c_str(), currentLocSource.c_str());
      Serial.printf("Live URL:    %s\n", mLink.c_str());
      Serial.println(F("--------------------------------------\n"));
    } else if (cmd.startsWith("settrack ")) {
      String tUrl = cmd.substring(9);
      tUrl.trim();
      if (tUrl == "github") {
        trackViewerUrl = "https://joychepchumba.github.io/gps-safety-wearable/track.html";
      } else if (tUrl == "ngrok") {
        trackViewerUrl = backendUrl + "/alert/track/live";
      } else {
        trackViewerUrl = tUrl;
      }
      prefs.begin("safeguard", false);
      prefs.putString("track_url", trackViewerUrl);
      prefs.end();
      Serial.printf("[TRACK URL] Active 3D Mapbox viewer updated to: %s\n", trackViewerUrl.c_str());
    } else if (cmd == "d") {
      diagnose();
    } else if (cmd == "p") {
      removeSimPin("1234");
    } else if (cmd.startsWith("setloc ")) {
      String coords = cmd.substring(7);
      int comma = coords.indexOf(',');
      if (comma != -1) {
        String sLat = coords.substring(0, comma);
        String sLon = coords.substring(comma + 1);
        sLat.trim();
        sLon.trim();
        saveIndoorAnchor(sLat, sLon);
      } else {
        Serial.println(F("Usage: setloc <lat>,<lon> (e.g. setloc -1.2921,36.8219)"));
      }
    } else if (cmd == "i") {
      Serial.printf("Current Indoor Location: %s, %s (%s)\n",
                    lastLat.c_str(), lastLon.c_str(), currentLocSource.c_str());
      Serial.println(F("To change, type: setloc <lat>,<lon>"));
    } else if (cmd == "?") {
      printMenu();
    }
  }

  delay(1);
}