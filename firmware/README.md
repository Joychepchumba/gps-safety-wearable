# GPS Safety Pendant Firmware

This folder contains the Arduino firmware for the GPS Safety Wearable pendant based on the ESP32-C3 Super Mini.

## Hardware Wiring

| Component                 | Pin on ESP32-C3 | Description                  |
| ------------------------- | --------------- | ---------------------------- |
| GY-NEO6MV2 GPS (TX)       | D7              | UART1 RX                     |
| GY-NEO6MV2 GPS (RX)       | D6              | UART1 TX                     |
| SIM800L GSM (TX)          | D5              | UART2 RX                     |
| SIM800L GSM (RX)          | D4              | UART2 TX                     |
| MPR121 Touch (SDA)        | D2              | I2C SDA                      |
| MPR121 Touch (SCL)        | D3              | I2C SCL                      |
| Status LED                | D8              | Active HIGH                  |
| LiPo TP4056 sense         | D1              | ADC input (Battery Voltage)  |

## Dependencies / Libraries

You will need to install the following libraries in the Arduino IDE (or add to `platformio.ini`):
- `Adafruit_MPR121`
- `TinyGPSPlus` (TinyGPS++)
- `NimBLE-Arduino`

## Configuration

Before flashing, review and update the settings in `config.h`:
- `GSM_APN`: Update for your local SIM provider (currently set to 'safaricom').
- `BACKEND_URL`: Put the actual API URL.
- `EMERGENCY_CONTACT_X`: Update the emergency phone numbers.
- `BLE_DEVICE_NAME`: Change the Bluetooth broadcast name if desired.

## Flashing

### Arduino IDE
1. Select "ESP32C3 Dev Module" from the Boards menu.
2. Ensure you have the necessary libraries installed.
3. Select the COM port and hit Upload.

### Power Considerations
Ensure your power supply (LiPo + TP4056) can deliver at least 2A peak current for the SIM800L module. If it cannot, the GSM module will brown-out the ESP32 during network registration or transmission.
