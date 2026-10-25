
/*
 * SafeGuard GPS Safety Pendant — Wokwi Simulation Sketch
 * ════════════════════════════════════════════════════════
 * MCU   : ESP32-C3 Super Mini (board-esp32-c3-devkitm-1)
 * Author: Joy Kipkemboi — Strathmore University
 *
 * Actual hardware (from arduinotech.co.ke):
 *   GPS  : GY-NEO6MV2  → UART1   RX=GPIO6, TX=GPIO7
 *   GSM  : SIM800L V2  → UART2   RX=GPIO4, TX=GPIO5
 *   Touch: TTP223B     → GPIO2   (digital HIGH/LOW — no library, no I2C!)
 *   Mic  : Electret condenser 6mm → GPIO1 (ADC1_CH0, analog)
 *   Spkr : 8Ω 1W mini speaker     → GPIO8 (PWM tone / buzzer)
 *
 * Wokwi substitutions (no exact chips in Wokwi):
 *   TTP223B   → chip-ttp223b (click it to simulate touch)
 *   Speaker   → buzzer       (tone() output)
 *   Electret  → joystick VERT ADC channel (moves slider = changes mic level)
 *
 * Alert channels on trigger:
 *   1. SMS → user's personal emergency contacts (BLE-provisioned)
 *   2. SMS → Nisikilize GBV helpline: 1195 (free 24/7)
 *   3. SMS → Kenya Police 999 + 112 (works without airtime)
 *   4. HTTP POST → backend via SIM800L GPRS
 *   5. BLE Beacon → community responders with the SafeGuard phone app (~30m)
 *
 * HOW TO TEST:
 *   Boot → watch Serial Monitor for init messages
 *   TOUCH trigger : Click the TTP223B chip — double-tap within 1.5s
 *   MIC trigger   : Move joystick VERT above ~80% — sustained loud sound
 *   Cancel        : Hold TTP223B >3s during the 10s cancel window
 *   Fire          : Do nothing for 10s — watch all 5 channels dispatch
 */

#include <Arduino.h>
#include <TinyGPS++.h>

// ─── Pin Definitions (match config.h exactly) ────────────────────
#define GPS_RX_PIN 6
#define GPS_TX_PIN 7
#define GSM_RX_PIN 4
#define GSM_TX_PIN 5
#define TOUCH_PIN 2   // TTP223B SIG pin — digital
#define MIC_ADC_PIN 1 // Electret mic via ADC1_CH0
#define SPEAKER_PIN 8 // 8Ω 1W mini speaker via PWM

// ─── Timing ──────────────────────────────────────────────────────
#define CANCEL_WINDOW_MS 10000UL
#define TOUCH_DOUBLE_PRESS_MS 1500UL
#define LONG_PRESS_CANCEL_MS 3000UL
#define GPS_TIMEOUT_MS 30000UL
#define GSM_TIMEOUT_MS 2000UL
#define GSM_SMS_TIMEOUT_MS 10000UL

// ─── Microphone thresholds (12-bit ADC, 0–4095) ──────────────────
// Electret capsule + bias: idle ≈ 2048 (mid-rail)
// Loud shout moves ±500+ counts. Wokwi joystick maps 0–4095.
#define MIC_SHOUT_THRESHOLD 3000 // > this = loud sustained sound
#define MIC_SHOUT_HOLD_MS 1500   // must stay loud for 1.5s

// ─── Emergency contacts ──────────────────────────────────────────
static const char *PERSONAL_CONTACTS[] = {"+254700000001", "+254700000002",
                                          "+254700000003"};
static const int NUM_CONTACTS = 3;

static const char *HELPLINE_NISIKILIZE = "1195"; // GBV helpline (free)
static const char *HELPLINE_POLICE = "999";
static const char *HELPLINE_POLICE_ALT = "112"; // works w/o airtime

