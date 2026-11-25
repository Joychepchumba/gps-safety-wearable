/*
 * ==============================================================================
 * SafeGuard GPS Safety Pendant — Master Firmware v2.4
 * ==============================================================================
 * MCU: ESP32-C3 Super Mini + INMP441 + SIM800L + NEO-6M GPS + TTP223B Touch
 *
 * Hardware Wiring (Verified on Breadboard):
 *   - SIM800L TX       -> GPIO5 (ESP32 RX)
 *   - SIM800L RX       -> GPIO6 (ESP32 TX)
 *   - NEO-6M TX        -> GPIO4 (ESP32 RX)
 *   - NEO-6M RX        -> GPIO3 (ESP32 TX)
 *   - TTP223B Touch    -> GPIO2 or GPIO1 (Active HIGH — both pins supported!)
 *   - INMP441 I2S Mic  -> SCK=GPIO7, WS=GPIO10, SD=GPIO0
 *   - Status LED       -> GPIO8
 * ==============================================================================
 */

#define TINY_GSM_MODEM_SIM800
#define TINY_GSM_RX_BUFFER 1024

// ---- Exact Lindana v7 Model Configuration ----
#define EIDSP_QUANTIZE_FILTERBANK 0
#define EI_CLASSIFIER_SLICES_PER_MODEL_WINDOW 2    // 0.5 s slices
#ifndef TEST_MODE
#define TEST_MODE 1                                // Emits [TEST_EVENT] millis=<ms> event=<name> over Serial
#endif

#include <Arduino.h>
#include <esp_mac.h>
#include <Preferences.h>
#include <TinyGsmClient.h>
#include <TinyGPSPlus.h>

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <BLEAdvertising.h>

#include <Lindana_inferencing.h>
#include <ESP_I2S.h>

// ------------------------------------------------------------------------------
// 1. PIN DEFINITIONS (Exact Breadboard + Lindana v7 Pins)
// ------------------------------------------------------------------------------
#define SIM_RX          5     // SIM800L TX -> ESP32 GPIO5
#define SIM_TX          6     // SIM800L RX -> ESP32 GPIO6
#define GPS_RX          4     // NEO-6M TX  -> ESP32 GPIO4
#define GPS_TX          3     // NEO-6M RX  -> ESP32 GPIO3
#define TOUCH_PIN       2     // TTP223B Touch SIG -> ESP32 GPIO2 (Active HIGH)
#define TOUCH_PIN_ALT   1     // Backup Touch pin -> ESP32 GPIO1 (Active HIGH)
#define PIN_STATUS_LED  8     // Onboard / External Status LED (GPIO8)
#define PIN_LED         8     // Alias for Lindana v7 alert_beep()
#define LED_ON_LEVEL    HIGH

// INMP441 I2S Pins (Exact Lindana v7 Pins)
#define PIN_I2S_SCK     7
#define PIN_I2S_WS      10
#define PIN_I2S_SD      0
#define USE_SPEAKER     0     // 0 = blink LED on GPIO8 (keeps GPIO2 free for Touch Sensor!)
#define PIN_SPK         2

// ---- Exact Lindana v7 Tuning ----
#define GAIN_SHIFT          15      // 14 = louder, 16 = quieter
#define TRIGGER_LABEL       "Callthepolice"
#define TRIGGER_THRESHOLD   0.70f
#define PRINT_MIN           0.10f   // print result lines when keyword prob is at least this
#define STATUS_EVERY_MS     10000
#define VOICE_COOLDOWN_MS   5000
#define LED_HOLD_MS         3000
#define BEEP_FREQ           2500
#define SLOT                I2S_STD_SLOT_RIGHT

// ------------------------------------------------------------------------------
// 2. BLE GATT UUIDS (Matches Flutter App Constants)
// ------------------------------------------------------------------------------
#define BLE_DEVICE_NAME   "SafeGuard"
#define SERVICE_UUID      "0000ffe0-0000-1000-8000-00805f9b34fb"
#define CHAR_ALERT_UUID   "0000ffe1-0000-1000-8000-00805f9b34fb" // Notify app when SOS triggered
#define CHAR_CONFIG_UUID  "0000ffe2-0000-1000-8000-00805f9b34fb" // App writes commands/config
#define CHAR_STATUS_UUID  "0000ffe3-0000-1000-8000-00805f9b34fb" // Live status readout for app

// ------------------------------------------------------------------------------
// 3. HARDWARE & GLOBAL OBJECTS
// ------------------------------------------------------------------------------
HardwareSerial SerialAT(1);    // SIM800L on UART1
HardwareSerial gpsSerial(0);   // NEO-6M on UART0 (USB CDC carries Serial console)
TinyGsm modem(SerialAT);
TinyGPSPlus gps;
Preferences prefs;
I2SClass i2s;

BLEServer *pServer = nullptr;
BLECharacteristic *pAlertChar = nullptr;
BLECharacteristic *pConfigChar = nullptr;
BLECharacteristic *pStatusChar = nullptr;
bool bleClientConnected = false;

// ------------------------------------------------------------------------------
// 4. DYNAMIC CONFIGURATION (Loaded from NVS Flash)
// ------------------------------------------------------------------------------
String linkedUserId    = "7426cae6-d358-4a02-9e2f-c7839a864e93";
String linkedUserEmail = "chepchumbajr@gmail.com";

String contact1        = "+254740034499";
String contact1Name    = "Primary Contact";
String contact2        = "";
String contact2Name    = "";
String contact3        = "";
String contact3Name    = "";

String ownerMode       = "adult";  // "adult" or "child"
bool touchSosEnabled   = true;     // True in adult mode, false in child mode
unsigned long holdPanicMs = 1500UL;
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

// Permanent 3D Mapbox Live Viewer (Alina Harbour Apartments)
String trackViewerUrl  = "https://joychepchumba.github.io/gps-safety-wearable/track.html";
const char simPin[]    = "";
String deviceMacAddress = "";

// ------------------------------------------------------------------------------
// 5. TIMING, THRESHOLDS & LOCATION STATE
// ------------------------------------------------------------------------------
const unsigned long FIX_WAIT_MS      = 3000UL;   // Brief outdoor GPS check before Alina Harbour indoor fallback
const unsigned long BOOT_GUARD_MS    = 2000UL;   // Ignore touch during first 2s after boot while TTP223 settles
const unsigned long DEBOUNCE_MS      = 50UL;     // Touch debounce
const unsigned long MIN_TAP_MS       = 60UL;     // Reject brief electrical noise
const unsigned long MAX_TAP_MS       = 900UL;    // Taps longer than 900ms are treated as holds
const unsigned long CHILD_CALL_HOLD_MS = 3000UL; // In Child Mode, holding 3s calls parent
const unsigned long DOUBLE_GAP_MS    = 1200UL;   // Max time between tap 1 and tap 2
const unsigned long COOLDOWN_MS      = 10000UL;  // Minimum time between triggered alerts

