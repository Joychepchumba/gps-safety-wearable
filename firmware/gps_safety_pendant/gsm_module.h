#ifndef GSM_MODULE_H
#define GSM_MODULE_H

#include <Arduino.h>
#include "config.h"

class GsmModule {
public:
    void begin();
    bool sendSms(const char* number, const char* message);
    bool httpPost(const char* url, const char* jsonPayload);
    bool isReady();
    int getSignalStrength();

private:
    void sendCommand(const char* cmd);
    bool waitForResponse(const char* expectedResponse, uint32_t timeoutMs = 1000);
};

#endif // GSM_MODULE_H
