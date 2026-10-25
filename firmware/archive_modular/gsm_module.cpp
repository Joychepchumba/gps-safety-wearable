#include "gsm_module.h"

void GsmModule::begin() {
    Serial2.begin(9600, SERIAL_8N1, GSM_RX_PIN, GSM_TX_PIN);
    
    // Wake up and test AT
    sendCommand("AT");
    waitForResponse("OK");
    
    // Disable echo
    sendCommand("ATE0");
    waitForResponse("OK");
    
    // Set SMS to text mode
    sendCommand("AT+CMGF=1");
    waitForResponse("OK");
    
    // Set APN
    char cmd[64];
    snprintf(cmd, sizeof(cmd), "AT+CSTT=\"%s\",\"\",\"\"", GSM_APN);
    sendCommand(cmd);
    waitForResponse("OK");
}

void GsmModule::sendCommand(const char* cmd) {
    Serial2.println(cmd);
}

bool GsmModule::waitForResponse(const char* expectedResponse, uint32_t timeoutMs) {
    unsigned long start = millis();
    String response = "";
    while (millis() - start < timeoutMs) {
        while (Serial2.available()) {
            char c = Serial2.read();
            response += c;
        }
        if (response.indexOf(expectedResponse) != -1) {
            return true;
        }
        delay(10);
    }
    return false;
}

bool GsmModule::sendSms(const char* number, const char* message) {
    char cmd[64];
    snprintf(cmd, sizeof(cmd), "AT+CMGS=\"%s\"", number);
    sendCommand(cmd);
    
    if (waitForResponse(">", 2000)) {
        Serial2.print(message);
        Serial2.write(26); // Ctrl+Z
        return waitForResponse("OK", 10000);
    }
    return false;
}

bool GsmModule::httpPost(const char* url, const char* jsonPayload) {
    sendCommand("AT+SAPBR=3,1,\"Contype\",\"GPRS\"");
    waitForResponse("OK");
    
    char cmd[128];
    snprintf(cmd, sizeof(cmd), "AT+SAPBR=3,1,\"APN\",\"%s\"", GSM_APN);
    sendCommand(cmd);
    waitForResponse("OK");
    
    sendCommand("AT+SAPBR=1,1");
    waitForResponse("OK", 3000);
    
    sendCommand("AT+HTTPINIT");
    waitForResponse("OK");
    
    sendCommand("AT+HTTPPARA=\"CID\",1");
    waitForResponse("OK");
    
    snprintf(cmd, sizeof(cmd), "AT+HTTPPARA=\"URL\",\"%s\"", url);
    sendCommand(cmd);
    waitForResponse("OK");
    
    sendCommand("AT+HTTPPARA=\"CONTENT\",\"application/json\"");
    waitForResponse("OK");
    
    snprintf(cmd, sizeof(cmd), "AT+HTTPDATA=%d,10000", strlen(jsonPayload));
    sendCommand(cmd);
    
    if (waitForResponse("DOWNLOAD", 2000)) {
        Serial2.print(jsonPayload);
        waitForResponse("OK", 2000);
        
        sendCommand("AT+HTTPACTION=1"); // POST
        if (waitForResponse("+HTTPACTION", 10000)) {
            sendCommand("AT+HTTPTERM");
            waitForResponse("OK");
            sendCommand("AT+SAPBR=0,1");
            return true;
        }
    }
    
    sendCommand("AT+HTTPTERM");
    sendCommand("AT+SAPBR=0,1");
    return false;
}

bool GsmModule::isReady() {
    sendCommand("AT");
    return waitForResponse("OK");
}

int GsmModule::getSignalStrength() {
    sendCommand("AT+CSQ");
    String response = "";
    unsigned long start = millis();
    while (millis() - start < 1000) {
        while (Serial2.available()) {
            char c = Serial2.read();
            response += c;
        }
        if (response.indexOf("OK") != -1) {
            break;
        }
    }
    
    int index = response.indexOf("+CSQ: ");
    if (index != -1) {
        return response.substring(index + 6, response.indexOf(",", index)).toInt();
    }
    return 0;
}