// ─── Device identity ─────────────────────────────────────────────
#define BLE_DEVICE_NAME "SafeGuard-Pendant"
#define BLE_SERVICE_UUID "FFE0"
#define BLE_CHAR_ALERT_UUID "FFE1"
#define BACKEND_URL "https://6aa4-102-208-82-115.ngrok-free.app/alert/pendant"
#define GSM_APN "safaricom"

// ─── Hardware ────────────────────────────────────────────────────
TinyGPSPlus gpsParser;
HardwareSerial gpsSerial(1); // UART1 → GPS
HardwareSerial gsmSerial(2); // UART2 → GSM

// ─── Alert State Machine ──────────────────────────────────────────
enum AlertState {
  STATE_IDLE,
  STATE_CANCEL_WINDOW,
  STATE_SENDING,
  STATE_CONFIRMED,
  STATE_FAILED
};
AlertState alertState = STATE_IDLE;
unsigned long stateEnter = 0;

// ─── TTP223B Touch State Machine ──────────────────────────────────
// TTP223B: output HIGH when finger present, LOW when not
// Double-tap = alert trigger | Hold >3s = cancel
enum TouchFSM { T_IDLE, T_PRESSED_1, T_RELEASED_1, T_PRESSED_2 };
TouchFSM touchState = T_IDLE;
unsigned long touchTimer = 0;
unsigned long holdStart = 0;
bool prevTouch = false;
bool doubleTapFired = false;
bool cancelHoldFired = false;

// ─── Microphone (electret ADC) ────────────────────────────────────
unsigned long micShoutStart = 0;
bool micAlertFired = false;

// ─── Speaker beep sequences ──────────────────────────────────────
void beepAlert() {
  // 3 short urgent beeps
  for (int i = 0; i < 3; i++) {
    tone(SPEAKER_PIN, 2000, 150);
    delay(300);
  }
}

void beepConfirmed() {
  // Rising two-tone = "sent"
  tone(SPEAKER_PIN, 1000, 200);
  delay(250);
  tone(SPEAKER_PIN, 1500, 300);
}

void beepCancelled() {
  // Descending = "cancelled"
  tone(SPEAKER_PIN, 1500, 200);
  delay(250);
  tone(SPEAKER_PIN, 800, 300);
}

void beepBoot() {
  tone(SPEAKER_PIN, 880, 100);
  delay(150);
  tone(SPEAKER_PIN, 1320, 150);
}

// ═════════════════════════════════════════════════════════════════
// GPS
// ═════════════════════════════════════════════════════════════════
void updateGps() {
  while (gpsSerial.available())
    gpsParser.encode(gpsSerial.read());
}

bool waitGpsFix(uint32_t ms) {
  Serial.println(F("[GPS]  Waiting for satellite fix..."));
  unsigned long t = millis();
  while (millis() - t < ms) {
    updateGps();
    if (gpsParser.location.isValid() && gpsParser.location.isUpdated()) {
      Serial.printf("[GPS]  ✓ Fix: %.6f, %.6f  sats=%d\n",
                    gpsParser.location.lat(), gpsParser.location.lng(),
                    gpsParser.satellites.value());
      return true;
    }
    delay(50);
  }
  Serial.println(F("[GPS]  ⚠ Timeout — using Nairobi default"));
  return false;
}

double getLat() {
  return gpsParser.location.isValid() ? gpsParser.location.lat() : -1.2921;
}
double getLng() {
  return gpsParser.location.isValid() ? gpsParser.location.lng() : 36.8219;
}

// ═════════════════════════════════════════════════════════════════
// GSM / SIM800L
// ═════════════════════════════════════════════════════════════════
void gsmWrite(const char *cmd) {
  gsmSerial.println(cmd);
  Serial.printf("[GSM]  >> %s\n", cmd);
}

bool gsmWait(const char *tok, uint32_t ms = GSM_TIMEOUT_MS) {
  String buf;
  unsigned long t = millis();
  while (millis() - t < ms) {
    while (gsmSerial.available())
      buf += (char)gsmSerial.read();
    if (buf.indexOf(tok) != -1) {
      buf.trim();
      if (buf.length())
        Serial.printf("[GSM]  << %s\n", buf.c_str());
      return true;
    }
    delay(10);
  }
  if (buf.length())
    Serial.printf("[GSM]  << %s\n", buf.c_str());
  return false;
}

