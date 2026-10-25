#include "led_controller.h"

void LedController::begin(int pin) {
    ledPin = pin;
    pinMode(ledPin, OUTPUT);
    digitalWrite(ledPin, LOW);
    setMode(HEARTBEAT);
}

void LedController::setMode(LedMode mode) {
    currentMode = mode;
    modeStartTime = millis();
    lastToggleTime = millis();
    
    if (mode == CONFIRMED) {
        digitalWrite(ledPin, HIGH);
        ledState = true;
    } else if (mode == OFF) {
        digitalWrite(ledPin, LOW);
        ledState = false;
    }
}

void LedController::update() {
    unsigned long now = millis();
    
    switch (currentMode) {
        case HEARTBEAT:
            if (now - lastToggleTime >= (ledState ? 100 : 1900)) {
                ledState = !ledState;
                digitalWrite(ledPin, ledState ? HIGH : LOW);
                lastToggleTime = now;
            }
            break;
            
        case ALERT_PENDING:
            if (now - lastToggleTime >= 250) { // 500ms cycle (250ms ON, 250ms OFF)
                ledState = !ledState;
                digitalWrite(ledPin, ledState ? HIGH : LOW);
                lastToggleTime = now;
            }
            break;
            
        case CONFIRMED:
            if (now - modeStartTime >= 3000) {
                setMode(HEARTBEAT);
            }
            break;
            
        case OFF:
            break;
    }
}
