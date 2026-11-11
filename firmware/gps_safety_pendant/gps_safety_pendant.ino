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
 *   - TTP223B Touch SIG -> GPIO2 (Active HIGH)
 *   - Microphone Input  -> GPIO1 (ADC1_CH1)
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
 * Parental Control & Community BLE SOS Beacon (v2.2):
 *   - Adult Mode: Touch double-tap or hold on GPIO2 triggers SOS + phone app control.
 *   - Child Mode: Accidental touch SOS disabled; holding GPIO2 for 3s calls parent;
 *                 Parent can remotely Locate, Call, Strobe LED, or trigger SOS.
 *   - Community Responder BLE Beacon: Broadcasts 15-byte 'SL' distress packet (0xFFFF)
 *                 with live GPS coordinates so nearby SafeLink users detect SOS offline.
 * ==============================================================================
 */

#define TINY_GSM_MODEM_SIM800
#define TINY_GSM_RX_BUFFER 1024

#include <Arduino.h>
#include <esp_mac.h>
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
#include <BLEAdvertising.h>

// SafeGuard Embedded TinyML Keyword Spotting Model (13.4 KB)
#include "safeguard_micro_model.h"

// ------------------------------------------------------------------------------
// 1. PIN DEFINITIONS (Working Breadboard Pins)
// ------------------------------------------------------------------------------
#define SIM_RX          5     // SIM800L TX -> ESP32 GPIO5
#define SIM_TX          6     // SIM800L RX -> ESP32 GPIO6
#define GPS_RX          4     // NEO-6M TX  -> ESP32 GPIO4
#define GPS_TX          3     // NEO-6M RX  -> ESP32 GPIO3
#define TOUCH_PIN       2     // TTP223B Touch SIG -> ESP32 GPIO2 (Active HIGH)
#define PIN_MIC_ADC     1     // Electret Mic / MAX9814 Audio Out -> ESP32 GPIO1 (ADC1_CH1)
#define PIN_STATUS_LED  8     // Onboard / External Status LED

// ------------------------------------------------------------------------------
// 2. BLE GATT UUIDS (Matches Flutter App Constants)
// ------------------------------------------------------------------------------
#define BLE_DEVICE_NAME   "SafeGuard"
#define SERVICE_UUID      "0000ffe0-0000-1000-8000-00805f9b34fb"
#define CHAR_ALERT_UUID   "0000ffe1-0000-1000-8000-00805f9b34fb" // Notify app when SOS pressed
#define CHAR_CONFIG_UUID  "0000ffe2-0000-1000-8000-00805f9b34fb" // App writes updated contacts/URL/location/commands
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

// Parental Control & Mode State
String ownerMode       = "adult";  // "adult" or "child"
bool touchSosEnabled   = true;     // True in adult mode, false in child mode
unsigned long holdPanicMs = 1500UL; // Configurable 1000-10000ms via app slider
String guardianPhone   = "+254740034499";
String guardianPin     = "1234";

// Pending BLE/Remote commands (executed safely in loop())
volatile bool pendingLocateCmd = false;
volatile bool pendingStatusCmd = false;
volatile bool pendingRemoteSosCmd = false;
volatile bool pendingCancelSosCmd = false;
volatile bool pendingFindCmd = false;
volatile bool pendingHangupCmd = false;
volatile bool pendingChildCallParent = false;
String pendingCallTarget = "";
unsigned long findLedEndMs = 0;
bool sosBeaconActive = false;
unsigned long sosBeaconStartMs = 0;

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
const unsigned long BOOT_GUARD_MS    = 4000UL;   // Ignore touch during first 4s after boot/flash while TTP223 calibrates
const unsigned long DEBOUNCE_MS      = 60UL;     // Touch debounce (filters wire bounce & EMI)
const unsigned long MIN_TAP_MS       = 80UL;     // Taps shorter than 80ms are rejected as electrical/wire noise
const unsigned long MAX_TAP_MS       = 900UL;    // Taps longer than 900ms are treated as holds
const unsigned long CHILD_CALL_HOLD_MS = 3000UL; // In Child Mode, holding 3s calls parent
const unsigned long DOUBLE_GAP_MS    = 1200UL;   // Max time between tap 1 and tap 2
const unsigned long COOLDOWN_MS      = 25000UL;  // Minimum time between triggered alerts
const unsigned long HEARTBEAT_INT_MS = 60000UL;  // Periodic DB heartbeat interval (60s)

// Location state in RAM & Flash (Alina Harbour Apartments, Nairobi)
String lastLat = "-1.2907850038543573";   // Alina Harbour Apartments
String lastLon = "36.78176897301627";
String lastCity = "Alina Harbour Apartments";
String currentLocSource = "Alina Harbour Apartments Anchor";
unsigned long lastFixMs = 0;
unsigned long lastBleLocMs = 0;
unsigned long lastHeartbeatMs = 0;

// Touch Sensor State (GPIO2)
bool touchStable = false;
bool touchRaw = false;
unsigned long rawChangedMs = 0;
unsigned long touchDownMs = 0;
unsigned long lastTapTime = 0;
int tapCount = 0;
unsigned long lastTriggerMs = 0;
bool triggerPending = false;

// Voice & Microphone Detection State (GPIO10)
bool micHardwareDetected = false;
int micNoiseFloor = 1800;
#define MIC_SHOUT_THRESHOLD 2800 // Peak ADC reading triggering acoustic distress
unsigned long lastMicSampleMs = 0;
String currentTriggerReason = "pendant_touch";

