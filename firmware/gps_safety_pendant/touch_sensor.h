#ifndef TOUCH_SENSOR_H
#define TOUCH_SENSOR_H

#include <Arduino.h>
#include <Adafruit_MPR121.h>
#include "config.h"

class TouchSensor {
public:
    void begin();
    void update();
    bool isAlertPattern();
    bool isCancelPress();

private:
    Adafruit_MPR121 cap;
    enum State { IDLE, PRESSED_1, RELEASED_1, PRESSED_2 };
    State currentState = IDLE;
    
    unsigned long stateChangeTime = 0;
    unsigned long lastPressTime = 0;
    bool wasTouched = false;
    bool alertPatternDetected = false;
    bool cancelPressDetected = false;
};

#endif // TOUCH_SENSOR_H
