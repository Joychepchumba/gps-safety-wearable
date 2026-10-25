#define TINY_GSM_MODEM_SIM800
#define TINY_GSM_RX_BUFFER 1024

#include <TinyGsmClient.h>
#include <TinyGPSPlus.h>

// ---------- pins (ESP32 RX pin = module TX) ----------
#define SIM_RX     5     // SIM800L TX -> GPIO5
#define SIM_TX     6     // SIM800L RX -> GPIO6
#define GPS_RX     4     // NEO-6M TX  -> GPIO4
#define GPS_TX     3     // NEO-6M RX  -> GPIO3
#define TOUCH_PIN  1     // TTP223B I/O -> GPIO1

HardwareSerial SerialAT(1);    // SIM800L on UART1
HardwareSerial gpsSerial(0);   // NEO-6M on UART0 (USB CDC carries Serial)

TinyGsm modem(SerialAT);
TinyGPSPlus gps;

const char number[] = "+254740034499";   //-> change with your number
const char simPin[] = "";                //-> leave empty if no PIN

// ---------- settings ----------
const unsigned long FIX_WAIT_MS     = 30000UL;   // wait for a fresh GPS fix after a trigger
const unsigned long DOUBLE_GAP_MS   = 1000UL;    // max time between release and 2nd press
const unsigned long LONG_PRESS_MS   = 1500UL;    // a press longer than this is ignored
const unsigned long DEBOUNCE_MS     = 40UL;
const unsigned long COOLDOWN_MS     = 30000UL;   // minimum time between triggered SMS

// last good fix, kept in RAM
String lastLat = "", lastLon = "";
unsigned long lastFixMs = 0;

// ---------- GPS ----------

void feedGPS() {
  while (gpsSerial.available()) gps.encode(gpsSerial.read());
  if (gps.location.isValid() && gps.location.age() < 2000) {
    lastLat = String(gps.location.lat(), 6);
    lastLon = String(gps.location.lng(), 6);
    lastFixMs = millis();
  }
}

// Waits up to timeoutMs for a fresh fix.
bool getFix(String &lat, String &lon, unsigned long timeoutMs) {
  unsigned long start = millis();
  while (millis() - start < timeoutMs) {
    feedGPS();
    if (lastFixMs != 0 && millis() - lastFixMs < 3000) {
      lat = lastLat;
      lon = lastLon;
      return true;
    }
    delay(5);
  }
  return false;
}

// ---------- SMS / call ----------

bool sendSMS(const String &text) {
  Serial.println("Sending: " + text);
  bool ok = modem.sendSMS(number, text);
  Serial.println(ok ? F("SMS sent") : F("SMS failed"));
  return ok;
}

// Sends the live location, or the last known one, or an alert with no location.
void sendLocationSMS(unsigned long waitMs) {
  Serial.println(F("Getting GPS fix..."));
  String lat, lon;
  if (getFix(lat, lon, waitMs)) {
    sendSMS("ALERT. My location: https://maps.google.com/?q=" + lat + "," + lon);
  } else if (lastFixMs != 0) {
    unsigned long mins = (millis() - lastFixMs) / 60000UL;
    sendSMS("ALERT. No live GPS fix. Last known location (" + String(mins) +
            " min ago): https://maps.google.com/?q=" + lastLat + "," + lastLon);
  } else {
    sendSMS("ALERT. No GPS fix available yet.");
  }
}

void showLocation() {
  Serial.println(F("Waiting for GPS fix (up to 3 min)..."));
  String lat, lon;
  if (getFix(lat, lon, 180000UL)) {
    Serial.println("https://maps.google.com/?q=" + lat + "," + lon);
  } else {
    Serial.println(F("No GPS fix. Take it outside with a clear view of the sky."));
  }
}

void callNumber() {
  Serial.println(F("Calling..."));
  bool ok = modem.callNumber(number);
  Serial.println(ok ? F("Call started") : F("Call failed"));
  delay(15000);
  modem.callHangup();
  Serial.println(F("Hung up"));
}

// ---------- diagnostics / SIM ----------

void diagnose() {
  Serial.print(F("Modem: "));          Serial.println(modem.getModemInfo());
  Serial.print(F("SIM status: "));     Serial.println(modem.getSimStatus());   // 1 = ready
  Serial.print(F("Registered: "));     Serial.println(modem.isNetworkConnected() ? F("yes") : F("no"));
  Serial.print(F("Operator: "));       Serial.println(modem.getOperator());
  Serial.print(F("Signal (0-31): "));  Serial.println(modem.getSignalQuality());
  Serial.print(F("Battery mV: "));     Serial.println(modem.getBattVoltage());
  Serial.print(F("GPS chars: "));      Serial.println(gps.charsProcessed());
  Serial.print(F("GPS satellites: ")); Serial.println(gps.satellites.isValid() ? gps.satellites.value() : 0);
}

// Disable the SIM PIN lock. Run ONCE with the SIM that has a PIN.
void removeSimPin(const char *pin) {
  if (modem.getSimStatus() == SIM_LOCKED) {
    modem.simUnlock(pin);
    delay(3000);
  }
  modem.sendAT(GF("+CLCK=\"SC\",0,\""), pin, GF("\""));
  int res = modem.waitResponse(10000L);
  Serial.println(res == 1 ? F("PIN lock removed") : F("Failed to remove PIN lock"));
}