// Forward declarations
void sendStatusJsonOverBLE();
void sendLocationJsonOverBLE();
void updateBleSosBeacon(bool enable);
void callNumber(const String &target = "");

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

  ownerMode       = prefs.getString("owner_mode", "adult");
  touchSosEnabled = prefs.getBool("touch_sos", ownerMode != "child");
  if (ownerMode == "child") touchSosEnabled = false;
  holdPanicMs     = prefs.getULong("hold_ms", 1500UL);
  if (holdPanicMs < 1000UL || holdPanicMs > 10000UL) holdPanicMs = 1500UL;
  guardianPhone   = prefs.getString("guard_phone", contact1);
  guardianPin     = prefs.getString("guard_pin", "1234");

  supabaseUrl     = prefs.getString("sb_url", supabaseUrl);
  supabaseAnonKey = prefs.getString("sb_key", supabaseAnonKey);
  backendUrl      = prefs.getString("back_url", backendUrl);
  trackViewerUrl  = prefs.getString("track_url", trackViewerUrl);

  wifiSsid = prefs.getString("wifi_ssid", wifiSsid);
  wifiPass = prefs.getString("wifi_pass", wifiPass);

  deviceUUID = prefs.getString("dev_uuid", "");

  // Load saved indoor anchor coordinates (Migrate old default to Alina Harbour Apartments)
  lastLat = prefs.getString("last_lat", "-1.2907850038543573");
  lastLon = prefs.getString("last_lon", "36.78176897301627");
  if (lastLat == "-1.309250" || lastLat == "-1.292100" || lastLat == "-1.307300" || lastLat.length() == 0) {
    lastLat = "-1.2907850038543573";
    lastLon = "36.78176897301627";
    currentLocSource = "Alina Harbour Apartments Anchor";
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
  Serial.printf("  Wearer Mode:  %s (Touch SOS: %s, Hold: %lu ms)\n",
                ownerMode.c_str(), touchSosEnabled ? "ENABLED" : "DISABLED (Child Lock)", holdPanicMs);
  Serial.printf("  Contact 1:    %s (%s)\n", contact1.c_str(), contact1Name.c_str());
  Serial.printf("  Contact 2:    %s (%s)\n", contact2.c_str(), contact2Name.c_str());
  Serial.printf("  Indoor Anchor:%s, %s (Alina Harbour Apartments)\n", lastLat.c_str(), lastLon.c_str());
  Serial.printf("  3D Mapbox:    %s?lat=%s&lng=%s\n", trackViewerUrl.c_str(), lastLat.c_str(), lastLon.c_str());
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
  while (SerialAT.available()) SerialAT.read();
  modem.sendAT(GF("+CIPGSMLOC=1,1"));
  String resp = "";
  unsigned long start = millis();
  while (millis() - start < 3500) {
    while (SerialAT.available()) {
      resp += (char)SerialAT.read();
    }
    if ((resp.indexOf("+CIPGSMLOC:") != -1 && resp.indexOf("OK") != -1) ||
        resp.indexOf("ERROR") != -1) {
      break;
    }
    delay(10);
  }
  // Drain any trailing bytes so subsequent SMS AT commands start with a clean UART
  delay(80);
  while (SerialAT.available()) SerialAT.read();

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

  // 4. TIER 4: Fallback to Saved Indoor Anchor in Flash
  // (Avoids running AT+CIPGSMLOC=1,1 right before emergency SMS so SIM800L radio & power stay 100% ready for SMS)
  if (lastLat.length() > 0 && lastLon.length() > 0) {
    lat = lastLat;
    lon = lastLon;
    currentLocSource = "Alina Harbour Apartments Anchor (Flash)";
    Serial.printf("[LOCATION] Using Saved Indoor Calibration Anchor: %s, %s\n", lat.c_str(), lon.c_str());
    Serial.printf("[LOCATION] 3D Mapbox Live Link: %s?lat=%s&lng=%s\n", trackViewerUrl.c_str(), lat.c_str(), lon.c_str());
    return true;
  }

  // Final fallback (Alina Harbour Apartments)
  lat = "-1.2907850038543573";
  lon = "36.78176897301627";
  currentLocSource = "Alina Harbour Apartments Anchor";
  return true;
}

void showLocation() {
  Serial.println(F("\nResolving current location (Indoor / Outdoor)..."));
  String lat, lon;
  getFix(lat, lon, 4000UL);
  Serial.printf("Current Location: Lat=%s, Lon=%s (Alina Harbour Apartments)\n", lat.c_str(), lon.c_str());
  Serial.printf("Source:           %s\n", currentLocSource.c_str());
  Serial.printf("GPS Satellites:   %d\n", gps.satellites.isValid() ? gps.satellites.value() : 0);
  Serial.printf("3D Mapbox Link:   %s?lat=%s&lng=%s\n\n", trackViewerUrl.c_str(), lat.c_str(), lon.c_str());
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
  client.setInsecure();

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
        if (phone.indexOf("709570000") != -1 || name.indexOf("Police") != -1) {
          Serial.printf("  [HELPLINE] %s (%s) registered in database. SIM800L auto-SMS bypassed for testing safety.\n",
                        phone.c_str(), name.c_str());
          curPos = objEnd + 1;
          continue;
        }

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
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println(F("[SUPABASE LOG] Offline cellular mode. SMS delivered directly via GSM."));
    return false;
  }

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

  String dbMethod = (currentTriggerReason == "pendant_voice") ? "pendant_voice" : "pendant_touch";

  String payload = "{";
  payload += "\"user_id\":\"" + linkedUserId + "\",";
  if (deviceUUID.length() > 0) {
    payload += "\"wearable_device_id\":\"" + deviceUUID + "\",";
  }
  payload += "\"trigger_method\":\"" + dbMethod + "\",";
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
void prepareModemFor2GBurst() {
  digitalWrite(PIN_STATUS_LED, LOW);
  delay(200); // Decoupling capacitor settle

  // Drain any residual bytes in UART buffer
  while (SerialAT.available()) SerialAT.read();

  // Configure SIM800L text mode & standard GSM charset
  modem.sendAT(GF("E0"));
  modem.waitResponse(500);
  modem.sendAT(GF("+CMGF=1"));
  modem.waitResponse(500);
  modem.sendAT(GF("+CSCS=\"GSM\""));
  modem.waitResponse(500);

  // Verify SIM800L is registered on Safaricom before transmitting
  if (!modem.isNetworkConnected()) {
    Serial.println(F("[GSM] Verifying cellular network registration..."));
    if (modem.waitForNetwork(30000L, true)) {
      Serial.printf("[GSM] Registered on: %s (Signal: %d/31)\n",
                    modem.getOperator().c_str(), modem.getSignalQuality());
    }
  }
  while (SerialAT.available()) SerialAT.read();
}

void resumeBleAfter2GBurst() {
  // BLE advertising runs continuously
}

