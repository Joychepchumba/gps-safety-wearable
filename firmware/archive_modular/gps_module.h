#ifndef GPS_MODULE_H
#define GPS_MODULE_H

#include <Arduino.h>
#include <TinyGPS++.h>
#include "config.h"

class GpsModule {
public:
    void begin();
    void update();
    bool hasFix();
    double getLatitude();
    double getLongitude();
    float getAccuracy();
    bool waitForFix(uint32_t timeoutMs);

private:
    TinyGPSPlus gps;
};

#endif // GPS_MODULE_H
