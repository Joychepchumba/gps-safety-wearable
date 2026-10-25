# SafeGuard Speech NLP & Emergency Keyword Detection Pipeline
**Project:** SafeGuard GPS Safety Wearable  
**Domain:** Bilingual Emergency Keyword Spotting & ASR (Kenyan Kiswahili + English)  
**Architecture:** Meta MMS (Massively Multilingual Speech) • CTC Alignment • TinyML DS-CNN for ESP32

---

## 🚀 Two Clean Notebooks — Simple & Streamlined

To eliminate complexity, everything has been unified into **two self-contained notebooks**:

### 🌟 1. [`notebooks/SafeGuard_STT_Master_Pipeline.ipynb`](file:///c:/Users/joych/gps-safety-wearable/ml/keyword_detection/notebooks/SafeGuard_STT_Master_Pipeline.ipynb) *(Recommended — Cloud & Backend Model)*
**The Complete All-In-One NLP Master Notebook:**
- **No file juggling, no zip transfers:** Runs everything end-to-end in a single Google Colab tab.
- **Workflow Included:**
  1. **EDA & Preprocessing:** Streams Google FLEURS (`sw_ke` & `en_us`), generates 128-band Mel-Spectrograms, VAD silence trimming, and zero-leakage splits.
  2. **Baseline Negative Control:** Demonstrates the untuned baseline (100% WER) to satisfy scientific peer review.
  3. **Meta MMS Transfer Learning:** Fine-tunes `facebook/mms-300m` with AdamW, Cosine Annealing, and SpecAugment.
  4. **Multi-Metric Validation:** Computes Clean & Noisy Test WER/CER, Wake-Word Precision/Recall/F1, and plots the high-res Seaborn Confusion Matrix.
  5. **Model Export:** Packages the final model into `safeguard_voice_model.zip` and triggers an automatic browser download.
- **Runtime:** ~10–12 minutes on Google Colab (free T4 GPU).

---

### ⚡ 2. [`notebooks/SafeGuard_ESP32_Micro_KWS.ipynb`](file:///c:/Users/joych/gps-safety-wearable/ml/keyword_detection/notebooks/SafeGuard_ESP32_Micro_KWS.ipynb) *(Hardware Model)*
- **TinyML On-Device Model:** Trains a Depthwise Separable CNN (DS-CNN) with 40 Mel bins.
- **Quantization:** Produces a ~32 KB INT8 quantized header file `safeguard_micro_model.h` for compiling directly onto the ESP32-C3 microcontroller pendant.

---

## 📖 Comprehensive Academic Technical Report
For thesis defense, presentation slides, and mathematical derivations of CTC Loss & MMS acoustic representations:  
📄 **[`docs/NLP_SPEECH_RECOGNITION_TECHNICAL_REPORT.md`](file:///c:/Users/joych/gps-safety-wearable/docs/NLP_SPEECH_RECOGNITION_TECHNICAL_REPORT.md)**