void printMenu() {
  Serial.println(F("Touch: press-release-press = send location SMS"));
  Serial.println(F("s=send location SMS, l=show location, t=test SMS, c=call,"));
  Serial.println(F("h=hang up, d=diagnose, p=remove SIM PIN"));
}

// ---------- touch pattern: press, release, press ----------

enum TouchState { IDLE, PRESS1, GAP, DONE_WAIT_RELEASE };
TouchState tState = IDLE;
bool touchStable = false;           // debounced level (true = touched)
bool touchRaw = false;
unsigned long rawChangedMs = 0;
unsigned long pressStartMs = 0;
unsigned long releaseMs = 0;
unsigned long lastTriggerMs = 0;
bool triggerPending = false;

// Call every loop. Sets triggerPending when the pattern is complete.
void updateTouch() {
  unsigned long now = millis();
  bool raw = digitalRead(TOUCH_PIN) == HIGH;   // TTP223B is HIGH when touched

  if (raw != touchRaw) { touchRaw = raw; rawChangedMs = now; }

  if (now - rawChangedMs >= DEBOUNCE_MS && touchStable != touchRaw) {
    touchStable = touchRaw;

    if (touchStable) {                          // ---- pressed ----
      if (tState == IDLE) {
        tState = PRESS1;
        pressStartMs = now;
      } else if (tState == GAP && now - releaseMs <= DOUBLE_GAP_MS) {
        tState = DONE_WAIT_RELEASE;             // second press: pattern complete
        if (now - lastTriggerMs >= COOLDOWN_MS || lastTriggerMs == 0) {
          triggerPending = true;
          lastTriggerMs = now;
        } else {
          Serial.println(F("Touch ignored (cooldown)."));
        }
      } else {
        tState = PRESS1;                        // gap too long: treat as a new first press
        pressStartMs = now;
      }
    } else {                                    // ---- released ----
      if (tState == PRESS1) {
        if (now - pressStartMs <= LONG_PRESS_MS) {
          tState = GAP;
          releaseMs = now;
        } else {
          tState = IDLE;                        // held too long
        }
      } else if (tState == DONE_WAIT_RELEASE) {
        tState = IDLE;
      }
    }
  }

  // gap expired without a second press
  if (tState == GAP && now - releaseMs > DOUBLE_GAP_MS) tState = IDLE;
  // stuck-high protection (sensor held or faulty)
  if (tState == PRESS1 && touchStable && now - pressStartMs > LONG_PRESS_MS) tState = IDLE;
}

// ---------- setup / loop ----------

void setup() {
  Serial.begin(115200);
  unsigned long w = millis();
  while (!Serial && millis() - w < 3000) delay(10);
  Serial.println(F("System started..."));

  pinMode(TOUCH_PIN, INPUT);

  SerialAT.setRxBufferSize(1024);
  SerialAT.begin(9600, SERIAL_8N1, SIM_RX, SIM_TX);
  delay(3000);

  Serial.println(F("Initialising modem..."));
  bool alive = false;
  for (int i = 0; i < 20 && !alive; i++) {      // wait up to ~20 s for the module
    alive = modem.testAT(1000);
    Serial.print('.');
  }
  Serial.println();

  if (!alive || !modem.init()) {
    Serial.println(F("No response from SIM800L. Check power, wiring, baud."));
  } else {
    if (modem.getSimStatus() == SIM_LOCKED) {
      if (strlen(simPin) == 0) Serial.println(F("SIM needs a PIN but simPin is empty."));
      else modem.simUnlock(simPin);
    }
    Serial.println(F("Waiting for network..."));
    if (modem.waitForNetwork(90000L)) {
      Serial.print(F("Registered on: ")); Serial.println(modem.getOperator());
      Serial.print(F("Signal: "));        Serial.println(modem.getSignalQuality());
    } else {
      Serial.println(F("NOT registered. Check power, antenna, SIM, 2G coverage."));
    }
  }

  // start the GPS UART last, with a pull-up so a disconnected pin can't float
  pinMode(GPS_RX, INPUT_PULLUP);
  gpsSerial.setRxBufferSize(512);
  gpsSerial.begin(9600, SERIAL_8N1, GPS_RX, GPS_TX);

  printMenu();
}

void loop() {
  feedGPS();          // keeps GPS parsing and the last fix up to date
  updateTouch();

  if (triggerPending) {
    triggerPending = false;
    Serial.println(F("Touch pattern detected."));
    sendLocationSMS(FIX_WAIT_MS);
  }

  if (Serial.available() > 0) {
    char c = Serial.read();
    if      (c == 's') sendLocationSMS(FIX_WAIT_MS);
    else if (c == 'l') showLocation();
    else if (c == 't') sendSMS("Hello from ESP32-C3");
    else if (c == 'c') callNumber();
    else if (c == 'h') { modem.callHangup(); Serial.println(F("Hung up")); }
    else if (c == 'd') diagnose();
    else if (c == 'p') removeSimPin("1234");   // replace 1234 with the real PIN
  }
  delay(1);
}