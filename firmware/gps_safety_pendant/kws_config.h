#pragma once
// Auto-generated. Front-end must match training exactly.
#define KWS_SAMPLE_RATE      16000
#define KWS_WINDOW_SAMPLES   16000
#define KWS_FRAME_LEN        480
#define KWS_FRAME_STEP       320
#define KWS_FFT_LEN          512
#define KWS_NUM_MELS         40
#define KWS_NUM_FRAMES       49
#define KWS_MEL_FMIN_HZ      80.0f
#define KWS_MEL_FMAX_HZ      7600.0f
#define KWS_LOG_EPS          1e-6f
#define KWS_FEAT_MEAN        -3.960117f
#define KWS_FEAT_STD         6.056649f
#define KWS_INPUT_SCALE      0.01520991f
#define KWS_INPUT_ZERO_POINT -21
#define KWS_OUTPUT_SCALE     0.00390625f
#define KWS_OUTPUT_ZERO_POINT -128
#define KWS_NUM_CLASSES      6
#define KWS_THRESHOLD        0.5f
#define KWS_HOP_MS           250
#define KWS_PAIR_WINDOW_MS   4000
#define KWS_REFRACTORY_MS    600
#define KWS_COOLDOWN_MS      10000
static const char* KWS_LABELS[KWS_NUM_CLASSES] = {"msaada", "polisi", "help", "police", "unknown", "noise"};
// class ids that are keywords: 0=msaada, 1=polisi, 2=help, 3=police
