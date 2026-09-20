#include "gps_module.h"

void GpsModule::begin() {
    Serial1.begin(9600, SERIAL_8N1, GPS_RX_PIN, GPS_TX_PIN);
}

void GpsModule::update() {
    while (Serial1.available() > 0) {
        gps.encode(Serial1.read());
    }
}

bool GpsModule::hasFix() {
    return gps.location.isValid() && gps.location.isUpdated();
}

double GpsModule::getLatitude() {
    return gps.location.lat();
}

double GpsModule::getLongitude() {
    return gps.location.lng();
}

float GpsModule::getAccuracy() {
    return gps.hdop.hdop();
}

bool GpsModule::waitForFix(uint32_t timeoutMs) {
    unsigned long start = millis();
    while (millis() - start < timeoutMs) {
        update();
        if (hasFix()) {
            return true;
        }
        delay(10);
    }
    return false;
}
