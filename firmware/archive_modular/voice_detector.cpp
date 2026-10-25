
#ifdef ENABLE_VOICE_ACTIVATION
#include <driver/i2s.h>

// Check for micro model header (from notebook 04) or standard header (from
// notebook 03)
#if __has_include("safeguard_micro_model.h")
#include "safeguard_micro_model.h"
#define HAS_SAFEGUARD_MODEL 1
#include "tensorflow/lite/micro/all_ops_resolver.h"
#include "tensorflow/lite/micro/micro_error_reporter.h"
#include "tensorflow/lite/micro/micro_interpreter.h"
#include "tensorflow/lite/schema/schema_generated.h"
#elif __has_include("safeguard_model.h")
#include "safeguard_model.h"
#define HAS_SAFEGUARD_MODEL 1
#include "tensorflow/lite/micro/all_ops_resolver.h"
#include "tensorflow/lite/micro/micro_error_reporter.h"
#include "tensorflow/lite/micro/micro_interpreter.h"
#include "tensorflow/lite/schema/schema_generated.h"
#else
#define HAS_SAFEGUARD_MODEL 0
#endif

#if HAS_SAFEGUARD_MODEL
namespace {
tflite::MicroErrorReporter micro_error_reporter;
tflite::ErrorReporter *error_reporter = &micro_error_reporter;
const tflite::Model *tflite_model = nullptr;
tflite::MicroInterpreter *interpreter = nullptr;
TfLiteTensor *model_input = nullptr;

// Tensor arena for ESP32-C3 memory allocation
constexpr int kTensorArenaSize = 32 * 1024;
alignas(16) uint8_t tensor_arena[kTensorArenaSize];
} // namespace
#endif

VoiceDetector::VoiceDetector()
    : _isInitialized(false), _wakeWordDetected(false), _lastInferenceTime(0) {}

bool VoiceDetector::initI2S() {
  i2s_config_t i2s_config = {.mode =
                                 (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX),
                             .sample_rate = 16000,
                             .bits_per_sample = I2S_BITS_PER_SAMPLE_16BIT,
                             .channel_format = I2S_CHANNEL_FMT_ONLY_LEFT,
                             .communication_format = I2S_COMM_FORMAT_STAND_I2S,
                             .intr_alloc_flags = ESP_INTR_FLAG_LEVEL1,
                             .dma_buf_count = 4,
                             .dma_buf_len = 512,
                             .use_apll = false,
                             .tx_desc_auto_clear = false,
                             .fixed_mclk = 0};

  i2s_pin_config_t pin_config = {.bck_io_num = I2S_SCK_PIN,
                                 .ws_io_num = I2S_WS_PIN,
                                 .data_out_num = I2S_PIN_NO_CHANGE,
                                 .data_in_num = I2S_SD_PIN};

  esp_err_t err = i2s_driver_install(I2S_NUM_0, &i2s_config, 0, NULL);
  if (err != ESP_OK) {
    Serial.printf("[VOICE] I2S driver install failed: 0x%x\n", err);
    return false;
  }

  err = i2s_set_pin(I2S_NUM_0, &pin_config);
  if (err != ESP_OK) {
    Serial.printf("[VOICE] I2S set pin failed: 0x%x\n", err);
    return false;
  }

  Serial.println("[VOICE] I2S Microphone initialized (16kHz Mono)");
  return true;
}

bool VoiceDetector::begin() {
  if (!initI2S()) {
    return false;
  }

#if HAS_SAFEGUARD_MODEL
  tflite_model = tflite::GetModel(g_safeguard_model_data);
  if (tflite_model->version() != TFLITE_SCHEMA_VERSION) {
    Serial.println("[VOICE] Model schema version mismatch!");
    return false;
  }

  static tflite::AllOpsResolver resolver;
  static tflite::MicroInterpreter static_interpreter(
      tflite_model, resolver, tensor_arena, kTensorArenaSize, error_reporter);
  interpreter = &static_interpreter;

  TfLiteStatus allocate_status = interpreter->AllocateTensors();
  if (allocate_status != kTfLiteOk) {
    Serial.println("[VOICE] AllocateTensors() failed");
    return false;
  }

  model_input = interpreter->input(0);
  Serial.println(
      "[VOICE] TFLite model loaded successfully from safeguard_model.h");
#else
  Serial.println(
      "[VOICE] safeguard_model.h not yet compiled - running in standby mode");
#endif

  _isInitialized = true;
  return true;
}

void VoiceDetector::update() {
  if (!_isInitialized)
    return;

  unsigned long now = millis();
  // Run window classification every 500ms
  if (now - _lastInferenceTime >= 500) {
    _lastInferenceTime = now;
    if (runInference()) {
      _wakeWordDetected = true;
    }
  }
}

bool VoiceDetector::runInference() {
#if HAS_SAFEGUARD_MODEL
  if (!interpreter || !model_input)
    return false;

  // Read audio chunk from I2S
  constexpr int samples_to_read = 512;
  int16_t sample_buffer[samples_to_read];
  size_t bytes_read = 0;

  i2s_read(I2S_NUM_0, sample_buffer, sizeof(sample_buffer), &bytes_read,
           pdMS_TO_TICKS(50));

  if (bytes_read == 0)
    return false;

  // Run model inference
  TfLiteStatus invoke_status = interpreter->Invoke();
  if (invoke_status != kTfLiteOk)
    return false;

  TfLiteTensor *output = interpreter->output(0);
  if (!output)
    return false;

  // Classes: 0=_silence_, 1=_unknown_, 2=tuma_msaada, 3=piga_polisi,
  // 4=send_help, 5=call_police
  const char *class_names[] = {"_silence_",   "_unknown_", "tuma msaada",
                               "piga polisi", "send help", "call police"};

  // Handle INT8 quantized output (values -128 to 127)
  if (output->type == kTfLiteInt8 && output->data.int8 != nullptr) {
    for (int i = 2; i <= 5; i++) {
      // Confidence > 80% corresponds to int8 value > 75
      if (output->data.int8[i] > 75) {
        Serial.printf(
            "[VOICE] 🚨 Emergency wake phrase detected: '%s' (conf: %d)\n",
            class_names[i], output->data.int8[i]);
        return true;
      }
    }
  }
  // Handle Float32 output (values 0.0 to 1.0)
  else if (output->data.f != nullptr) {
    for (int i = 2; i <= 5; i++) {
      if (output->data.f[i] > 0.80f) {
        Serial.printf(
            "[VOICE] 🚨 Emergency wake phrase detected: '%s' (conf: %.2f)\n",
            class_names[i], output->data.f[i]);
        return true;
      }
    }
  }
#endif
  return false;
}

bool VoiceDetector::isWakeWordDetected() {
  if (_wakeWordDetected) {
    _wakeWordDetected = false;
    return true;
  }
  return false;
}

#endif // ENABLE_VOICE_ACTIVATION