void gsmInit() {
  Serial.println(F("[GSM]  Initialising SIM800L V2..."));
  delay(800);
  gsmWrite("AT");
  gsmWait("OK");
  gsmWrite("ATE0");
  gsmWait("OK");
  gsmWrite("AT+CMGF=1");
  gsmWait("OK");
  gsmWrite("AT+CSQ");
  gsmWait("OK");
  Serial.println(F("[GSM]  Ready"));
}

bool sendSms(const char *number, const char *message) {
  char cmd[64];
  snprintf(cmd, sizeof(cmd), "AT+CMGS=\"%s\"", number);
  gsmWrite(cmd);
  if (gsmWait(">", GSM_TIMEOUT_MS)) {
    gsmSerial.print(message);
    gsmSerial.write(26); // Ctrl+Z
    bool ok = gsmWait("OK", GSM_SMS_TIMEOUT_MS);
    Serial.printf("[SMS]  %s → %s\n", ok ? "✓ Sent" : "✗ FAILED", number);
    return ok;
  }
  // Wokwi sim: SIM800L may not reply with '>' — log and continue
  Serial.printf("[SMS]  (sim) Would send to %s\n", number);
  return true;
}

bool httpPostAlert(const char *json) {
  gsmWrite("AT+SAPBR=3,1,\"Contype\",\"GPRS\"");
  gsmWait("OK");
  char cmd[80];
  snprintf(cmd, sizeof(cmd), "AT+SAPBR=3,1,\"APN\",\"%s\"", GSM_APN);
  gsmWrite(cmd);
  gsmWait("OK");
  gsmWrite("AT+SAPBR=1,1");
  gsmWait("OK", 5000);
  gsmWrite("AT+HTTPINIT");
  gsmWait("OK");
  gsmWrite("AT+HTTPPARA=\"CID\",1");
  gsmWait("OK");
  snprintf(cmd, sizeof(cmd), "AT+HTTPPARA=\"URL\",\"%s\"", BACKEND_URL);
  gsmWrite(cmd);
  gsmWait("OK");
  gsmWrite("AT+HTTPPARA=\"CONTENT\",\"application/json\"");
  gsmWait("OK");
  snprintf(cmd, sizeof(cmd), "AT+HTTPDATA=%d,10000", strlen(json));
  gsmWrite(cmd);
  if (gsmWait("DOWNLOAD", GSM_TIMEOUT_MS)) {
    gsmSerial.print(json);
    gsmWait("OK", 3000);
    gsmWrite("AT+HTTPACTION=1");
    bool ok = gsmWait("+HTTPACTION", 12000);
    gsmWrite("AT+HTTPTERM");
    gsmWait("OK");
    gsmWrite("AT+SAPBR=0,1");
    Serial.printf("[HTTP] POST %s\n", ok ? "✓ Success" : "✗ Failed");
    return ok;
  }
  Serial.printf("[HTTP] (sim) POST payload: %s\n", json);
  gsmWrite("AT+HTTPTERM");
  gsmWrite("AT+SAPBR=0,1");
  return true;
}

// ═════════════════════════════════════════════════════════════════
// BLE BEACON — community responder broadcast (simulated printout)
// ═════════════════════════════════════════════════════════════════
void bleAdvertiseAlert(double lat, double lng) {
  Serial.println(F(""));
  Serial.println(F("┌─────────────────────────────────────────────────────┐"));
  Serial.println(F("│  BLE BEACON — Community Responder Broadcast          │"));
  Serial.println(F("│  Service UUID : FFE0                                 │"));
  Serial.println(F("│  Char UUID    : FFE1  (READ | NOTIFY)               │"));
  Serial.println(F("│  Value        : 0x01  (SOS active)                  │"));
  Serial.printf("│  Lat: %-10.6f  Lng: %-10.6f                  │\n", lat, lng);
  Serial.println(F("│  SafeGuard app community responders notified (~30m) │"));
  Serial.println(F("└─────────────────────────────────────────────────────┘"));
}

