#include "touch_sensor.h"
#include <Wire.h>

void TouchSensor::begin() {
    Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
    if (!cap.begin(0x5A, &Wire)) {
        Serial.println("MPR121 not found, check wiring?");
    }
}

void TouchSensor::update() {
    alertPatternDetected = false;
    cancelPressDetected = false;
    
    uint16_t currtouched = cap.touched();
    bool isTouched = (currtouched & (1 << TOUCH_ELECTRODE)) != 0;
    
    unsigned long now = millis();
    
    // Check for long press (cancel)
    if (isTouched) {
        if (!wasTouched) {
            lastPressTime = now;
        } else if (now - lastPressTime > LONG_PRESS_CANCEL_MS) {
            cancelPressDetected = true;
            currentState = IDLE; // Reset state machine
        }
    }
    
    // State machine for double tap
    switch (currentState) {
        case IDLE:
            if (isTouched && !wasTouched) {
                currentState = PRESSED_1;
                stateChangeTime = now;
            }
            break;
            
        case PRESSED_1:
            if (!isTouched && wasTouched) {
                currentState = RELEASED_1;
                stateChangeTime = now;
            } else if (now - stateChangeTime > TOUCH_DOUBLE_PRESS_MS) {
                currentState = IDLE;
            }
            break;
            
        case RELEASED_1:
            if (isTouched && !wasTouched) {
                if (now - stateChangeTime <= TOUCH_DOUBLE_PRESS_MS) {
                    currentState = PRESSED_2;
                    alertPatternDetected = true;
                } else {
                    currentState = PRESSED_1;
                    stateChangeTime = now;
                }
            } else if (now - stateChangeTime > TOUCH_DOUBLE_PRESS_MS) {
                currentState = IDLE;
            }
            break;
            
        case PRESSED_2:
            if (!isTouched && wasTouched) {
                currentState = IDLE;
            }
            break;
    }
    
    wasTouched = isTouched;
}

bool TouchSensor::isAlertPattern() {
    return alertPatternDetected;
}

bool TouchSensor::isCancelPress() {
    return cancelPressDetected;
}
