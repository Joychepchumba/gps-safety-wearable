#ifndef CONFIG_H
#define CONFIG_H

// ═══════════════════════════════════════════════════════════════
// SafeGuard GPS Safety Pendant — Hardware Configuration
// MCU: ESP32-C3 Super Mini (board-esp32-c3-devkitm-1)
// Source: https://arduinotech.co.ke
// ═══════════════════════════════════════════════════════════════

// ── UART1: GY-NEO6MV2 GPS Module ────────────────────────────────
// https://arduinotech.co.ke/product/gy-neo6mv2-...
// Wiring: VCC→3V3, GND→GND, TX→GPIO6, RX→GPIO7
#define GPS_RX_PIN   6   // ESP32-C3 receives from GPS TX
#define GPS_TX_PIN   7   // ESP32-C3 transmits to GPS RX

// ── UART2: SIM800L V2.0 GSM Module (5V, Quad-Band) ──────────────
// https://arduinotech.co.ke/product/sim800l-v2-0-5v-gsm-gprs...
// Wiring: VCC→5V (or VUSB), GND→GND, TX→GPIO4, RX→GPIO5
#define GSM_RX_PIN   4   // ESP32-C3 receives from SIM800L TX
#define GSM_TX_PIN   5   // ESP32-C3 transmits to SIM800L RX
#define GSM_APN      "safaricom"

// ── TTP223B Capacitive Touch Sensor (single digital output) ──────
// https://arduinotech.co.ke/product/ttp223b-1-channel-capacitive...
// Wiring: VCC→3V3, GND→GND, SIG→GPIO2
// Output: HIGH (touched) / LOW (not touched) — direct digital read
// NOTE: replaces MPR121; no I2C needed, no library needed
#define TOUCH_PIN    2

// ── 6mm × 2.2mm Electret Condenser Microphone Capsule ────────────
// https://arduinotech.co.ke/product/6mm-2-2mm-electret-condenser...
// Wiring: +→GPIO1 (ADC1_CH0 via 10kΩ pull-up bias), −→GND
// Output: analog AC audio signal (read via ADC) — threshold-based
// External amplifier recommended for voice keyword detection
#define MIC_ADC_PIN  1   // GPIO1 = ADC1_CH0 on ESP32-C3

// ── Mini Speaker 8Ω 1W (15-20mm round loudspeaker) ───────────────
// https://arduinotech.co.ke/product/mini-speaker-8-ohm-1w...
// Wiring: +→GPIO8 (via NPN transistor or 100Ω series resistor), −→GND
// Driven by PWM tone() — plays alert beep on trigger/confirmed
#define SPEAKER_PIN  8

// ── GSM / Backend ────────────────────────────────────────────────
#define BACKEND_URL  "http://api.example.com/alert/pendant"

// ── BLE ─────────────────────────────────────────────────────────
#define BLE_DEVICE_NAME      "SafeGuard-Pendant"
#define BLE_SERVICE_UUID     "FFE0"
#define BLE_CHAR_ALERT_UUID  "FFE1"

// ── Timing ──────────────────────────────────────────────────────
#define CANCEL_WINDOW_MS       10000UL  // 10 s cancel window
#define GPS_TIMEOUT_MS         30000UL  // max wait for GPS fix
#define TOUCH_DOUBLE_PRESS_MS   1500UL  // max gap between taps (TTP223B)
#define LONG_PRESS_CANCEL_MS    3000UL  // hold >3s to cancel

// ── Microphone (ADC threshold-based voice activity) ──────────────
#define MIC_SILENCE_THRESHOLD  300     // ADC counts below = silence
#define MIC_SHOUT_THRESHOLD    2500    // ADC counts above = loud shout

// ── Emergency Contacts (personal — provisioned via BLE from app) ──
#define EMERGENCY_CONTACT_1  "+254700000001"
#define EMERGENCY_CONTACT_2  "+254700000002"
#define EMERGENCY_CONTACT_3  "+254700000003"

// ── Helplines (hardcoded — always notified) ───────────────────────
#define HELPLINE_NISIKILIZE  "1195"   // Nisikilize GBV helpline (free 24/7)
#define HELPLINE_POLICE      "999"    // Kenya Police emergency
#define HELPLINE_POLICE_ALT  "112"    // Safaricom emergency (works w/o airtime)

#endif // CONFIG_H