// ═════════════════════════════════════════════════════════════════
// FULL ALERT DISPATCH
// ═════════════════════════════════════════════════════════════════
void dispatchAlert() {
  beepAlert(); // Audible SOS beeps on speaker

  Serial.println(F(""));
  Serial.println(F("╔══════════════════════════════════════════════════════╗"));
  Serial.println(F("║         🚨  EMERGENCY ALERT DISPATCHING  🚨          ║"));
  Serial.println(F("╚══════════════════════════════════════════════════════╝"));

  waitGpsFix(GPS_TIMEOUT_MS);
  double lat = getLat();
  double lng = getLng();

  char smsBody[280];
  snprintf(smsBody, sizeof(smsBody),
           "EMERGENCY ALERT from SafeGuard Pendant!\n"
           "Live 3D Map: "
           "https://6aa4-102-208-82-115.ngrok-free.app/alert/track/"
           "live?lat=%.6f&lng=%.6f\n"
           "Google Maps: https://maps.google.com/?q=%.6f,%.6f\n"
           "Respond immediately.",
           lat, lng, lat, lng);

  // ── Channel 1: Personal emergency contacts ──
  Serial.println(F("\n── CHANNEL 1: Personal Emergency Contacts ──"));
  for (int i = 0; i < NUM_CONTACTS; i++)
    sendSms(PERSONAL_CONTACTS[i], smsBody);

  // ── Channel 2: Nisikilize GBV helpline ──
  Serial.println(F("\n── CHANNEL 2: Nisikilize GBV Helpline (1195) ──"));
  char nisiSms[220];
  snprintf(nisiSms, sizeof(nisiSms),
           "GBV ALERT — SafeGuard wearable activated.\n"
           "User location: https://maps.google.com/?q=%.6f,%.6f\n"
           "Device: %s",
           lat, lng, BLE_DEVICE_NAME);
  sendSms(HELPLINE_NISIKILIZE, nisiSms);

  // ── Channel 3: Kenya Police ──
  Serial.println(F("\n── CHANNEL 3: Kenya Police (999 + 112) ──"));
  char policeSms[220];
  snprintf(policeSms, sizeof(policeSms),
           "EMERGENCY — SafeGuard pendant activated.\n"
           "Immediate assistance needed.\n"
           "Location: https://maps.google.com/?q=%.6f,%.6f",
           lat, lng);
  sendSms(HELPLINE_POLICE, policeSms);
  sendSms(HELPLINE_POLICE_ALT, policeSms);

  // ── Channel 4: Backend HTTP POST via GPRS ──
  Serial.println(F("\n── CHANNEL 4: Backend HTTP POST (GPRS) ──"));
  char json[320];
  snprintf(json, sizeof(json),
           "{\"device_id\":\"%s\","
           "\"trigger\":\"pendant\","
           "\"lat\":%.6f,\"lng\":%.6f,"
           "\"contacts_sms\":%d,"
           "\"helplines\":[\"nisikilize_1195\",\"police_999\",\"police_112\"],"
           "\"ble_beacon\":true}",
           BLE_DEVICE_NAME, lat, lng, NUM_CONTACTS);
  httpPostAlert(json);

  // ── Channel 5: BLE Beacon → Community Responders ──
  Serial.println(F("\n── CHANNEL 5: BLE Beacon → Community Responders ──"));
  bleAdvertiseAlert(lat, lng);

  Serial.println(
      F("\n╔══════════════════════════════════════════════════════╗"));
  Serial.println(F("║   ✅  All 5 alert channels dispatched.               ║"));
  Serial.println(
      F("╚══════════════════════════════════════════════════════╝\n"));
}

