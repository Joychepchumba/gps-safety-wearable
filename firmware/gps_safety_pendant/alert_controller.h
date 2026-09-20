#ifndef ALERT_CONTROLLER_H
#define ALERT_CONTROLLER_H

#include "touch_sensor.h"
#include "gps_module.h"
#include "gsm_module.h"
#include "ble_beacon.h"
#include "led_controller.h"

enum AlertState {
    STATE_IDLE,
    STATE_TRIGGERED,
    STATE_CANCEL_WINDOW,
    STATE_SENDING,
    STATE_CONFIRMED,
    STATE_FAILED
};

class AlertController {
public:
    void begin();
    void update();

private:
    TouchSensor touch;
    GpsModule gps;
    GsmModule gsm;
    BleBeacon ble;
    LedController led;
    
    AlertState state = STATE_IDLE;
    unsigned long stateEnterTime = 0;
    
    void sendAlert();
    void buildAlertJson(char* buf, double lat, double lng);
    void changeState(AlertState newState);
};

#endif // ALERT_CONTROLLER_H
