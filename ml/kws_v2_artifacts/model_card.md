# SafeGuard KWS v2: model card
**Task:** bilingual emergency keyword spotting (msaada, polisi, help, police) + unknown + noise, 1 s windows @16 kHz.
**Data:** Common Voice 27 Swahili (forced-aligned words), MSWC English, ESC-50 noise. Speaker-disjoint train/val/test.
**Model:** DS-CNN, 4,110 parameters, INT8 TFLite 19.4 KB.
**Best hyper-parameters:** {'lr': 0.0031762003176392588, 'width': 0.5, 'blocks': 4, 'dropout': 0.1, 'ls': 0.05, 'batch': 32, 'noise_p': 0.8, 'wd': 0.0001}

## Test results (per-clip)
| model                |   macro_f1 |   acc |   kw_recall |   false_accept |
|:---------------------|-----------:|------:|------------:|---------------:|
| majority class       |      0.113 | 0.513 |       0     |          0     |
| MFCC + LogReg        |      0.545 | 0.748 |       0.86  |          0.256 |
| MFCC + RandomForest  |      0.412 | 0.891 |       0.189 |          0.003 |
| DS-CNN (float32)     |      0.507 | 0.698 |       0.878 |          0.31  |
| DS-CNN (INT8 TFLite) |      0.506 | 0.692 |       0.884 |          0.318 |

## Streaming simulation (threshold 0.5, two-detection rule)
- Two-word trigger rate: 0.29
- One-word alert rate (safety property, want ~0): 0.19
- False alerts/hour on a harsh continuous negative stream: 233.04 (24.7 min of audio)

## Known limitations
- Training speech is read speech from phones/laptops, not shouted distress speech on the pendant microphone.
- Noise class comes from ESC-50 (no matatu / market recordings yet).
- Per-day false-alert rates cannot be claimed from minutes of audio; run a multi-hour real-environment test.
- Real-device recordings (`real/`) are the deciding evidence; the numbers above are an upper bound until they exist.