// Location state in RAM & Flash (Alina Harbour Apartments, Nairobi)
String lastLat = "-1.2907850038543573";   // Alina Harbour Apartments
String lastLon = "36.78176897301627";
String currentLocSource = "Alina Harbour Apartments Anchor";
unsigned long lastFixMs = 0;
unsigned long lastBleLocMs = 0;

// Touch Sensor State (GPIO2 & GPIO1)
bool benchFastMode = false;        // When true ('bench on'), triggers BLE + LED alarm immediately without 25s SMS/Call delay
bool voicePausedForTouchTest = false; // When true ('voice off'), pauses 559ms voice inference so loop() polls touch at 1000 Hz
bool gpio2StuckHighAtBoot = false; // If GPIO2 is pulled HIGH at boot (e.g. speaker/strapping), use GPIO1 only until GPIO2 drops LOW
bool touchStable = false;
bool touchRaw = false;
unsigned long rawChangedMs = 0;
unsigned long touchDownMs = 0;
unsigned long lastTapTime = 0;
int tapCount = 0;
unsigned long lastTriggerMs = 0;
bool triggerPending = false;
String currentTriggerReason = "pendant_touch";

static inline void logTestEvent(const char *evt) {
#if TEST_MODE
  Serial.printf("[TEST_EVENT] millis=%lu event=%s\n", millis(), evt);
#endif
}

// ---- Lindana v7 Continuous I2S State ----
static const size_t SLICE = EI_CLASSIFIER_SLICE_SIZE;
static size_t RING        = 16000; // Dynamically sized in setupVoiceI2S() based on free heap after BLE init
static int16_t *ring = nullptr;
static int16_t *snap = nullptr;
static volatile size_t head = 0;
static volatile uint32_t total_samples = 0;
static volatile int32_t mic_peak = 0;
static uint32_t consumed = 0;
static size_t rpos = 0;
static int warmup = EI_CLASSIFIER_SLICES_PER_MODEL_WINDOW;
static uint32_t led_off_at = 0;
bool i2sVoiceReady = false;

// Forward declarations
void updateTouch();
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

static void reset_audio_stream() {
  if (!i2sVoiceReady) return;
  consumed = total_samples;
  rpos = head;
  run_classifier_init();
  warmup = EI_CLASSIFIER_SLICES_PER_MODEL_WINDOW;
}

// Exact Lindana v7 alert_beep(): three short signals (beeps or LED blinks), then throw away audio recorded meanwhile
static void alert_beep() {
  for (int i = 0; i < 3; i++) {
#if USE_SPEAKER
    ledcWriteTone(PIN_SPK, BEEP_FREQ);
    delay(180);
    ledcWriteTone(PIN_SPK, 0);
    delay(120);
#else
    digitalWrite(PIN_LED, LED_ON_LEVEL);
    delay(180);
    digitalWrite(PIN_LED, !LED_ON_LEVEL);
    delay(120);
#endif
  }
  digitalWrite(PIN_LED, LED_ON_LEVEL);   // stay lit until the hold time ends
  reset_audio_stream();
}

static int get_audio_data(size_t offset, size_t length, float *out_ptr) {
  return numpy::int16_to_float(&snap[offset], out_ptr, length);
}

static void capture_task(void *arg) {
  static int32_t raw[256];
  size_t h = 0;
  while (true) {
    size_t n = i2s.readBytes((char *)raw, sizeof(raw)) / 4;
    for (size_t i = 0; i < n; i++) {
      int32_t a24 = raw[i] >> 8;
      if (a24 < 0) a24 = -a24;
      if (a24 > mic_peak) mic_peak = a24;
      int32_t s = raw[i] >> GAIN_SHIFT;
      if (s > 32767) s = 32767;
      if (s < -32768) s = -32768;
      ring[h] = (int16_t)s;
      if (++h == RING) h = 0;
      head = h;
    }
    total_samples += n;
    vTaskDelay(1);
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
  trackViewerUrl  = prefs.getString("track_url", trackViewerUrl);

  // Load saved indoor anchor coordinates (Alina Harbour Apartments)
  lastLat = prefs.getString("last_lat", "-1.2907850038543573");
  lastLon = prefs.getString("last_lon", "36.78176897301627");
  if (lastLat == "-1.309250" || lastLat == "-1.292100" || lastLat == "-1.307300" || lastLat.length() == 0) {
    lastLat = "-1.2907850038543573";
    lastLon = "36.78176897301627";
    currentLocSource = "Alina Harbour Apartments Anchor";
    prefs.putString("last_lat", lastLat);
    prefs.putString("last_lon", lastLon);
  }

  prefs.putString("user_id", linkedUserId);
  prefs.putString("user_email", linkedUserEmail);
  prefs.putString("c1", contact1);
  prefs.putString("c1_name", contact1Name);
  prefs.putString("last_lat", lastLat);
  prefs.putString("last_lon", lastLon);
  prefs.end();

  Serial.println(F("[NVS] Configuration loaded from Flash memory:"));
  Serial.printf("  Linked User:  %s (%s)\n", linkedUserEmail.c_str(), linkedUserId.c_str());
  Serial.printf("  Wearer Mode:  %s (Touch SOS: %s, Hold: %lu ms)\n",
                ownerMode.c_str(), touchSosEnabled ? "ENABLED" : "DISABLED (Child Lock)", holdPanicMs);
  Serial.printf("  Contact 1:    %s (%s)\n", contact1.c_str(), contact1Name.c_str());
  Serial.printf("  Anchor:%s, %s (Alina Harbour Apartments)\n", lastLat.c_str(), lastLon.c_str());
  Serial.printf("  3D Mapbox:    %s?lat=%s&lng=%s\n", trackViewerUrl.c_str(), lastLat.c_str(), lastLon.c_str());
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
  currentLocSource = " Calibration Anchor";
  prefs.begin("safeguard", false);
  prefs.putString("last_lat", lastLat);
  prefs.putString("last_lon", lastLon);
  prefs.end();
  Serial.printf("[ ANCHOR] Saved coordinates to Flash: %s, %s\n",
                lastLat.c_str(), lastLon.c_str());
}

// ------------------------------------------------------------------------------
// 7. MULTI-TIER LOCATION ENGINE (INDOOR ALINA HARBOUR & OUTDOOR NEO-6M GPS)
// ------------------------------------------------------------------------------
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

bool getFix(String &lat, String &lon, unsigned long timeoutMs) {
  Serial.println(F("\n[LOCATION ENGINE] Resolving current location..."));

  // 1. TIER 1: Check NEO-6M satellite fix (Brief check up to 2.5s)
  unsigned long start = millis();
  unsigned long checkTime = min(timeoutMs, 2500UL);
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
    currentLocSource = "Phone BLE Assisted GPS ";
    Serial.printf("[LOCATION] Using Phone Assisted GPS over BLE: %s, %s\n", lat.c_str(), lon.c_str());
    return true;
  }

  // 3. TIER 3: Fallback to Saved Indoor Anchor in Flash (Alina Harbour Apartments)
  if (lastLat.length() > 0 && lastLon.length() > 0) {
    lat = lastLat;
    lon = lastLon;
    currentLocSource = "Alina Harbour Apartments Anchor (Flash)";
    Serial.printf("[LOCATION] Using Saved Calibration Anchor: %s, %s\n", lat.c_str(), lon.c_str());
    Serial.printf("[LOCATION] 3D Mapbox Live Link: %s?lat=%s&lng=%s\n", trackViewerUrl.c_str(), lat.c_str(), lon.c_str());
    return true;
  }

  lat = "-1.2907850038543573";
  lon = "36.78176897301627";
  currentLocSource = "Alina Harbour Apartments Anchor";
  return true;
}

