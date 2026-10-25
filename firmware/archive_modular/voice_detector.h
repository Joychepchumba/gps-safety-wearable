#ifndef VOICE_DETECTOR_H
#define VOICE_DETECTOR_H

#include <Arduino.h>
#include "config.h"

#ifdef ENABLE_VOICE_ACTIVATION

class VoiceDetector {
public:
    VoiceDetector();
    bool begin();
    void update();
    bool isWakeWordDetected();

private:
    bool _isInitialized;
    bool _wakeWordDetected;
    unsigned long _lastInferenceTime;
    
    bool initI2S();
    bool runInference();
};

#endif // ENABLE_VOICE_ACTIVATION
#endif // VOICE_DETECTOR_H