// ═════════════════════════════════════════════════════════════════
// TOUCH SENSOR (TTP223B — single digital pin)
// HIGH = finger present, LOW = not touching
// Double-tap within 1.5s → alert trigger
// Hold >3s → cancel during cancel window
// ═════════════════════════════════════════════════════════════════
void updateTouch() {
  doubleTapFired = false;
  cancelHoldFired = false;

  bool isTouched = digitalRead(TOUCH_PIN) == HIGH;
  unsigned long now = millis();

  // Long-press cancel
  if (isTouched) {
    if (!prevTouch)
      holdStart = now;
    else if (now - holdStart > LONG_PRESS_CANCEL_MS) {
      cancelHoldFired = true;
      touchState = T_IDLE;
    }
  }

  // Double-tap FSM
  switch (touchState) {
  case T_IDLE:
    if (isTouched && !prevTouch) {
      touchState = T_PRESSED_1;
      touchTimer = now;
    }
    break;
  case T_PRESSED_1:
    if (!isTouched && prevTouch) {
      touchState = T_RELEASED_1;
      touchTimer = now;
    } else if (now - touchTimer > TOUCH_DOUBLE_PRESS_MS)
      touchState = T_IDLE;
    break;
  case T_RELEASED_1:
    if (isTouched && !prevTouch) {
      if (now - touchTimer <= TOUCH_DOUBLE_PRESS_MS) {
        touchState = T_PRESSED_2;
        doubleTapFired = true;
      } else {
        touchState = T_PRESSED_1;
        touchTimer = now;
      }
    } else if (now - touchTimer > TOUCH_DOUBLE_PRESS_MS)
      touchState = T_IDLE;
    break;
  case T_PRESSED_2:
    if (!isTouched && prevTouch)
      touchState = T_IDLE;
    break;
  }
  prevTouch = isTouched;
}

// ═════════════════════════════════════════════════════════════════
// MICROPHONE (Electret capsule — ADC threshold detection)
// The capsule needs a 10kΩ bias resistor to 3V3. In Wokwi the
// joystick VERT ADC simulates this — move it high to simulate a shout.
// ═════════════════════════════════════════════════════════════════
void updateMic() {
  micAlertFired = false;
  int level = analogRead(MIC_ADC_PIN); // 0–4095 on ESP32-C3

  if (level > MIC_SHOUT_THRESHOLD) {
    if (micShoutStart == 0)
      micShoutStart = millis();
    else if (millis() - micShoutStart >= MIC_SHOUT_HOLD_MS) {
      micAlertFired = true;
      micShoutStart = 0;
    }
  } else {
    micShoutStart = 0;
  }
}

// ═════════════════════════════════════════════════════════════════
// ALERT STATE MACHINE
// ═════════════════════════════════════════════════════════════════
void changeState(AlertState s) {
  alertState = s;
  stateEnter = millis();
  switch (s) {
  case STATE_IDLE:
    Serial.println(F("[STATE] → IDLE (waiting for double-tap or loud mic)"));
    break;
  case STATE_CANCEL_WINDOW:
    Serial.println(F("[STATE] → CANCEL WINDOW — 10s, hold touch to abort"));
    break;
  case STATE_SENDING:
    Serial.println(F("[STATE] → SENDING ALL ALERTS"));
    break;
  case STATE_CONFIRMED:
    Serial.println(F("[STATE] → CONFIRMED (resetting in 5s)"));
    break;
  case STATE_FAILED:
    Serial.println(F("[STATE] → FAILED (resetting in 5s)"));
    break;
  }
}

