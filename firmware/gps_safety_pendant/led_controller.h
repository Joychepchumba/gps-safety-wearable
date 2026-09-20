#ifndef LED_CONTROLLER_H
#define LED_CONTROLLER_H

#include <Arduino.h>

enum LedMode { HEARTBEAT, ALERT_PENDING, CONFIRMED, OFF };

class LedController {
public:
    void begin(int pin);
    void setMode(LedMode mode);
    void update();

private:
    int ledPin;
    LedMode currentMode = OFF;
    unsigned long lastToggleTime = 0;
    unsigned long modeStartTime = 0;
    bool ledState = false;
};

#endif // LED_CONTROLLER_H
