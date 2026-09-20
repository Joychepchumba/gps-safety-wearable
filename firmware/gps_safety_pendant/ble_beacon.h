#ifndef BLE_BEACON_H
#define BLE_BEACON_H

#include <NimBLEDevice.h>
#include "config.h"

class BleBeacon {
public:
    void begin(const char* deviceName);
    void advertiseAlert();
    void clearAlert();

private:
    NimBLEServer* pServer;
    NimBLEService* pService;
    NimBLECharacteristic* pCharacteristic;
};

#endif // BLE_BEACON_H
