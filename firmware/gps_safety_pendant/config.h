#ifndef CONFIG_H
#define CONFIG_H

// Pin Definitions
// MCU: ESP32-C3 Super Mini
// UART1: GY-NEO6MV2 GPS module
#define GPS_TX_PIN 6
#define GPS_RX_PIN 7

// UART2: SIM800L GSM module
#define GSM_TX_PIN 4
#define GSM_RX_PIN 5

// I2C: MPR121 Capacitive Touch sensor
#define I2C_SDA_PIN 2
#define I2C_SCL_PIN 3
#define TOUCH_ELECTRODE 0

// Status LED
#define LED_PIN 8

// Battery voltage sense
#define BAT_SENSE_PIN 1

// GSM Configuration
#define GSM_APN "safaricom"
#define BACKEND_URL "http://api.example.com/alert/pendant"

// BLE Configuration
#define BLE_DEVICE_NAME "SafeGuard-Pendant"
#define BLE_SERVICE_UUID "FFE0"
#define BLE_CHAR_ALERT_UUID "FFE1"

// Timing Constants
#define CANCEL_WINDOW_MS 10000
#define GPS_TIMEOUT_MS 30000
#define TOUCH_DOUBLE_PRESS_MS 1500
#define LONG_PRESS_CANCEL_MS 3000

// Emergency Contacts
#define EMERGENCY_CONTACT_1 "+254700000001"
#define EMERGENCY_CONTACT_2 "+254700000002"
#define EMERGENCY_CONTACT_3 "+254700000003"
#define EMERGENCY_CONTACT_POLICE "999"

#endif // CONFIG_H