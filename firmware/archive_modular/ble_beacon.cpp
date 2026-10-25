#include "ble_beacon.h"

void BleBeacon::begin(const char* deviceName) {
    NimBLEDevice::init(deviceName);
    
    pServer = NimBLEDevice::createServer();
    pService = pServer->createService(BLE_SERVICE_UUID);
    
    pCharacteristic = pService->createCharacteristic(
        BLE_CHAR_ALERT_UUID,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY
    );
    
    uint8_t initVal = 0x00;
    pCharacteristic->setValue(&initVal, 1);
    
    pService->start();
    
    NimBLEAdvertising* pAdvertising = NimBLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(BLE_SERVICE_UUID);
    pAdvertising->start();
}

void BleBeacon::advertiseAlert() {
    uint8_t alertVal = 0x01;
    pCharacteristic->setValue(&alertVal, 1);
    pCharacteristic->notify();
}

void BleBeacon::clearAlert() {
    uint8_t initVal = 0x00;
    pCharacteristic->setValue(&initVal, 1);
    pCharacteristic->notify();
}