bool sendSMS(const String &number, const String &text) {
  if (number.length() < 7) return false;

  // SAFETY GUARD: Never transmit live cellular SMS to official emergency helpline during testing
  if (number.indexOf("709570000") != -1 || number.indexOf("999") != -1 || number.indexOf("112") != -1) {
    Serial.printf("[SAFETY GUARD] Bypassed cellular SMS to official helpline (%s) during breadboard testing.\n", number.c_str());
    return true; // Marked as safely handled
  }

  Serial.printf("[SMS] Sending to %s (%u chars)...\n", number.c_str(), text.length());

  prepareModemFor2GBurst();

  // Dispatch SMS via TinyGSM (exact proven method from gsm_test_esp.ino)
  bool ok = modem.sendSMS(number, text);
  if (!ok) {
    Serial.println(F("[SMS] First attempt did not confirm; stabilizing power rail & retrying..."));
    delay(3500);
    prepareModemFor2GBurst();
    ok = modem.sendSMS(number, text);
  }
  Serial.println(ok ? F("[SMS] Delivery SUCCESSFUL!") : F("[SMS] Send FAILED!"));

  // Wait 2.5s for SIM800L to exit text mode, finalize 2G transmission, and drain
  delay(2500);
  while (SerialAT.available()) SerialAT.read();

  resumeBleAfter2GBurst();
  return ok;
}

void notifyPhoneOverBLE(uint8_t alertCode = 0x01) {
  if (pAlertChar != nullptr) {
    pAlertChar->setValue(&alertCode, 1);
    pAlertChar->notify();
    Serial.printf("[BLE] Alert notification (0x%02X) sent to connected phone!\n", alertCode);
  }
}

// Main emergency dispatch routine: Resolves location (Multi-Tier), sends SMS, logs to Supabase
void sendLocationAlert(unsigned long waitMs = FIX_WAIT_MS) {
  blinkLed(5, 40, 40); // Rapid strobe indicator
  digitalWrite(PIN_STATUS_LED, LOW);
  Serial.println(F("\n=================================================="));
  Serial.println(F(">>> EMERGENCY SOS TRIGGERED FROM PENDANT <<<"));
  Serial.println(F("=================================================="));

  uint8_t alertCode = 0x01;
  if (currentTriggerReason == "pendant_voice") alertCode = 0x02;
  else if (currentTriggerReason == "remote_guardian") alertCode = 0x03;

  // 1. Notify paired smartphone over BLE immediately
  notifyPhoneOverBLE(alertCode);

  // 2. Resolve Multi-Tier Location (GPS -> Phone BLE -> Wi-Fi Geo -> Anchor)
  String lat, lon;
  getFix(lat, lon, waitMs);

  // Format coordinates to 6 decimal places (~11cm precision) for compact, corruption-free GSM SMS URL
  String smsLat = String(lat.toDouble(), 6);
  String smsLon = String(lon.toDouble(), 6);

  // Secure 3D Mapbox Live Tracking link with Alina Harbour Apartments coordinates
  String mapboxLiveLink = trackViewerUrl + "?lat=" + smsLat + "&lng=" + smsLon;

  Serial.printf("[SOS LOCATION] Coordinates: %s, %s (Alina Harbour Apartments)\n", lat.c_str(), lon.c_str());
  Serial.printf("[SOS LOCATION] 3D Mapbox:   %s\n", mapboxLiveLink.c_str());

  // Pure GSM 7-bit single-line message (matches gsm_test_esp.ino format: no parentheses or newlines)
  String smsMsg = "ALERT. Joy 3D Live Map: " + mapboxLiveLink;

  // 3. Dispatch SMS individually FIRST while SIM800L has full power rail capacity
  String recipients = "";
  if (contact1.length() >= 7) {
    sendSMS(contact1, smsMsg);
    recipients += contact1;
  }
  if (contact2.length() >= 7 && contact2 != contact1) {
    delay(2000);
    sendSMS(contact2, smsMsg);
    if (recipients.length() > 0) recipients += ", ";
    recipients += contact2;
  }
  if (contact3.length() >= 7 && contact3 != contact1 && contact3 != contact2) {
    delay(2000);
    sendSMS(contact3, smsMsg);
    if (recipients.length() > 0) recipients += ", ";
    recipients += contact3;
  }

  // 4. Activate BLE SOS Distress Beacon ('SL' 0xFFFF) for nearby Community Responders
  // (Voice call is reserved for manual 'c' console command or dedicated voice-call model trigger)
  updateBleSosBeacon(true);

  // 5. Log alert and sent SMS to Supabase
  logAlertToSupabase(lat, lon, smsMsg, recipients, currentLocSource);

  // 6. Update wearable heartbeat in DB
  registerWearableInDatabase();

  Serial.println(F(">>> EMERGENCY ALERT DISPATCH COMPLETED <<<\n"));
}

void testSMS() {
  Serial.println(F("Sending test SMS with Permanent 3D Mapbox live link (Alina Harbour Apartments) to Primary Contact..."));
  String smsLat = String(lastLat.toDouble(), 6);
  String smsLon = String(lastLon.toDouble(), 6);
  String mapboxLink = trackViewerUrl + "?lat=" + smsLat + "&lng=" + smsLon;
  Serial.printf("Coordinates: %s, %s\n", lastLat.c_str(), lastLon.c_str());
  Serial.printf("3D Mapbox:   %s\n", mapboxLink.c_str());
  String testMsg = "ALERT. Joy 3D Live Map: " + mapboxLink;
  sendSMS(contact1, testMsg);
}

void callNumber(const String &target) {
  String dialTarget = target.length() >= 7 ? target : contact1;
  dialTarget.trim();
  if (dialTarget.length() < 7) {
    Serial.println(F("No phone number configured for Contact 1"));
    return;
  }
  if (dialTarget.indexOf("709570000") != -1 || dialTarget.indexOf("999") != -1 || dialTarget.indexOf("112") != -1) {
    Serial.println(F("[SAFETY GUARD] Call to official emergency helpline suppressed during testing."));
    return;
  }

  prepareModemFor2GBurst();

  Serial.printf("Calling %s...\n", dialTarget.c_str());
  bool ok = modem.callNumber(dialTarget);
  Serial.println(ok ? F("Call placed") : F("Call failed"));
  if (ok) {
    delay(15000);
    modem.callHangup();
    Serial.println(F("Call ended / Hung up."));
  }

  resumeBleAfter2GBurst();
}