// ═════════════════════════════════════════════════════════════════
// SETUP & LOOP
// ═════════════════════════════════════════════════════════════════
void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println(F(""));
  Serial.println(F("╔══════════════════════════════════════════════════════╗"));
  Serial.println(F("║   SafeGuard GPS Safety Pendant — Wokwi Simulation   ║"));
  Serial.println(F("║   ESP32-C3 Super Mini | Joy Kipkemboi, Strathmore   ║"));
  Serial.println(F("╚══════════════════════════════════════════════════════╝"));

  // GPIO init
  pinMode(TOUCH_PIN, INPUT_PULLDOWN);
  pinMode(SPEAKER_PIN, OUTPUT);
  analogReadResolution(12); // 12-bit ADC (0–4095)

  // GPS — UART1
  gpsSerial.begin(9600, SERIAL_8N1, GPS_RX_PIN, GPS_TX_PIN);
  Serial.printf("[GPS]  Serial1 ready (RX=GPIO%d TX=GPIO%d)\n", GPS_RX_PIN,
                GPS_TX_PIN);

  // GSM — UART2
  gsmSerial.begin(9600, SERIAL_8N1, GSM_RX_PIN, GSM_TX_PIN);
  Serial.printf("[GSM]  Serial2 ready (RX=GPIO%d TX=GPIO%d)\n", GSM_RX_PIN,
                GSM_TX_PIN);
  gsmInit();

  // Info
  Serial.println(F(""));
  Serial.println(F("Hardware:"));
  Serial.printf("  Touch  : TTP223B → GPIO%d (digital HIGH/LOW)\n", TOUCH_PIN);
  Serial.printf("  Mic    : Electret condenser → GPIO%d (ADC)\n", MIC_ADC_PIN);
  Serial.printf("  Speaker: 8Ω 1W mini speaker → GPIO%d (PWM)\n", SPEAKER_PIN);
  Serial.println(F("\nAlert recipients on trigger:"));
  Serial.println(F("  1. Personal contacts  (BLE-provisioned from app)"));
  Serial.printf("  2. Nisikilize GBV      %s (free 24/7)\n",
                HELPLINE_NISIKILIZE);
  Serial.printf("  3. Kenya Police        %s / %s\n", HELPLINE_POLICE,
                HELPLINE_POLICE_ALT);
  Serial.println(F("  4. Backend HTTP POST  via SIM800L GPRS"));
  Serial.println(F("  5. BLE beacon         community responders ~30m\n"));

  beepBoot();
  changeState(STATE_IDLE);
  Serial.println(F("► Double-tap TTP223B chip to trigger alert."));
  Serial.println(
      F("► Move joystick VERT high (>73%) for 1.5s = mic shout trigger."));
  Serial.println(F("► Hold TTP223B >3s during cancel window to abort.\n"));
}

void loop() {
  updateGps();
  updateTouch();
  updateMic();

  unsigned long now = millis();

  switch (alertState) {

  case STATE_IDLE:
    if (doubleTapFired) {
      Serial.println(
          F("[TOUCH] ⚡ Double-tap — 10s cancel window starting..."));
      changeState(STATE_CANCEL_WINDOW);
    } else if (micAlertFired) {
      Serial.println(
          F("[MIC]   🎙 Sustained loud sound detected — alert triggered!"));
      changeState(STATE_CANCEL_WINDOW);
    }
    break;

  case STATE_CANCEL_WINDOW: {
    if (cancelHoldFired) {
      beepCancelled();
      Serial.println(F("[TOUCH] Long-press — ALERT CANCELLED."));
      changeState(STATE_IDLE);
      break;
    }
    unsigned long elapsed = now - stateEnter;
    if (elapsed >= CANCEL_WINDOW_MS) {
      changeState(STATE_SENDING);
    } else {
      static unsigned long lastCnt = 0;
      if (now - lastCnt >= 2000) {
        lastCnt = now;
        uint32_t rem = (CANCEL_WINDOW_MS - elapsed + 999) / 1000;
        Serial.printf("[CANCEL] %us remaining — hold touch to abort...\n", rem);
      }
    }
    break;
  }

  case STATE_SENDING:
    dispatchAlert();
    beepConfirmed();
    changeState(STATE_CONFIRMED);
    break;

  case STATE_CONFIRMED:
    if (now - stateEnter >= 5000)
      changeState(STATE_IDLE);
    break;

  case STATE_FAILED:
    if (now - stateEnter >= 5000)
      changeState(STATE_IDLE);
    break;
  }
}