/*
 * GPS Safety Jewellery Wearable — Pendant Firmware
 * MCU: ESP32-C3 Super Mini
 * Author: Joy Kipkemboi — Strathmore University
 * 
 * Components:
 * - GY-NEO6MV2 GPS Module (UART D6/D7)
 * - SIM800L GSM Module (UART D4/D5)
 * - MPR121 Capacitive Touch (I2C SDA/SCL)
 * - Status LED (D2)
 * - LiPo 100mAh + TP4056 charger
 */

 #include "config.h"
 #include "alert_controller.h"
 #include "touch_sensor.h"
 #include "gps_module.h"
 #include "gsm_module.h"
 #include "ble_beacon.h"
 #include "led_controller.h"
 
 AlertController alertController;
 
 void setup() {
   Serial.begin(115200);
   Serial.println("GPS Safety Pendant — Starting...");
   alertController.begin();
   Serial.println("System ready.");
 }
 
 void loop() {
   alertController.update();
 }