void showLocation() {
  Serial.println(F("\nResolving current location ..."));
  String lat, lon;
  getFix(lat, lon, 2000UL);
  Serial.printf("Current Location: Lat=%s, Lon=%s (Alina Harbour Apartments)\n", lat.c_str(), lon.c_str());
  Serial.printf("Source:           %s\n", currentLocSource.c_str());
  Serial.printf("GPS Satellites:   %d\n", gps.satellites.isValid() ? gps.satellites.value() : 0);
  Serial.printf("3D Mapbox Link:   %s?lat=%s&lng=%s\n\n", trackViewerUrl.c_str(), lat.c_str(), lon.c_str());
  blinkLed(3, 70, 70);
  reset_audio_stream();
}

// ------------------------------------------------------------------------------
// 8. SMS & CELLULAR GSM DISPATCH (SIM800L)
// ------------------------------------------------------------------------------
void prepareModemFor2GBurst() {
  digitalWrite(PIN_STATUS_LED, LOW);
  delay(200);

  while (SerialAT.available()) SerialAT.read();

  modem.sendAT(GF("E0"));
  modem.waitResponse(500);
  modem.sendAT(GF("+CMGF=1"));
  modem.waitResponse(500);
  modem.sendAT(GF("+CSCS=\"GSM\""));
  modem.waitResponse(500);

  if (!modem.isNetworkConnected()) {
    Serial.println(F("[GSM] Verifying cellular network registration..."));
    if (modem.waitForNetwork(20000L, true)) {
      Serial.printf("[GSM] Registered on: %s (Signal: %d/31)\n",
                    modem.getOperator().c_str(), modem.getSignalQuality());
    }
  }
  while (SerialAT.available()) SerialAT.read();
}

bool sendSMS(const String &number, const String &text) {
  if (number.length() < 7) return false;

  if (number.indexOf("709570000") != -1 || number.indexOf("999") != -1 || number.indexOf("112") != -1) {
    Serial.printf("[SAFETY GUARD] Bypassed cellular SMS to official helpline (%s) during breadboard testing.\n", number.c_str());
    return true;
  }

  Serial.printf("[SMS] Sending to %s (%u chars)...\n", number.c_str(), text.length());

  prepareModemFor2GBurst();

  bool ok = modem.sendSMS(number, text);
  if (!ok) {
    Serial.println(F("[SMS] First attempt did not confirm; stabilizing power rail & retrying..."));
    delay(3000);
    prepareModemFor2GBurst();
    ok = modem.sendSMS(number, text);
  }
  Serial.println(ok ? F("[SMS] Delivery SUCCESSFUL!") : F("[SMS] Send FAILED!"));

  delay(2000);
  while (SerialAT.available()) SerialAT.read();
  reset_audio_stream();
  return ok;
}

void notifyPhoneOverBLE(uint8_t alertCode = 0x01) {
  sosBeaconActive = (alertCode != 0x00);
  if (pAlertChar != nullptr) {
    pAlertChar->setValue(&alertCode, 1);
    pAlertChar->notify();
    logTestEvent("BLE_ALERT_GATT_NOTIFY");
    Serial.printf("[ESP32 -> APP BLE] Alert notification (0x%02X) sent to connected phone!\n", alertCode);
  }
  sendStatusJsonOverBLE();
  updateBleSosBeacon(alertCode != 0x00);
  if (alertCode != 0x00) {
    logTestEvent("BLE_SL_BEACON_ACTIVE");
  }
}

// Main emergency dispatch routine: Triggers Alarm, notifies BLE, resolves Alina Harbour / GPS, sends SMS, & places Voice Call
void sendLocationAlert(unsigned long waitMs = FIX_WAIT_MS) {
  alert_beep(); // Audible + visual alarm (exact Lindana v7 3x blink/beep)
  Serial.println(F("\n=================================================="));
  Serial.println(F(">>> EMERGENCY SOS TRIGGERED FROM PENDANT <<<"));
  Serial.println(F("=================================================="));

  uint8_t alertCode = 0x01;
  if (currentTriggerReason == "pendant_voice") alertCode = 0x02;
  else if (currentTriggerReason == "remote_guardian") alertCode = 0x03;

  // 1. Notify paired smartphone over BLE immediately + start 'SL' BLE SOS Beacon
  notifyPhoneOverBLE(alertCode);

  // 2. Resolve Multi-Tier Location (GPS -> Phone BLE -> Alina Harbour Apartments Anchor)
  String lat, lon;
  getFix(lat, lon, waitMs);
  sendLocationJsonOverBLE();

  String smsLat = String(lat.toDouble(), 6);
  String smsLon = String(lon.toDouble(), 6);
  String mapboxLiveLink = trackViewerUrl + "?lat=" + smsLat + "&lng=" + smsLon;

  Serial.printf("[SOS LOCATION] Coordinates: %s, %s (Alina Harbour Apartments)\n", lat.c_str(), lon.c_str());
  Serial.printf("[SOS LOCATION] 3D Mapbox:   %s\n", mapboxLiveLink.c_str());

  String smsMsg = "ALERT. Joy 3D Live Map: " + mapboxLiveLink;

  // 3. Dispatch SMS to Emergency Contacts
  if (contact1.length() >= 7) {
    sendSMS(contact1, smsMsg);
  }
  if (contact2.length() >= 7 && contact2 != contact1) {
    delay(2000);
    sendSMS(contact2, smsMsg);
  }
  if (contact3.length() >= 7 && contact3 != contact1 && contact3 != contact2) {
    delay(2000);
    sendSMS(contact3, smsMsg);
  }

  // 4. Place Emergency Voice Call to Primary Contact
  if (contact1.length() >= 7) {
    Serial.println(F("[SOS CALL] Placing emergency voice call to Primary Contact..."));
    callNumber(contact1);
  }

  led_off_at = millis() + LED_HOLD_MS;
  reset_audio_stream();
  Serial.println(F(">>> EMERGENCY ALERT (BLE + ALARM + SMS + CALL) COMPLETED <<<\n"));
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

  reset_audio_stream();
}

