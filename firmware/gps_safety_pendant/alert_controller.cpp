#include "alert_controller.h"

void AlertController::begin() {
    led.begin(LED_PIN);
    touch.begin();
    gps.begin();
    gsm.begin();
    ble.begin(BLE_DEVICE_NAME);
    
    // Edge Impulse model init stub
    // e.g. run_classifier_init();
    
    changeState(STATE_IDLE);
}

void AlertController::update() {
    touch.update();
    gps.update();
    led.update();
    
    unsigned long now = millis();
    
    switch (state) {
        case STATE_IDLE:
            if (touch.isAlertPattern()) {
                changeState(STATE_TRIGGERED);
            }
            break;
            
        case STATE_TRIGGERED:
            changeState(STATE_CANCEL_WINDOW);
            break;
            
        case STATE_CANCEL_WINDOW:
            if (touch.isCancelPress()) {
                changeState(STATE_IDLE);
            } else if (now - stateEnterTime >= CANCEL_WINDOW_MS) {
                changeState(STATE_SENDING);
            }
            break;
            
        case STATE_SENDING:
            sendAlert();
            changeState(STATE_CONFIRMED);
            break;
            
        case STATE_CONFIRMED:
            if (now - stateEnterTime >= 3000) {
                changeState(STATE_IDLE);
            }
            break;
            
        case STATE_FAILED:
            if (now - stateEnterTime >= 5000) {
                changeState(STATE_IDLE);
            }
            break;
    }
}

void AlertController::changeState(AlertState newState) {
    state = newState;
    stateEnterTime = millis();
    
    switch (state) {
        case STATE_IDLE:
            led.setMode(HEARTBEAT);
            ble.clearAlert();
            break;
        case STATE_CANCEL_WINDOW:
            led.setMode(ALERT_PENDING);
            break;
        case STATE_CONFIRMED:
            led.setMode(CONFIRMED);
            break;
        default:
            break;
    }
}

void AlertController::sendAlert() {
    gps.waitForFix(GPS_TIMEOUT_MS);
    
    double lat = gps.getLatitude();
    double lng = gps.getLongitude();
    
    char msg[128];
    snprintf(msg, sizeof(msg), "EMERGENCY ALERT! Location: https://maps.google.com/?q=%f,%f", lat, lng);
    
    // Send SMS
    gsm.sendSms(EMERGENCY_CONTACT_1, msg);
    gsm.sendSms(EMERGENCY_CONTACT_2, msg);
    gsm.sendSms(EMERGENCY_CONTACT_3, msg);
    gsm.sendSms(EMERGENCY_CONTACT_POLICE, msg);
    
    // HTTP POST
    char jsonPayload[256];
    buildAlertJson(jsonPayload, lat, lng);
    gsm.httpPost(BACKEND_URL, jsonPayload);
    
    // BLE Advert
    ble.advertiseAlert();
}

void AlertController::buildAlertJson(char* buf, double lat, double lng) {
    snprintf(buf, 256, "{\"device_id\":\"%s\",\"lat\":%f,\"lng\":%f,\"type\":\"sos\"}", BLE_DEVICE_NAME, lat, lng);
}