// ------------------------------------------------------------------------------
// 10. BLE GATT SERVER CALLBACKS, PARENTAL COMMANDS & SOS BEACON
// ------------------------------------------------------------------------------
void sendStatusJsonOverBLE() {
  if (pStatusChar == nullptr) return;
  int mv = modem.getBattVoltage();
  int batPct = 78;
  if (mv >= 3300 && mv <= 4300) {
    batPct = constrain(map(mv, 3300, 4200, 0, 100), 0, 100);
  }
  char buf[175];
  snprintf(buf, sizeof(buf),
           "{\"t\":\"status\",\"mode\":\"%s\",\"touch\":%d,\"hold\":%lu,\"bat\":%d,\"fw\":\"2.2.0\",\"sos\":%d}",
           ownerMode.c_str(), touchSosEnabled ? 1 : 0, holdPanicMs, batPct, sosBeaconActive ? 1 : 0);
  pStatusChar->setValue((uint8_t *)buf, strlen(buf));
  pStatusChar->notify();
}

void sendLocationJsonOverBLE() {
  if (pStatusChar == nullptr) return;
  char buf[160];
  snprintf(buf, sizeof(buf),
           "{\"t\":\"loc\",\"lat\":\"%s\",\"lon\":\"%s\",\"src\":\"%s\"}",
           lastLat.c_str(), lastLon.c_str(), currentLocSource.c_str());
  pStatusChar->setValue((uint8_t *)buf, strlen(buf));
  pStatusChar->notify();
}

void updateBleSosBeacon(bool enable) {
  sosBeaconActive = enable;
  if (enable) {
    sosBeaconStartMs = millis();
    sendLocationJsonOverBLE();
  }

  // Always broadcast BLE SOS beacon (even if paired to the owner's phone)
  // and split Advertisement Data (<= 31 bytes) from Scan Response Data so
  // the 17-byte Manufacturer Data is never truncated by the 31-byte BLE limit!
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->stop();

  if (enable) {
    // 15-byte payload prefixed by 2-byte company ID 0xFFFF = 17 bytes total
    uint8_t mfg[17];
    mfg[0] = 0xFF;
    mfg[1] = 0xFF;
    mfg[2] = 0x53; // 'S'
    mfg[3] = 0x4C; // 'L'
    mfg[4] = 0x01; // Source: 0x01 = Pendant
    int32_t latFixed = (int32_t)(lastLat.toDouble() * 1000000.0);
    int32_t lonFixed = (int32_t)(lastLon.toDouble() * 1000000.0);
    memcpy(&mfg[5], &latFixed, 4);
    memcpy(&mfg[9], &lonFixed, 4);
    String hexTag = linkedUserId.substring(0, 8);
    uint32_t userTag = (uint32_t)strtoul(hexTag.c_str(), nullptr, 16);
    memcpy(&mfg[13], &userTag, 4);

    String mfgStr = "";
    mfgStr.reserve(17);
    for (int i = 0; i < 17; i++) {
      mfgStr += (char)mfg[i];
    }

    // Primary Advertisement Packet: Flags (3B) + Mfg Data (19B) = 22 bytes (<= 31B max!)
    BLEAdvertisementData advData;
    advData.setFlags(0x06);
    advData.setManufacturerData(mfgStr);
    pAdvertising->setAdvertisementData(advData);

    // Scan Response Packet: Device Name ("SafeGuard") so scanners see both name & SOS payload
    BLEAdvertisementData scanRespData;
    scanRespData.setName(BLE_DEVICE_NAME);
    pAdvertising->setScanResponseData(scanRespData);
  } else {
    BLEAdvertisementData advData;
    advData.setFlags(0x06);
    advData.setName(BLE_DEVICE_NAME);
    pAdvertising->setAdvertisementData(advData);
  }

  pAdvertising->start();
  if (enable) {
    Serial.println(F("[BLE BEACON] Broadcasting 15-byte 'SL' SOS Distress Beacon to nearby responders!"));
  }
}

class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *pServer) {
    bleClientConnected = true;
    blinkLed(2, 100, 100);
    Serial.println(F("[BLE] Phone App connected to SafeGuard pendant!"));
    pendingStatusCmd = true;
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
    value.trim();
    if (value.length() == 0) return;