// ------------------------------------------------------------------------------
// 9. BLE GATT SERVER CALLBACKS, PARENTAL COMMANDS & SOS BEACON
// ------------------------------------------------------------------------------
void sendStatusJsonOverBLE() {
  if (pStatusChar == nullptr) return;
  char buf[160];
  snprintf(buf, sizeof(buf),
           "{\"t\":\"status\",\"mode\":\"%s\",\"touch\":%d,\"hold\":%lu,\"fw\":\"2.4.0\",\"sos\":%d}",
           ownerMode.c_str(), touchSosEnabled ? 1 : 0, holdPanicMs, sosBeaconActive ? 1 : 0);
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

  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->stop();

  if (enable) {
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

    BLEAdvertisementData advData;
    advData.setFlags(0x06);
    advData.setManufacturerData(mfgStr);
    advData.setCompleteServices(BLEUUID(SERVICE_UUID));
    pAdvertising->setAdvertisementData(advData);

    BLEAdvertisementData scanRespData;
    scanRespData.setName(BLE_DEVICE_NAME);
    pAdvertising->setScanResponseData(scanRespData);
  } else {
    BLEAdvertisementData advData;
    advData.setFlags(0x06);
    advData.setName(BLE_DEVICE_NAME);
    advData.setCompleteServices(BLEUUID(SERVICE_UUID));
    pAdvertising->setAdvertisementData(advData);

    BLEAdvertisementData scanRespData;
    scanRespData.setName(BLE_DEVICE_NAME);
    pAdvertising->setScanResponseData(scanRespData);
  }

  pAdvertising->start();
  if (enable) {
    Serial.println(F("[BLE BEACON] Broadcasting 15-byte 'SL' SOS Distress Beacon to nearby responders!"));
  }
}

class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *pServer) override {
    bleClientConnected = true;
    Serial.println(F("\n======================================================="));
    Serial.println(F(" [BLE CONNECTED] SafeLink Phone App paired to ESP32!"));
    Serial.println(F("=======================================================\n"));
    pendingStatusCmd = true;
  }

  void onDisconnect(BLEServer *pServer) override {
    bleClientConnected = false;
    Serial.println(F("[BLE] Phone App disconnected. Resuming advertising..."));
    pServer->startAdvertising();
  }
};

class ConfigCharCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) override {
    String value = pChar->getValue().c_str();
    value.trim();
    if (value.length() == 0) return;

    Serial.println(F("\n*******************************************************"));
    Serial.printf(" [APP -> ESP32 BLE] Command received from Phone App: %s\n", value.c_str());
    Serial.println(F("*******************************************************"));

    if (value.startsWith("LOC:")) {
      int comma = value.indexOf(',', 4);
      if (comma != -1) {
        lastLat = value.substring(4, comma);
        lastLon = value.substring(comma + 1);
        lastLat.trim();
        lastLon.trim();
        lastBleLocMs = millis();
        lastFixMs = millis();
        currentLocSource = "Phone BLE Assisted GPS";
        prefs.begin("safeguard", false);
        prefs.putString("last_lat", lastLat);
        prefs.putString("last_lon", lastLon);
        prefs.end();
        Serial.printf("[BLE LOC] Live location synced from phone GPS: %s, %s\n",
                      lastLat.c_str(), lastLon.c_str());
      }
      return;
    }

    if (value.startsWith("MODE:")) {
      String m = value.substring(5);
      m.toLowerCase();
      ownerMode = (m == "child") ? "child" : "adult";
      touchSosEnabled = (ownerMode != "child");
      prefs.begin("safeguard", false);
      prefs.putString("owner_mode", ownerMode);
      prefs.putBool("touch_sos", touchSosEnabled);
      prefs.end();
      Serial.printf("[MODE] Switched to %s mode (Touch SOS: %s)\n",
                    ownerMode.c_str(), touchSosEnabled ? "ENABLED" : "DISABLED - Child Safety");
      pendingStatusCmd = true;
      return;
    }

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

    if (value.startsWith("CMD:")) {
      String cmd = value.substring(4);
      if (cmd == "LOCATE") pendingLocateCmd = true;
      else if (cmd == "STATUS") pendingStatusCmd = true;
      else if (cmd == "SOS") pendingRemoteSosCmd = true;
      else if (cmd == "CANCEL") pendingCancelSosCmd = true;
      else if (cmd == "FIND" || cmd == "BLINK" || cmd == "PING" || cmd == "TEST") pendingFindCmd = true;
      else if (cmd == "HANGUP") pendingHangupCmd = true;
      else if (cmd.startsWith("CALL")) {
        int colon = cmd.indexOf(':');
        pendingCallTarget = (colon != -1) ? cmd.substring(colon + 1) : guardianPhone;
      }
      return;
    }

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