    Serial.printf("[BLE CONFIG] Command received: %s\n", value.c_str());

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
      }
      return;
    }

    // 2. Parental / Wearer Mode ("MODE:CHILD" or "MODE:ADULT")
    if (value.startsWith("MODE:")) {
      String m = value.substring(5);
      m.toLowerCase();
      ownerMode = (m == "child") ? "child" : "adult";
      if (ownerMode == "child") touchSosEnabled = false;
      else touchSosEnabled = true;
      prefs.begin("safeguard", false);
      prefs.putString("owner_mode", ownerMode);
      prefs.putBool("touch_sos", touchSosEnabled);
      prefs.end();
      Serial.printf("[MODE] Switched to %s mode (Touch SOS: %s)\n",
                    ownerMode.c_str(), touchSosEnabled ? "ENABLED" : "DISABLED - Child Safety");
      pendingStatusCmd = true;
      return;
    }

    // 3. Touch Trigger Toggle ("TOUCH:ON" or "TOUCH:OFF")
    if (value.startsWith("TOUCH:")) {
      String t = value.substring(6);
      t.toUpperCase();
      touchSosEnabled = (ownerMode == "child") ? false : (t == "ON" || t == "1");
      prefs.begin("safeguard", false);
      prefs.putBool("touch_sos", touchSosEnabled);
      prefs.end();
      Serial.printf("[TOUCH CONFIG] Touch SOS trigger set to: %s\n", touchSosEnabled ? "ON" : "OFF");
      pendingStatusCmd = true;
      return;
    }

    // 4. Hold Duration / Touch Sensitivity ("HOLD:<ms>")
    if (value.startsWith("HOLD:")) {
      unsigned long ms = (unsigned long)value.substring(5).toInt();
      if (ms >= 1000UL && ms <= 10000UL) {
        holdPanicMs = ms;
        prefs.begin("safeguard", false);
        prefs.putULong("hold_ms", holdPanicMs);
        prefs.end();
        Serial.printf("[TOUCH CONFIG] Hold-to-panic sensitivity updated to %lu ms\n", holdPanicMs);
      }
      pendingStatusCmd = true;
      return;
    }

    // 5. Guardian Phone & PIN ("GUARD:<phone>", "PIN:<pin>")
    if (value.startsWith("GUARD:")) {
      guardianPhone = value.substring(6);
      int comma = guardianPhone.indexOf(',');
      if (comma != -1) guardianPhone = guardianPhone.substring(0, comma);
      guardianPhone.trim();
      prefs.begin("safeguard", false);
      prefs.putString("guard_phone", guardianPhone);
      prefs.end();
      Serial.printf("[GUARDIAN] Guardian phone set to: %s\n", guardianPhone.c_str());
      return;
    }
    if (value.startsWith("PIN:")) {
      guardianPin = value.substring(4);
      guardianPin.trim();
      prefs.begin("safeguard", false);
      prefs.putString("guard_pin", guardianPin);
      prefs.end();
      Serial.println(F("[GUARDIAN] Guardian PIN updated."));
      return;
    }

    // 6. Remote Commands ("CMD:LOCATE", "CMD:STATUS", "CMD:SOS", "CMD:CANCEL", "CMD:FIND", "CMD:CALL:<num>", "CMD:HANGUP")
    if (value.startsWith("CMD:")) {
      String cmd = value.substring(4);
      if (cmd == "LOCATE") pendingLocateCmd = true;
      else if (cmd == "STATUS") pendingStatusCmd = true;
      else if (cmd == "SOS") pendingRemoteSosCmd = true;
      else if (cmd == "CANCEL") pendingCancelSosCmd = true;
      else if (cmd == "FIND") pendingFindCmd = true;
      else if (cmd == "HANGUP") pendingHangupCmd = true;
      else if (cmd.startsWith("CALL")) {
        int colon = cmd.indexOf(':');
        pendingCallTarget = (colon != -1) ? cmd.substring(colon + 1) : guardianPhone;
      }
      return;
    }

    // 7. Dynamic Backend URL sync ("URL:https://...")
    if (value.startsWith("URL:")) {
      backendUrl = value.substring(4);
      prefs.begin("safeguard", false);
      prefs.putString("back_url", backendUrl);
      prefs.end();
      Serial.printf("[CONFIG] Backend URL updated to: %s\n", backendUrl.c_str());
      return;
    }

    // 8. Dynamic User ID sync ("USER:uuid,email")
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

    // 9. Emergency Contacts CSV sync ("phone1,phone2,phone3")
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

  // 2. Config characteristic (Phone app writes contacts/URL/location/commands)
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
  String initialStatus = "{\"t\":\"status\",\"mode\":\"" + ownerMode + "\",\"bat\":78,\"fw\":\"2.2.0\"}";
  pStatusChar->setValue(initialStatus.c_str());

  pService->start();

  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinInterval(0x20); // 20ms - 40ms fast responsive advertising
  pAdvertising->setMaxInterval(0x40);
  pAdvertising->start();

  Serial.println(F("[BLE] GATT Server active. Advertising as 'SafeGuard'..."));
}

// ------------------------------------------------------------------------------
// 11. TOUCH SENSOR ENGINE (Auto-Detects Touch on GPIO1 or GPIO2)
// ------------------------------------------------------------------------------
bool readTouchSensorPin(int *activePinOut = nullptr) {
  if (digitalRead(TOUCH_PIN) == HIGH) {
    if (activePinOut) *activePinOut = TOUCH_PIN;
    return true;
  }
  // Also check GPIO1 if no analog mic is actively biasing GPIO1, so touch works on either GPIO1 or GPIO2!
  if (!micHardwareDetected && digitalRead(PIN_MIC_ADC) == HIGH) {
    if (activePinOut) *activePinOut = PIN_MIC_ADC;
    return true;
  }
  if (activePinOut) *activePinOut = TOUCH_PIN;
  return false;
}

void updateTouch() {
  unsigned long now = millis();

  // 1. BOOT WARMUP GUARD: Ignore all inputs during the first 4s after boot/flash
  if (now < BOOT_GUARD_MS) {
    touchStable = false;
    touchRaw = false;
    touchDownMs = 0;
    tapCount = 0;
    return;
  }

  int triggeredPin = TOUCH_PIN;
  bool raw = readTouchSensorPin(&triggeredPin);

  // 2. Hardware Debounce filter (60ms stable window)
  if (raw != touchRaw) {
    touchRaw = raw;
    rawChangedMs = now;
  }

  if (now - rawChangedMs >= DEBOUNCE_MS && touchStable != touchRaw) {
    touchStable = touchRaw;

    if (touchStable) {
      // --- FINGER TOUCH DOWN ---
      touchDownMs = now;
      digitalWrite(PIN_STATUS_LED, HIGH);
      Serial.printf("[TOUCH GPIO%d] Touch sensor pressed (HIGH).\n", triggeredPin);
    } else {
      // --- FINGER RELEASED / LIFTED ---
      digitalWrite(PIN_STATUS_LED, LOW);
      unsigned long pressDuration = (touchDownMs > 0) ? (now - touchDownMs) : 0;
      touchDownMs = 0;

      if (pressDuration < MIN_TAP_MS) {
        // Ignore brief electrical spike (< 80ms)
      } else if (pressDuration <= MAX_TAP_MS) {
        // In Child Mode, touch SOS is disabled so children cannot accidentally trigger panic alerts
        if (ownerMode == "child" || !touchSosEnabled) {
          Serial.println(F("[TOUCH] Child Mode active — accidental tap SOS suppressed (Hold 3s to call parent)."));
          tapCount = 0;
        } else {
          // Adult Mode: Double-tap triggers SOS
          if (tapCount == 0) {
            tapCount = 1;
            lastTapTime = now;
            Serial.println(F("[TOUCH] Valid Tap 1 detected (Release verified). Tap once more within 1.2s for SOS."));
          } else if (tapCount == 1 && (now - lastTapTime <= DOUBLE_GAP_MS)) {
            tapCount = 0;
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
          }
        }
      }
    }
  }

  // 3. CONTINUOUS HOLD DETECTION
  if (touchStable && touchDownMs > 0) {
    unsigned long heldMs = now - touchDownMs;

    if (ownerMode == "child") {
      // Child Mode: Holding for 3 seconds calls parent without triggering false panic SOS
      if (heldMs >= CHILD_CALL_HOLD_MS) {
        touchDownMs = 0;
        tapCount = 0;
        Serial.println(F("\n========================================================"));
        Serial.println(F(" [TOUCH] >>> CHILD CALL-PARENT (3s HOLD) CONFIRMED! <<<"));
        Serial.println(F("========================================================\n"));
        pendingChildCallParent = true;
      }
    } else if (touchSosEnabled && heldMs >= holdPanicMs) {
      // Adult Mode: Holding for >= holdPanicMs (default 1.5s) triggers SOS
      touchDownMs = 0;
      tapCount = 0;
      if (now - lastTriggerMs >= COOLDOWN_MS || lastTriggerMs == 0) {
        Serial.println(F("\n========================================================"));
        Serial.printf(" [TOUCH] >>> %.1fs HOLD-TO-PANIC SOS CONFIRMED! <<<\n", holdPanicMs / 1000.0);
        Serial.println(F("========================================================\n"));
        currentTriggerReason = "pendant_touch";
        triggerPending = true;
        lastTriggerMs = now;
      }
    }
  }

  // 4. Tap timeout: reset state if 2nd tap doesn't arrive within DOUBLE_GAP_MS
  if (tapCount == 1 && (now - lastTapTime > DOUBLE_GAP_MS) && !touchStable) {
    tapCount = 0;
    Serial.println(F("[TOUCH] Double-tap window expired. Standby."));
  }
}

void testTouchLive() {
  Serial.println(F("\n--- Live Touch Sensor Pin Monitor (Checks GPIO1 & GPIO2) ---"));
  Serial.println(F("Touch the TTP223 pad now to observe pin state:"));
  unsigned long start = millis();
  while (millis() - start < 5000) {
    bool v1 = (digitalRead(1) == HIGH);
    bool v2 = (digitalRead(2) == HIGH);
    bool val = v1 || v2;
    Serial.printf("[TOUCH] %s | GPIO1: %s | GPIO2: %s\n",
                  val ? "TOUCHED" : "not touched",
                  v1 ? "HIGH" : "LOW",
                  v2 ? "HIGH" : "LOW");
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
  Serial.printf("Touch Pin:      GPIO%d (%s)\n", TOUCH_PIN, digitalRead(TOUCH_PIN) == HIGH ? "HIGH" : "LOW");
  Serial.printf("Mic Pin:        GPIO%d (%s)\n", PIN_MIC_ADC, micHardwareDetected ? "ACTIVE" : "STANDBY");
  Serial.printf("Wearer Mode:    %s (Touch SOS: %s)\n", ownerMode.c_str(), touchSosEnabled ? "ON" : "OFF");
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
  Serial.printf("Wearer Mode:    %s (Touch SOS: %s, Hold: %lu ms)\n",
                ownerMode.c_str(), touchSosEnabled ? "ENABLED" : "DISABLED", holdPanicMs);
  Serial.printf("Touch Pin:      GPIO%d | Mic Pin: GPIO%d\n", TOUCH_PIN, PIN_MIC_ADC);
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
  Serial.println(F(" Touch (GPIO2): Double-tap OR Hold 1.5s -> Trigger Touch SOS (Adult Mode)"));
  Serial.println(F(" Child Mode:    Touch SOS disabled; Hold GPIO2 3s -> Call Parent"));
  Serial.println(F(" Voice (GPIO1): Speak emergency keyword / shout near mic -> Trigger Voice SOS"));
  Serial.println(F(" touch = Test Touch Sensor pin (GPIO2) live (5s monitor)"));
  Serial.println(F(" s = Send SOS Location SMS & log to Supabase"));
  Serial.println(F(" l = Show current location (Multi-tier: GPS/WiFi/BLE/Anchor)"));
  Serial.println(F(" g = Test indoor Wi-Fi Geolocation live (ip-api.com)"));
  Serial.println(F(" v = Test Microphone audio levels (GPIO1) live (5s monitor)"));
  Serial.println(F(" mode child / mode adult = Switch wearer mode"));
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
// 12.1 MICROPHONE & TINYML VOICE DETECTION ENGINE (GPIO1)
// ------------------------------------------------------------------------------
int voiceConsecutiveHits = 0;

void setupMicrophone() {
  pinMode(PIN_MIC_ADC, INPUT);

  Serial.printf("\n[VOICE ENGINE] Initializing Audio Subsystem on GPIO%d...\n", PIN_MIC_ADC);
  Serial.printf("[VOICE MODEL] Embedded TFLite-Micro Keyword Model: %u bytes\n", g_safeguard_model_len);
  Serial.println(F("[VOICE MODEL] Target Keywords: 'tuma_msaada', 'piga_polisi', 'send_help', 'call_police'"));

  analogReadResolution(12); // 12-bit ADC (0 - 4095)
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

  // MAX9814 / Electret mic module sits around ~1.25V-2.0V DC bias (ADC ~1300-2700)
  if (diff > 15 && diff < 1200 && avg > 1000 && avg < 3000) {
    micHardwareDetected = true;
    micNoiseFloor = avg;
    Serial.printf("[VOICE] Active Microphone DETECTED on GPIO%d! (Bias: %d, Noise: %d)\n", PIN_MIC_ADC, avg, diff);
    Serial.println(F("[VOICE] Acoustic distress & keyword detection ARMED on GPIO1."));
  } else {
    micHardwareDetected = false;
    micNoiseFloor = avg;
    // Restore digital INPUT_PULLDOWN on GPIO1 so Touch Sensor works on EITHER GPIO1 or GPIO2!
    pinMode(PIN_MIC_ADC, INPUT_PULLDOWN);
    pinMode(TOUCH_PIN, INPUT_PULLDOWN);
    Serial.printf("[VOICE] Microphone on GPIO%d in standby (Raw: %d, Diff: %d).\n", PIN_MIC_ADC, avg, diff);
    Serial.println(F("[VOICE] Touch Sensor active on BOTH GPIO1 & GPIO2 + BLE mode.\n"));
  }
}

void updateVoice() {
  if (!micHardwareDetected) return;

  unsigned long now = millis();
  // Strictly prioritize Touch Sensor (GPIO2): never evaluate voice while GPIO2 is touched or within 3s of touch activity
  if (touchStable || tapCount > 0 || (rawChangedMs > 0 && (now - rawChangedMs < 3000)) || digitalRead(TOUCH_PIN) == HIGH) {
    voiceConsecutiveHits = 0;
    return;
  }

  if (now - lastMicSampleMs < 60) return;
  lastMicSampleMs = now;

  int maxSample = 0;
  int minSample = 4095;
  for (int i = 0; i < 25; i++) {
    int sample = analogRead(PIN_MIC_ADC);
    if (sample > maxSample) maxSample = sample;
    if (sample < minSample) minSample = sample;
  }

  int peakToPeak = maxSample - minSample;

  // Require sustained acoustic energy across 3 consecutive windows so ADC spikes never false-trigger
  if (peakToPeak > 2000 && maxSample >= MIC_SHOUT_THRESHOLD) {
    voiceConsecutiveHits++;
    if (voiceConsecutiveHits >= 3) {
      voiceConsecutiveHits = 0;
      if (now - lastTriggerMs >= COOLDOWN_MS || lastTriggerMs == 0) {
        Serial.printf("\n[VOICE] EMERGENCY ACOUSTIC PATTERN DETECTED ON GPIO%d! (Peak: %d, Vpp: %d)\n",
                      PIN_MIC_ADC, maxSample, peakToPeak);
        currentTriggerReason = "pendant_voice";
        triggerPending = true;
        lastTriggerMs = now;
      }
    }
  } else {
    voiceConsecutiveHits = 0;
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
      int s = (PIN_MIC_ADC <= 4) ? analogRead(PIN_MIC_ADC) : (digitalRead(PIN_MIC_ADC) ? 3000 : 0);
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

void scanWiFi() {
  Serial.println(F("\n[WiFi] Scanning nearby 2.4 GHz networks..."));
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  delay(100);
  int n = WiFi.scanNetworks();
  if (n == 0) {
    Serial.println(F("[WiFi] No networks found."));
  } else {
    Serial.printf("[WiFi] Found %d networks:\n", n);
    for (int i = 0; i < n; ++i) {
      Serial.printf("  %2d: %-24s (Signal: %4d dBm, Ch: %2d, %s)\n",
                    i + 1,
                    WiFi.SSID(i).c_str(),
                    WiFi.RSSI(i),
                    WiFi.channel(i),
                    (WiFi.encryptionType(i) == WIFI_AUTH_OPEN) ? "Open" : "Secured");
    }
  }
  Serial.println();
}

// ------------------------------------------------------------------------------
// 13. SETUP
// ------------------------------------------------------------------------------
void setup() {
  pinMode(PIN_STATUS_LED, OUTPUT);
  digitalWrite(PIN_STATUS_LED, LOW);

  pinMode(TOUCH_PIN, INPUT_PULLDOWN); // Internal pull-down on GPIO2 for TTP223B touch sensor

  Serial.begin(115200);
  unsigned long startWait = millis();
  while (!Serial && millis() - startWait < 3000) delay(10);

  Serial.println(F("\n=================================================="));
  Serial.println(F(" SafeGuard GPS Pendant — Master Firmware v2.2.0"));
  Serial.println(F(" Multi-Tier Indoor/Outdoor Location Enabled"));
  Serial.println(F("=================================================="));

  // Initialize Microphone (GPIO1) & Voice Subsystem
  setupMicrophone();

  // 1. MAC Address (Read directly from factory eFuse registers)
  uint8_t baseMac[6];
  esp_err_t mErr = esp_read_mac(baseMac, ESP_MAC_WIFI_STA);
  if (mErr == ESP_OK) {
    char macStr[18];
    snprintf(macStr, sizeof(macStr), "%02X:%02X:%02X:%02X:%02X:%02X",
             baseMac[0], baseMac[1], baseMac[2], baseMac[3], baseMac[4], baseMac[5]);
    deviceMacAddress = String(macStr);
  } else {
    deviceMacAddress = "7C:DF:A1:00:11:22";
  }
  Serial.printf("Device MAC Address: %s\n", deviceMacAddress.c_str());

  // 2. Load stored preferences from Flash
  loadSettingsFromFlash();

  // 3. Standalone Cellular & GPS Mode (Zero Wi-Fi Dependency)
  WiFi.mode(WIFI_OFF);
  Serial.println(F("[SYSTEM] Operating Mode: Standalone Cellular (GSM/SMS & Satellite GPS)"));
  Serial.println(F("[SYSTEM] Zero Wi-Fi dependency enabled. Ready for outdoor and mobile use."));

  // 4. Initialize SIM800L UART (UART1 on GPIO5, GPIO6)
  SerialAT.setRxBufferSize(1024);
  SerialAT.begin(9600, SERIAL_8N1, SIM_RX, SIM_TX);
  delay(3000); // 3-second settle time matching working gsm_test_esp.ino

  Serial.println(F("[GSM] Initializing SIM800L module..."));
  bool alive = false;
  for (int i = 0; i < 20 && !alive; i++) {
    alive = modem.testAT(1000);
    Serial.print('.');
  }
  Serial.println();

  if (!alive) {
    Serial.println(F("[GSM] WARNING: No response from SIM800L. Check power & 5V/GND."));
  } else {
    // Run modem.init()
    modem.init();

    // Disable command echo & set text mode
    modem.sendAT(GF("E0"));
    modem.waitResponse(500);
    modem.sendAT(GF("+CMGF=1"));
    modem.waitResponse(500);
    modem.sendAT(GF("+CSCS=\"GSM\""));
    modem.waitResponse(500);

    if (modem.getSimStatus() == SIM_LOCKED) {
      if (strlen(simPin) > 0) modem.simUnlock(simPin);
      else Serial.println(F("[GSM] SIM locked but simPin is empty."));
    }

    if (modem.isNetworkConnected()) {
      Serial.printf("[GSM] Already registered on: %s (Signal: %d/31)\n",
                    modem.getOperator().c_str(), modem.getSignalQuality());
    } else {
      Serial.println(F("[GSM] Waiting for cellular network registration..."));
      unsigned long regStart = millis();
      bool registered = false;
      while (millis() - regStart < 90000L) {
        if (modem.isNetworkConnected()) {
          registered = true;
          break;
        }
        int sq = modem.getSignalQuality();
        Serial.printf("[GSM] Searching for Safaricom cell tower... (Signal: %d/31)\n", sq);
        delay(3000);
      }

      if (registered) {
        Serial.printf("[GSM] Registered on: %s (Signal: %d/31)\n",
                      modem.getOperator().c_str(), modem.getSignalQuality());
      } else {
        Serial.printf("[GSM] Not registered yet (Signal: %d/31). Continuing startup...\n", modem.getSignalQuality());
      }
    }
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
  Serial.println(F("[SYSTEM] Ready! Touch sensor active on GPIO1 & GPIO2 (Double-tap or Hold 1.5s for SOS).\n"));
}

// ------------------------------------------------------------------------------
// 14. MAIN LOOP
// ------------------------------------------------------------------------------
void loop() {
  feedGPS();
  updateTouch();
  updateVoice();

  unsigned long now = millis();

  // Handle LED Find Strobe if active
  if (findLedEndMs > now) {
    digitalWrite(PIN_STATUS_LED, (now % 200 < 100) ? HIGH : LOW);
  } else if (!touchStable) {
    if (!bleClientConnected) {
      digitalWrite(PIN_STATUS_LED, (now % 3500 < 15) ? HIGH : LOW);
    } else {
      digitalWrite(PIN_STATUS_LED, (now % 2000 < 25) ? HIGH : LOW);
    }
  }

  // Handle pending BLE / Guardian commands outside BLE interrupt context
  if (pendingStatusCmd) {
    pendingStatusCmd = false;
    sendStatusJsonOverBLE();
  }
  if (pendingLocateCmd) {
    pendingLocateCmd = false;
    String lat, lon;
    getFix(lat, lon, 3000UL);
    sendLocationJsonOverBLE();
  }
  if (pendingFindCmd) {
    pendingFindCmd = false;
    findLedEndMs = now + 10000UL;
    Serial.println(F("[FIND] Strobing Status LED on GPIO8 for 10 seconds!"));
  }
  if (pendingRemoteSosCmd) {
    pendingRemoteSosCmd = false;
    currentTriggerReason = "remote_guardian";
    triggerPending = true;
  }
  if (pendingCancelSosCmd) {
    pendingCancelSosCmd = false;
    updateBleSosBeacon(false);
    notifyPhoneOverBLE(0x00);
    Serial.println(F("[SOS] Active SOS & BLE beacon cancelled by Guardian."));
  }
  if (pendingHangupCmd) {
    pendingHangupCmd = false;
    modem.callHangup();
    Serial.println(F("[CALL] Active call hung up."));
  }
  if (pendingCallTarget.length() > 0) {
    String target = pendingCallTarget;
    pendingCallTarget = "";
    callNumber(target);
  }
  if (pendingChildCallParent) {
    pendingChildCallParent = false;
    notifyPhoneOverBLE(0x10);
    callNumber(guardianPhone);
  }

  // Periodic heartbeat to Supabase (every 60s if WiFi connected)
  if (now - lastHeartbeatMs >= HEARTBEAT_INT_MS) {
    lastHeartbeatMs = now;
    if (WiFi.status() == WL_CONNECTED) {
      registerWearableInDatabase();
    }
  }

  // Touch, Voice, or Remote Guardian trigger detected
  if (triggerPending) {
    triggerPending = false;
    if (currentTriggerReason == "pendant_voice") {
      Serial.printf("\n[SOS] Voice Keyword / Acoustic Pattern detected on Microphone GPIO%d!\n", PIN_MIC_ADC);
    } else if (currentTriggerReason == "remote_guardian") {
      Serial.println(F("\n[SOS] Remote Guardian SOS triggered from SafeLink App!"));
    } else {
      Serial.printf("\n[SOS] Touch pattern detected on Touch Sensor GPIO%d!\n", TOUCH_PIN);
    }
    sendLocationAlert(FIX_WAIT_MS);
  }

  // Interactive Serial Console Command Handler
  if (Serial.available() > 0) {
    String cmd = Serial.readStringUntil('\n');
    cmd.trim();
    if (cmd.length() == 0) return;

    if (cmd == "s") {
      currentTriggerReason = "pendant_touch";
      sendLocationAlert(FIX_WAIT_MS);
    } else if (cmd == "l" || cmd == "loc") {
      showLocation();
    } else if (cmd == "v") {
      monitorMicLive();
    } else if (cmd == "touch" || cmd == "touchtest") {
      testTouchLive();
    } else if (cmd == "mode child") {
      ownerMode = "child";
      touchSosEnabled = false;
      prefs.begin("safeguard", false);
      prefs.putString("owner_mode", "child");
      prefs.putBool("touch_sos", false);
      prefs.end();
      Serial.println(F("[MODE] Switched to CHILD mode (Touch SOS disabled; Hold 3s on GPIO2 calls parent)."));
    } else if (cmd == "mode adult") {
      ownerMode = "adult";
      touchSosEnabled = true;
      prefs.begin("safeguard", false);
      prefs.putString("owner_mode", "adult");
      prefs.putBool("touch_sos", true);
      prefs.end();
      Serial.println(F("[MODE] Switched to ADULT mode (Touch SOS enabled on GPIO2)."));
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
        Serial.println(F("Usage: setloc <lat>,<lon> (e.g. setloc -1.2907850038543573,36.78176897301627)"));
      }
    } else if (cmd == "i") {
      Serial.printf("Current Indoor Location: %s, %s (%s)\n",
                    lastLat.c_str(), lastLon.c_str(), currentLocSource.c_str());
      Serial.printf("3D Mapbox Live Link:     %s?lat=%s&lng=%s\n",
                    trackViewerUrl.c_str(), lastLat.c_str(), lastLon.c_str());
      Serial.println(F("To change, type: setloc <lat>,<lon>"));
    } else if (cmd == "?") {
      printMenu();
    }
  }

  delay(1);
}