  pAlertChar = pService->createCharacteristic(
      CHAR_ALERT_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  pAlertChar->addDescriptor(new BLE2902());
  uint8_t zero = 0x00;
  pAlertChar->setValue(&zero, 1);

  pConfigChar = pService->createCharacteristic(
      CHAR_CONFIG_UUID,
      BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR | BLECharacteristic::PROPERTY_READ);
  pConfigChar->setCallbacks(new ConfigCharCallbacks());
  pConfigChar->setValue(contact1.c_str());

  pStatusChar = pService->createCharacteristic(
      CHAR_STATUS_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  pStatusChar->addDescriptor(new BLE2902());
  String initialStatus = "{\"t\":\"status\",\"mode\":\"" + ownerMode + "\",\"fw\":\"2.4.0\"}";
  pStatusChar->setValue(initialStatus.c_str());

  pService->start();

  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinInterval(0x20);
  pAdvertising->setMaxInterval(0x40);
  pAdvertising->start();

  Serial.printf("[BLE] GATT Server active ('SafeGuard'). Free heap after BLE: %u bytes\n", ESP.getFreeHeap());
}

// ------------------------------------------------------------------------------
// 10. TOUCH SENSOR ENGINE (GPIO2 & GPIO1 — Double-Tap OR 1.5s Hold)
// ------------------------------------------------------------------------------
void updateTouch() {
  unsigned long now = millis();
  if (now < BOOT_GUARD_MS) {
    return;
  }

  static int gpio2IdleState = LOW;
  static bool firstCheckAfterBootGuard = true;
  if (firstCheckAfterBootGuard) {
    firstCheckAfterBootGuard = false;
    gpio2IdleState = digitalRead(TOUCH_PIN);
    Serial.printf("[TOUCH INIT] Calibrated GPIO2 idle baseline = %s\n",
                  gpio2IdleState == HIGH ? "HIGH" : "LOW");
  }

  bool r2 = (digitalRead(TOUCH_PIN) != gpio2IdleState);
  bool r1 = (digitalRead(TOUCH_PIN_ALT) == HIGH);
  bool raw = r2 || r1;
  int triggeredPin = r2 ? TOUCH_PIN : TOUCH_PIN_ALT;

  // If GPIO2 changes steady-state baseline for > 4.5s (e.g. TTP223 auto-recalibration), adapt baseline
  static unsigned long r2ContinuousStartMs = 0;
  if (r2) {
    if (r2ContinuousStartMs == 0) r2ContinuousStartMs = now;
    else if (now - r2ContinuousStartMs > 4500UL) {
      gpio2IdleState = digitalRead(TOUCH_PIN);
      r2ContinuousStartMs = 0;
      touchStable = false;
      touchRaw = false;
      touchDownMs = 0;
      return;
    }
  } else {
    r2ContinuousStartMs = 0;
  }

  if (raw != touchRaw) {
    touchRaw = raw;
    rawChangedMs = now;
  }

  if (now - rawChangedMs >= DEBOUNCE_MS && touchStable != touchRaw) {
    touchStable = touchRaw;

    if (touchStable) {
      touchDownMs = now;
      digitalWrite(PIN_STATUS_LED, HIGH);
      Serial.printf("[TOUCH GPIO%d] Touch sensor pressed (HIGH).\n", triggeredPin);
    } else {
      digitalWrite(PIN_STATUS_LED, LOW);
      unsigned long pressDuration = (touchDownMs > 0) ? (now - touchDownMs) : 0;
      touchDownMs = 0;
      unsigned long effectiveCooldown = benchFastMode ? 1500UL : COOLDOWN_MS;

      if (pressDuration == 0) {
        // Already handled by continuous hold trigger while pressed
      } else if (pressDuration < MIN_TAP_MS) {
        Serial.printf("[TOUCH] Brief spike (%lu ms < %lu ms) rejected — no SOS.\n", pressDuration, MIN_TAP_MS);
      } else if (pressDuration <= MAX_TAP_MS) {
        if (ownerMode == "child" || !touchSosEnabled) {
          Serial.printf("[TOUCH] Child Mode active — accidental tap (%lu ms) suppressed.\n", pressDuration);
          tapCount = 0;
        } else {
          if (tapCount == 0) {
            tapCount = 1;
            lastTapTime = now;
            Serial.printf("[TOUCH] Valid Tap 1 (%lu ms) detected. Tap once more within 1.2s for SOS.\n", pressDuration);
          } else if (tapCount == 1 && (now - lastTapTime <= DOUBLE_GAP_MS)) {
            tapCount = 0;
            if (now - lastTriggerMs >= effectiveCooldown || lastTriggerMs == 0) {
              Serial.println(F("\n========================================================"));
              Serial.println(F(" [TOUCH] >>> DOUBLE-TAP SOS CONFIRMED! <<<"));
              Serial.println(F("========================================================\n"));
              currentTriggerReason = "pendant_touch";
              triggerPending = true;
              lastTriggerMs = now;
            }
          }
        }
      } else {
        Serial.printf("[TOUCH] Released after %lu ms (shorter than %lu ms hold threshold) — no SOS.\n", pressDuration, holdPanicMs);
      }
    }
  }

  // Continuous Hold Detection (1.5s Hold in Adult Mode -> SOS; 3.0s Hold in Child Mode -> Call Parent)
  if (touchStable && touchDownMs > 0) {
    unsigned long heldMs = now - touchDownMs;
    unsigned long effectiveCooldown = benchFastMode ? 1500UL : COOLDOWN_MS;

    if (ownerMode == "child") {
      if (heldMs >= CHILD_CALL_HOLD_MS) {
        touchDownMs = 0;
        tapCount = 0;
        Serial.println(F("\n========================================================"));
        Serial.println(F(" [TOUCH] >>> CHILD CALL-PARENT (3s HOLD) CONFIRMED! <<<"));
        Serial.println(F("========================================================\n"));
        pendingChildCallParent = true;
      }
    } else if (touchSosEnabled && heldMs >= holdPanicMs) {
      touchDownMs = 0;
      tapCount = 0;
      if (now - lastTriggerMs >= effectiveCooldown || lastTriggerMs == 0) {
        Serial.println(F("\n========================================================"));
        Serial.printf(" [TOUCH] >>> %.1fs HOLD-TO-PANIC SOS CONFIRMED! <<<\n", holdPanicMs / 1000.0);
        Serial.println(F("========================================================\n"));
        currentTriggerReason = "pendant_touch";
        triggerPending = true;
        lastTriggerMs = now;
      }
    }
  }

  if (tapCount == 1 && (now - lastTapTime > DOUBLE_GAP_MS) && !touchStable) {
    tapCount = 0;
    Serial.println(F("[TOUCH] Single tap expired (>1.2s without 2nd tap) — Accidental touch rejected. Standby."));
  }
}

void testTouchLive() {
  Serial.println(F("\n--- Live Touch Sensor Pin Monitor (Checks GPIO1 & GPIO2 for 5s) ---"));
  unsigned long start = millis();
  while (millis() - start < 5000) {
    bool v1 = (digitalRead(TOUCH_PIN_ALT) == HIGH);
    bool v2 = (digitalRead(TOUCH_PIN) == HIGH);
    bool val = v1 || v2;
    Serial.printf("[TOUCH] %s | GPIO1: %s | GPIO2: %s\n",
                  val ? "TOUCHED" : "not touched",
                  v1 ? "HIGH" : "LOW",
                  v2 ? "HIGH" : "LOW");
    digitalWrite(PIN_STATUS_LED, val ? HIGH : LOW);
    delay(200);
  }
  Serial.println(F("--- End of Touch Monitor ---\n"));
  reset_audio_stream();
}

// ------------------------------------------------------------------------------
// 11. LINDANA V7 VOICE DETECTION ENGINE (INMP441 I2S)
// ------------------------------------------------------------------------------
void setupVoiceI2S() {
  Serial.println(F("\n[VOICE] Initializing Lindana model test v7 (INMP441 I2S)..."));
  Serial.printf("  Slice: %d samples (%d ms), slices per window: %d\n",
                (int)SLICE, (int)(1000UL * SLICE / EI_CLASSIFIER_FREQUENCY),
                EI_CLASSIFIER_SLICES_PER_MODEL_WINDOW);

  snap = (int16_t *)malloc(SLICE * sizeof(int16_t));
  // Try 16000 samples (32 KB) first; fall back to 8000 samples (16 KB) if BLE left tight heap
  RING = 16000;
  ring = (int16_t *)malloc(RING * sizeof(int16_t));
  if (!ring) {
    RING = SLICE;
    ring = (int16_t *)malloc(RING * sizeof(int16_t));
  }

  if (!ring || !snap) {
    Serial.println(F("[VOICE] WARNING: Could not allocate I2S buffers. Touch/SMS/Call/BLE still active."));
    i2sVoiceReady = false;
    return;
  }
  memset(ring, 0, RING * sizeof(int16_t));

  i2s.setPins(PIN_I2S_SCK, PIN_I2S_WS, -1, PIN_I2S_SD);
  if (!i2s.begin(I2S_MODE_STD, EI_CLASSIFIER_FREQUENCY,
                 I2S_DATA_BIT_WIDTH_32BIT, I2S_SLOT_MODE_MONO, SLOT)) {
    Serial.println(F("[VOICE] WARNING: I2S failed to start. Check INMP441 wiring (SCK=7, WS=10, SD=0)."));
    i2sVoiceReady = false;
    return;
  }

  run_classifier_init();
  // Priority 1 (same as loopTask) so capture_task and loop() share the single-core CPU fairly
  xTaskCreate(capture_task, "capture", 4096, nullptr, 1, nullptr);
  i2sVoiceReady = true;
  Serial.printf("[VOICE] Active! Ring=%u samples, Free heap=%u bytes. Say \"call the police\" (~30 cm).\n",
                (unsigned int)RING, ESP.getFreeHeap());
}

void updateVoiceI2S() {
  if (!i2sVoiceReady || !ring || !snap || voicePausedForTouchTest || touchStable || tapCount > 0) return;

  static uint32_t last_voice_trigger = 0;
  static uint32_t last_status = millis();
  static float best = 0;
  static uint32_t skipped = 0;

  uint32_t avail = total_samples - consumed;
  if (avail < SLICE) return;

  while (avail >= 2 * SLICE) {                 // drop oldest slice if behind
    rpos = (rpos + SLICE) % RING;
    consumed += SLICE;
    avail -= SLICE;
    skipped++;
  }

  size_t first = RING - rpos;                 // copy one slice out of the ring buffer
  if (first >= SLICE) {
    memcpy(snap, ring + rpos, SLICE * sizeof(int16_t));
  } else {
    memcpy(snap, ring + rpos, first * sizeof(int16_t));
    memcpy(snap + first, ring, (SLICE - first) * sizeof(int16_t));
  }
  int peak = 0;
  for (size_t i = 0; i < SLICE; i++) {
    int a = abs(snap[i]);
    if (a > peak) peak = a;
  }
  rpos = (rpos + SLICE) % RING;
  consumed += SLICE;

  signal_t signal;
  signal.total_length = SLICE;
  signal.get_data = &get_audio_data;

  ei_impulse_result_t result = {0};
  uint32_t t = millis();
  EI_IMPULSE_ERROR err = run_classifier_continuous(&signal, &result, false);
  uint32_t took = millis() - t;
  if (err != EI_IMPULSE_OK) {
    Serial.printf("ERR: classifier returned %d\n", err);
    return;
  }
  if (warmup > 0) {
    warmup--;
    return;
  }

  float p = 0;
  for (size_t i = 0; i < EI_CLASSIFIER_LABEL_COUNT; i++) {
    if (strcmp(result.classification[i].label, TRIGGER_LABEL) == 0) {
      p = result.classification[i].value;
    }
  }
  if (p > best) best = p;

  if (p >= PRINT_MIN || (benchFastMode && peak > 600)) {
    for (size_t i = 0; i < EI_CLASSIFIER_LABEL_COUNT; i++) {
      Serial.printf("%s: %.2f  ", result.classification[i].label, result.classification[i].value);
    }
    Serial.printf("| peak %d | %lu ms\n", peak, (unsigned long)took);
  }

  unsigned long effectiveVoiceCooldown = benchFastMode ? 1500UL : VOICE_COOLDOWN_MS;
  if (p >= TRIGGER_THRESHOLD && millis() - last_voice_trigger > effectiveVoiceCooldown) {
    last_voice_trigger = millis();
    Serial.println(F(">>> KEYWORD DETECTED: CALL THE POLICE <<<"));
    currentTriggerReason = "pendant_voice";
    triggerPending = true;
    lastTriggerMs = millis();
    return;
  }

  if (millis() - last_status >= STATUS_EVERY_MS) {
    Serial.printf("[status] slice peak %d | best Callthepolice %.2f | skipped slices %lu | %lu ms/slice (limit %d)%s\n",
                  peak, best, (unsigned long)skipped, (unsigned long)took,
                  (int)(1000UL * SLICE / EI_CLASSIFIER_FREQUENCY),
                  took > 1000UL * SLICE / EI_CLASSIFIER_FREQUENCY ? "  TOO SLOW" : "");
    mic_peak = 0;
    best = 0;
    last_status = millis();
  }
}

// ------------------------------------------------------------------------------
// 12. DIAGNOSTICS & SERIAL CONSOLE COMMANDS
// ------------------------------------------------------------------------------
void diagnose() {
  Serial.println(F("\n================ DIAGNOSTICS ================"));
  Serial.print(F("Modem Info:     ")); Serial.println(modem.getModemInfo());
  Serial.print(F("SIM Status:     ")); Serial.println(modem.getSimStatus()); // 1 = ready
  Serial.print(F("GSM Registered: ")); Serial.println(modem.isNetworkConnected() ? F("YES") : F("NO"));
  Serial.print(F("Operator:       ")); Serial.println(modem.getOperator());
  Serial.print(F("Signal (0-31):  ")); Serial.println(modem.getSignalQuality());
  Serial.printf("Touch Pins:     GPIO2=%s | GPIO1=%s\n",
                digitalRead(TOUCH_PIN) == HIGH ? "HIGH" : "LOW",
                digitalRead(TOUCH_PIN_ALT) == HIGH ? "HIGH" : "LOW");
  Serial.printf("INMP441 I2S:    %s (SCK=%d, WS=%d, SD=%d)\n",
                i2sVoiceReady ? "ACTIVE (Lindana v7)" : "STANDBY", PIN_I2S_SCK, PIN_I2S_WS, PIN_I2S_SD);
  Serial.printf("Wearer Mode:    %s (Touch SOS: %s)\n", ownerMode.c_str(), touchSosEnabled ? "ON" : "OFF");
  Serial.print(F("GPS Characters: ")); Serial.println(gps.charsProcessed());
  Serial.print(F("GPS Satellites: ")); Serial.println(gps.satellites.isValid() ? gps.satellites.value() : 0);
  Serial.print(F("BLE Connected:  ")); Serial.println(bleClientConnected ? F("YES (Phone paired)") : F("Advertising as 'SafeGuard'"));
  Serial.printf("Current Loc:    %s, %s [%s]\n", lastLat.c_str(), lastLon.c_str(), currentLocSource.c_str());
  Serial.printf("3D Mapbox Link: %s?lat=%s&lng=%s\n", trackViewerUrl.c_str(), lastLat.c_str(), lastLon.c_str());
  Serial.printf("Free Heap RAM:  %u bytes\n", ESP.getFreeHeap());
  Serial.println(F("=============================================\n"));
  reset_audio_stream();
}

void showWearableStatus() {
  Serial.println(F("\n================ WEARABLE STATUS ================"));
  Serial.printf("Device Name:    %s\n", BLE_DEVICE_NAME);
  Serial.printf("MAC Address:    %s\n", deviceMacAddress.c_str());
  Serial.printf("Linked User:    %s (%s)\n", linkedUserEmail.c_str(), linkedUserId.c_str());
  Serial.printf("Wearer Mode:    %s (Touch SOS: %s, Hold: %lu ms)\n",
                ownerMode.c_str(), touchSosEnabled ? "ENABLED" : "DISABLED", holdPanicMs);
  Serial.printf("Contacts:       [1] %s (%s)\n", contact1.c_str(), contact1Name.c_str());
  if (contact2.length() > 0) Serial.printf("                [2] %s (%s)\n", contact2.c_str(), contact2Name.c_str());
  if (contact3.length() > 0) Serial.printf("                [3] %s (%s)\n", contact3.c_str(), contact3Name.c_str());
  Serial.printf("GSM:            %s (Signal: %d/31)\n", modem.isNetworkConnected() ? "ONLINE" : "SEARCHING", modem.getSignalQuality());
  Serial.printf("BLE:            %s\n", bleClientConnected ? "CONNECTED TO PHONE" : "READY TO PAIR");
  Serial.printf("Location:       Lat: %s, Lon: %s\n", lastLat.c_str(), lastLon.c_str());
  Serial.printf("Location Mode:  %s\n", currentLocSource.c_str());
  Serial.printf("3D Mapbox Link: %s?lat=%s&lng=%s\n", trackViewerUrl.c_str(), lastLat.c_str(), lastLon.c_str());
  Serial.println(F("=================================================\n"));
  reset_audio_stream();
}

void printMenu() {
  Serial.println(F("\n--- SafeGuard Console Commands ---"));
  Serial.println(F(" Touch (GPIO2/1): Double-tap OR Hold 1.5s -> Trigger Touch SOS (BLE + Alarm + SMS + Call)"));
  Serial.println(F(" Voice (INMP441): Say \"call the police\" -> Trigger Voice SOS (BLE + Alarm + SMS + Call)"));
  Serial.println(F(" touch = Test Touch Sensor pins (GPIO1 & GPIO2) live (5s monitor)"));
  Serial.println(F(" s = Send SOS Location SMS + Voice Call + BLE Alert"));
  Serial.println(F(" l = Show current location (GPS)"));
  Serial.println(F(" t = Send test SMS (Alina Harbour 3D Live Map) to Contact 1"));
  Serial.println(F(" c = Place voice call to Contact 1"));
  Serial.println(F(" h = Hang up active voice call"));
  Serial.println(F(" b = Test BLE SOS Alert + Beacon to SafeLink Phone App"));
  Serial.println(F(" a = Test Alarm beep / LED blink (alert_beep)"));
  Serial.println(F(" mode child / mode adult = Switch wearer mode"));
  Serial.println(F(" w = Show Wearable info & linked user status"));
  Serial.println(F(" m = Display current 3D Mapbox live tracking link"));
  Serial.println(F(" d = Run full hardware diagnostics"));
  Serial.println(F(" i = Show or calibrate location (e.g. setloc -1.290785,36.781769)"));
  Serial.println(F(" ? = Show this command menu\n"));
}

// ------------------------------------------------------------------------------
// 13. SETUP
// ------------------------------------------------------------------------------
void setup() {
  pinMode(PIN_STATUS_LED, OUTPUT);
  digitalWrite(PIN_STATUS_LED, LOW);

  pinMode(TOUCH_PIN, INPUT_PULLDOWN);
  pinMode(TOUCH_PIN_ALT, INPUT_PULLDOWN);
  delay(20);
  gpio2StuckHighAtBoot = (digitalRead(TOUCH_PIN) == HIGH);

  Serial.begin(115200);
  Serial.setTimeout(50); // Fast 50ms Serial read timeout so commands execute instantly even with "No line ending"
  unsigned long startWait = millis();
  while (!Serial && millis() - startWait < 2500) delay(10);

  Serial.println(F("\n=================================================="));
  Serial.println(F(" SafeGuard GPS Pendant — Master Firmware v2.4.0"));
  Serial.println(F(" Lindana v7 Voice + Touch + Alina Harbour + BLE"));
  Serial.println(F("=================================================="));

  // 1. Read MAC Address
  uint8_t baseMac[6];
  if (esp_read_mac(baseMac, ESP_MAC_WIFI_STA) == ESP_OK) {
    char macStr[18];
    snprintf(macStr, sizeof(macStr), "%02X:%02X:%02X:%02X:%02X:%02X",
             baseMac[0], baseMac[1], baseMac[2], baseMac[3], baseMac[4], baseMac[5]);
    deviceMacAddress = String(macStr);
  } else {
    deviceMacAddress = "7C:DF:A1:00:11:22";
  }
  Serial.printf("Device MAC Address: %s\n", deviceMacAddress.c_str());

  // 2. Load stored preferences & Alina Harbour Apartments anchor from Flash
  loadSettingsFromFlash();

  // 3. Initialize BLE GATT Server ("SafeGuard") BEFORE allocating I2S ring buffers
  //    so the ESP32-C3 BLE stack always gets its contiguous DRAM block cleanly!
  setupBLE();

  // 4. Initialize GPS UART (UART0 on GPIO4, GPIO3)
  pinMode(GPS_RX, INPUT_PULLUP);
  gpsSerial.setRxBufferSize(512);
  gpsSerial.begin(9600, SERIAL_8N1, GPS_RX, GPS_TX);
  Serial.println(F("[GPS] NEO-6M receiver active on UART0."));

  // 5. Initialize SIM800L UART (UART1 on GPIO5, GPIO6) — fast non-blocking startup
  SerialAT.setRxBufferSize(1024);
  SerialAT.begin(9600, SERIAL_8N1, SIM_RX, SIM_TX);
  delay(1500);

  Serial.print(F("[GSM] Checking SIM800L"));
  bool alive = false;
  for (int i = 0; i < 5 && !alive; i++) {
    alive = modem.testAT(500);
    Serial.print('.');
  }
  Serial.println();

  if (!alive) {
    Serial.println(F("[GSM] SIM800L warming up in background (will auto-init before SMS/Call)."));
  } else {
    modem.init();
    modem.sendAT(GF("E0"));
    modem.waitResponse(300);
    modem.sendAT(GF("+CMGF=1"));
    modem.waitResponse(300);
    modem.sendAT(GF("+CSCS=\"GSM\""));
    modem.waitResponse(300);
    if (modem.isNetworkConnected()) {
      Serial.printf("[GSM] Registered on: %s (Signal: %d/31)\n",
                    modem.getOperator().c_str(), modem.getSignalQuality());
    } else {
      Serial.printf("[GSM] SIM800L online (Signal: %d/31) — registering in background.\n",
                    modem.getSignalQuality());
    }
  }

  // 6. Initialize INMP441 I2S + Lindana v7 LAST (exact v7 startup order!)
  setupVoiceI2S();

  blinkLed(2, 100, 100);
  printMenu();
  Serial.println(F("[SYSTEM] Ready! Touch (GPIO1/GPIO2), Voice (\"Call the police\"), BLE, and Serial Console active.\n"));
}

// ------------------------------------------------------------------------------
// 14. MAIN LOOP
// ------------------------------------------------------------------------------
void loop() {
  feedGPS();
  updateTouch();
  updateVoiceI2S();

  unsigned long now = millis();

  // Handle LED Find Strobe or Hold-time after voice trigger
  if (findLedEndMs > now) {
    digitalWrite(PIN_STATUS_LED, (now % 200 < 100) ? HIGH : LOW);
  } else if (led_off_at && now > led_off_at) {
    digitalWrite(PIN_STATUS_LED, LOW);
    led_off_at = 0;
  }

  // Handle pending BLE / Phone App commands outside BLE interrupt context
  if (pendingStatusCmd) {
    pendingStatusCmd = false;
    sendStatusJsonOverBLE();
  }
  if (pendingLocateCmd) {
    pendingLocateCmd = false;
    Serial.println(F("\n[APP CONTROL] Sending live ESP32 coordinates (Alina Harbour / GPS) to Phone App..."));
    String lat, lon;
    getFix(lat, lon, 1500UL);
    sendLocationJsonOverBLE();
    reset_audio_stream();
  }
  if (pendingFindCmd) {
    pendingFindCmd = false;
    Serial.println(F("\n======================================================="));
    Serial.println(F(" [APP CONTROL] Blinking ESP32 LED (GPIO8) from Phone App!"));
    Serial.println(F("=======================================================\n"));
    alert_beep();
    findLedEndMs = millis() + 8000UL;
    sendStatusJsonOverBLE();
  }
  if (pendingRemoteSosCmd) {
    pendingRemoteSosCmd = false;
    Serial.println(F("\n======================================================="));
    Serial.println(F(" [APP CONTROL] Remote SOS Triggered from SafeLink App!"));
    Serial.println(F("======================================================="));
    currentTriggerReason = "remote_guardian";
    triggerPending = true;
  }
  if (pendingCancelSosCmd) {
    pendingCancelSosCmd = false;
    findLedEndMs = 0;
    digitalWrite(PIN_STATUS_LED, LOW);
    notifyPhoneOverBLE(0x00);
    Serial.println(F("[SOS] Active SOS & BLE beacon cancelled by Guardian."));
    reset_audio_stream();
  }
  if (pendingHangupCmd) {
    pendingHangupCmd = false;
    modem.callHangup();
    Serial.println(F("[CALL] Active call hung up."));
    reset_audio_stream();
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

  // Touch, Voice, or Remote Guardian trigger detected
  if (triggerPending) {
    triggerPending = false;
    if (currentTriggerReason == "pendant_voice") {
      Serial.println(F("\n[SOS] Voice Keyword (\"Call the police\") detected on INMP441!"));
    } else if (currentTriggerReason == "remote_guardian") {
      Serial.println(F("\n[SOS] Remote Guardian SOS triggered from SafeLink App!"));
    } else {
      Serial.println(F("\n[SOS] Touch pattern detected on Touch Sensor (GPIO1/GPIO2)!"));
    }
    if (benchFastMode) {
      uint8_t alertCode = (currentTriggerReason == "pendant_voice") ? 0x02 : 0x01;
      notifyPhoneOverBLE(alertCode);
      alert_beep();
      led_off_at = millis() + 1000UL;
      Serial.printf(">>> [BENCHMARK TRIAL COMPLETE] Trigger='%s' (BLE+LED confirmed; ready for next trial in 1.5s!) <<<\n\n", currentTriggerReason.c_str());
    } else {
      sendLocationAlert(FIX_WAIT_MS);
    }
  }

  // Interactive Serial Console Command Handler (Works with or without newline in Serial Monitor!)
  if (Serial.available() > 0) {
    String cmd = Serial.readStringUntil('\n');
    cmd.trim();
    if (cmd.length() > 0) {
      Serial.printf("\n[SERIAL CMD] Executing: '%s'\n", cmd.c_str());
      if (cmd == "bench on") {
        benchFastMode = true;
        Serial.println(F("[BENCHMARK MODE] Fast Trial Mode ENABLED (1.5s cooldown; BLE+LED active; skips 25s SMS/Call delay)."));
        reset_audio_stream();
      } else if (cmd == "bench off") {
        benchFastMode = false;
        voicePausedForTouchTest = false;
        Serial.println(F("[BENCHMARK MODE] Fast Trial Mode DISABLED (Full SMS + Voice Call dispatch restored)."));
        reset_audio_stream();
      } else if (cmd == "voice off") {
        voicePausedForTouchTest = true;
        Serial.println(F("[TOUCH TEST MODE] Voice inference paused — Touch Sensor polling at 1000 Hz (1 ms resolution)!"));
      } else if (cmd == "voice on") {
        voicePausedForTouchTest = false;
        reset_audio_stream();
        Serial.println(F("[TOUCH TEST MODE] Voice inference resumed."));
      } else if (cmd == "s") {
        currentTriggerReason = "pendant_touch";
        sendLocationAlert(FIX_WAIT_MS);
      } else if (cmd == "l" || cmd == "loc") {
        showLocation();
      } else if (cmd == "touch" || cmd == "touchtest") {
        testTouchLive();
      } else if (cmd == "t") {
        testSMS();
      } else if (cmd == "c") {
        callNumber();
      } else if (cmd == "h") {
        modem.callHangup();
        Serial.println(F("Hung up call."));
        reset_audio_stream();
      } else if (cmd == "b") {
        Serial.println(F("[TEST] Sending BLE SOS Alert (0x02) + 'SL' Beacon to SafeLink Phone App..."));
        notifyPhoneOverBLE(0x02);
        alert_beep();
        led_off_at = millis() + LED_HOLD_MS;
      } else if (cmd == "a") {
        Serial.println(F("[TEST] Running alert_beep() alarm..."));
        alert_beep();
        led_off_at = millis() + LED_HOLD_MS;
      } else if (cmd == "mode child") {
        ownerMode = "child";
        touchSosEnabled = false;
        prefs.begin("safeguard", false);
        prefs.putString("owner_mode", "child");
        prefs.putBool("touch_sos", false);
        prefs.end();
        Serial.println(F("[MODE] Switched to CHILD mode (Touch SOS disabled; Hold 3s calls parent)."));
        sendStatusJsonOverBLE();
        reset_audio_stream();
      } else if (cmd == "mode adult") {
        ownerMode = "adult";
        touchSosEnabled = true;
        prefs.begin("safeguard", false);
        prefs.putString("owner_mode", "adult");
        prefs.putBool("touch_sos", true);
        prefs.end();
        Serial.println(F("[MODE] Switched to ADULT mode (Touch SOS enabled)."));
        sendStatusJsonOverBLE();
        reset_audio_stream();
      } else if (cmd == "w") {
        showWearableStatus();
      } else if (cmd == "m") {
        String mLink = trackViewerUrl + "?lat=" + lastLat + "&lng=" + lastLon;
        Serial.println(F("\n--- 3D Mapbox Live Telemetry Link ---"));
        Serial.printf("Coordinates: %s, %s [%s]\n", lastLat.c_str(), lastLon.c_str(), currentLocSource.c_str());
        Serial.printf("Live URL:    %s\n", mLink.c_str());
        Serial.println(F("--------------------------------------\n"));
        reset_audio_stream();
      } else if (cmd == "d") {
        diagnose();
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
        reset_audio_stream();
      } else if (cmd == "i") {
        Serial.printf("Current Location: %s, %s (%s)\n",
                      lastLat.c_str(), lastLon.c_str(), currentLocSource.c_str());
        Serial.printf("3D Mapbox Live Link:     %s?lat=%s&lng=%s\n",
                      trackViewerUrl.c_str(), lastLat.c_str(), lastLon.c_str());
        Serial.println(F("To change, type: setloc <lat>,<lon>"));
        reset_audio_stream();
      } else if (cmd == "?") {
        printMenu();
        reset_audio_stream();
      } else {
        Serial.printf("Unknown command '%s'. Type '?' for menu.\n", cmd.c_str());
        reset_audio_stream();
      }
    }
  }

  delay(1);
}
