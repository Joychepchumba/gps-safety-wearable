# Chapter 5: System Implementation, Testing and Evaluation

## 5.1 Introduction

This chapter explains how the approved design for the SafeGuard GPS Safety Wearable and Companion Emergency Response System was implemented, configured, tested, and evaluated. It presents what was built across the wearable hardware prototype, the cloud-trained Edge Impulse keyword spotting model, the Flutter mobile companion application, and the FastAPI and Supabase backend. Because SafeGuard is a hybrid project combining an embedded IoT wearable, an edge machine learning voice trigger, and a mobile-cloud emergency response application, this chapter follows the hybrid structure covering the implementation environment, software and database modules, Edge Impulse model implementation, hardware and firmware integration, system testing, version control evidence, and evaluation against the project objectives.

---

## 5.2 Implementation Environment

The SafeGuard system was developed and tested as a local hardware prototype paired with a mobile companion application and a private cloud database deployment. Development, Edge Impulse model training, firmware compilation, and end-to-end testing were conducted across a local development laptop, the Edge Impulse Studio web platform, an Android smartphone, and an ESP32-based wearable prototype.

### 5.2.1 Hardware and Deployment Environment

Table 5.1 summarizes the client devices, cloud runtime services, and specialized embedded hardware used to develop and test the finished prototype, together with the minimum tested specifications and supporting evidence.

**Table 5.1: Implementation environment and minimum requirements**

| Item or layer | Minimum tested specification or version | Purpose and justification | Evidence or source |
| :--- | :--- | :--- | :--- |
| **Development laptop** | Windows 11 (64-bit), Intel Core i5 / x86_64 processor, 8 GB RAM, 256 GB SSD, Wi-Fi and USB 2.0 | Used to write and compile microcontroller firmware in Arduino IDE, build the Flutter mobile application, and run the FastAPI backend server. | Local build logs and development environment verification. |
| **Client device (Mobile)** | Android Smartphone running Android 11 or higher, 4 GB RAM, Bluetooth Low Energy (BLE 4.2+), GPS, and 4G LTE / Wi-Fi | Hosted the SafeGuard Flutter companion application, maintained the background BLE connection with the wearable, and forwarded alerts to the backend. | Physical device testing on Android smartphone. |
| **Server and cloud runtime** | FastAPI (Uvicorn ASGI server) with Supabase managed PostgreSQL 15 (Free Tier, 500 MB storage, AWS cloud region) and Edge Impulse Studio cloud platform | Hosted the relational database tables, processed incident creation and live location updates, and trained the keyword spotting model in the cloud. | Supabase project configuration and Edge Impulse Studio project dashboard. |
| **Specialised hardware** | ESP32 Microcontroller Development Board (Dual-core Xtensa 32-bit LX6 at 240 MHz, 520 KB SRAM, 4 MB Flash, integrated Wi-Fi and Bluetooth BLE) with I2S digital microphone, u-blox NEO-6M GPS, and SIM800L GSM | Executed the Edge Impulse keyword spotting model on-device, read GPS coordinates, monitored the physical panic button, and transmitted BLE and SMS alerts. | Espressif ESP32 datasheet, Arduino serial monitor logs, and bench tests. |

Because the project includes an embedded wearable prototype, Table 5.2 documents each physical sensor, controller, communication module, and power component connected in the end-to-end hardware chain from input sensing to alert transmission.

**Table 5.2: IoT or embedded component evidence**

| Component | Image or model/part number | Role and connection | Key specification and justification |
| :--- | :--- | :--- | :--- |
| **Microcontroller and BLE gateway** | Espressif ESP32-WROOM-32 Development Board | Central controller that samples the microphone and panic button, runs the Edge Impulse audio model, parses GPS data, and sends BLE alerts to the phone. | 240 MHz dual-core MCU, 520 KB SRAM, 4 MB Flash, integrated BLE 4.2. Selected for sufficient RAM/Flash to run Edge Impulse C++ inference alongside BLE. |
| **Digital audio sensor (Microphone)** | INMP441 Omnidirectional I2S MEMS Microphone Module | Captures voice audio in 1-second windows at 16 kHz and sends digital PCM audio to the ESP32 over the I2S bus. | 24-bit digital I2S output, 61 dBA SNR, flat frequency response from 60 Hz to 15 kHz. Selected for low noise and direct digital connection without an external codec. |
| **Manual input device (Panic button)** | 6x6 mm Momentary Tactile Push Button Switch | Connected between GPIO pin and ground (active-low with internal pull-up resistor) to detect a 3-second hold or triple-tap SOS trigger. | Contact resistance under 100 mOhm, rated for over 100,000 presses. Provides a reliable manual trigger when the user cannot speak. |
| **Location sensor (GPS module)** | u-blox NEO-6M GPS Receiver Module with ceramic patch antenna | Connected to the ESP32 via hardware UART (9600 bps) to supply NMEA latitude and longitude coordinates. | 50-channel receiver, 2.5 m horizontal position accuracy, 3.3 V operating voltage. Selected for low power consumption and reliable outdoor satellite tracking. |
| **Cellular fallback module** | SIMCom SIM800L Quad-Band GSM/GPRS Module | Connected via UART AT command interface to send fallback emergency SMS messages and place voice calls when Bluetooth is disconnected. | Supports 850/900/1800/1900 MHz GSM bands. Ensures the wearable can still alert guardians when the companion phone is out of range. |
| **Actuator and feedback** | 3 V Mini Coin Vibration Motor and Status LED | Driven via GPIO output pin to give silent tactile vibration confirmation when an alert is triggered or cancelled. | 3.0 V rated voltage, 60 mA current draw. Provides discreet confirmation to the wearer without alerting an attacker. |
| **Power component** | 3.7 V, 500 mAh Lithium-Polymer (LiPo) rechargeable battery with TP4056 charger | Supplies portable power to the ESP32, sensors, and SIM800L module, with battery voltage monitored via an ADC pin. | 3.7 V nominal voltage, built-in overcharge and short-circuit protection. Selected for compact size and sufficient peak current capacity for GSM bursts. |

---

### 5.2.2 Software, Services and Configuration

Table 5.3 lists the software platforms, frameworks, libraries, and cloud services used to implement and run the project, together with their tested versions and roles.

**Table 5.3: Software, services and configuration**

| Software or service | Tested version | Role and configuration in the project |
| :--- | :--- | :--- |
| **Edge Impulse Studio** | Web Platform (2026 release) with EON Compiler | Used to upload the keyword spotting audio dataset, extract Mel-Frequency Cepstral Coefficient (MFCC) features, train the lightweight 1D Convolutional Neural Network (1D ConvNet), and export an open-source C++ Arduino library for the ESP32. |
| **Arduino IDE and ESP32 Core** | Arduino IDE 2.3.x with Espressif Arduino-ESP32 BSP 2.0.x | Used to write, compile, and flash the embedded C/C++ firmware and the exported Edge Impulse inference library onto the ESP32 microcontroller. |
| **TinyGPSPlus Library** | Version 1.0.3 | Parsed raw NMEA 0183 strings from the NEO-6M GPS module into decimal latitude, longitude, speed, and satellite count values. |
| **Flutter and Dart SDK** | Flutter 3.x / Dart 3.x | Used to build the cross-platform Android companion application, using `flutter_blue_plus` for BLE communication, `geolocator` for phone GPS, and `flutter_map` for live map rendering. |
| **Python and FastAPI** | Python 3.11 / FastAPI 0.115.x / Uvicorn | Implemented the REST API endpoints and WebSocket channels for user authentication, incident logging, live coordinate streaming, and alert dispatching. |
| **Supabase (PostgreSQL)** | PostgreSQL 15 | Cloud relational database configured with Row-Level Security (RLS) to store user profiles, paired wearable devices, emergency contacts, incidents, and location history. |
| **Git and GitHub** | Git 2.x | Used for source code version control, branch management, and storing configuration templates without exposing secret API keys. |

---

### 5.2.3 Deployment and Reproducibility

To reproduce and verify the complete SafeGuard prototype in a controlled test environment, the following four steps were executed:

1. **Database Setup:** The SQL migration script (`setup_supabase.sql`) was executed in the Supabase SQL Editor to create the five relational tables (`users`, `devices`, `emergency_contacts`, `incidents`, and `location_logs`) and enable Row-Level Security policies.
2. **Backend API Startup:** Python dependencies were installed from `backend/requirements.txt` inside a virtual environment, environment variables (`SUPABASE_URL` and `SUPABASE_KEY`) were configured in a local `.env` file excluded from Git, and the FastAPI server was launched using `uvicorn app.main:app --host 0.0.0.0 --port 8000`. Health verification was performed by querying the `GET /health` endpoint, which returned HTTP 200 (`{"status": "healthy"}`).
3. **Edge Impulse Model and Firmware Flashing:** The trained keyword spotting impulse was exported from Edge Impulse Studio as an Arduino `.zip` library and imported into Arduino IDE (`Sketch -> Include Library -> Add .ZIP Library`). The firmware (`gps_safety_pendant.ino`) was compiled for the ESP32 board and flashed over USB at 115200 baud.
4. **Mobile Application Installation:** The Flutter companion application (`app/`) was compiled and installed onto the Android test smartphone via USB debugging using `flutter run`, after which Bluetooth and Location permissions were granted and the phone was paired with the wearable (`SafeGuard-Pendant`).

---

## 5.3 System Implementation

The implementation was carried out across three integrated layers matching the system architecture from Chapter 4: (1) the database, backend API, and mobile application modules; (2) the Edge Impulse voice keyword spotting dataset and model; and (3) the wearable hardware and firmware integration.

### 5.3.1 Implemented Modules, Integration and User Workflows

#### Database and Data Implementation
The data design from Chapter 4 was implemented in Supabase PostgreSQL using five linked tables:
- **`users`:** Stores registered wearer accounts (`id`, `full_name`, `phone`, `email`, and `safety_pin_hash` for cancelling false alarms).
- **`devices`:** Links each physical wearable (`mac_address`, `firmware_version`, `battery_level`, `is_active`) to its owner via `user_id`.
- **`emergency_contacts`:** Stores trusted guardians (`name`, `phone_number`, `relationship`, `priority_order`) associated with each user.
- **`incidents`:** Records every emergency alert (`id`, `user_id`, `device_id`, `trigger_type` as button or voice, `status` as active, cancelled, or resolved, and timestamps).
- **`location_logs`:** Stores time-series GPS points (`incident_id`, `latitude`, `longitude`, `accuracy`, `battery_pct`, `recorded_at`) linked to an active incident.

Validation rules in the FastAPI schemas (`schemas.py`) reject invalid latitude/longitude ranges or incomplete incident payloads, while PostgreSQL Row-Level Security (RLS) restricts users and guardians to viewing only their own authorized records.

#### Application Modules and Business Rules
The software application was divided into four core modules:
1. **Authentication and Profile Module:** Handles user sign-in, emergency contact registration, and configuration of a 4-digit safety PIN.
2. **BLE Device Manager Module (`ble_service.dart`):** Scans for the wearable, maintains an automatic background connection, reads battery percentage updates, and listens for incoming `0x01` (button SOS) or `0x02` (voice SOS) notification packets.
3. **Alert Countdown and Cancellation Module (`alert_triggered_screen.dart`):** Implements the primary false-alarm business rule. When the wearable triggers an alert, the mobile application vibrates and displays a 10-second countdown timer. If the wearer enters their safety PIN before the timer reaches zero, the alert is marked as `cancelled` and a reset byte (`0x00`) is sent back to the wearable.
4. **Incident Dispatch and Live Tracking Module (`incidents.py` and `tracking_map_screen.dart`):** If the 10-second countdown expires without cancellation, the app sends a `POST /api/v1/incidents` request to the FastAPI backend. The backend records the incident in Supabase, notifies the registered emergency contacts with a tracking link, and streams live GPS coordinates over a WebSocket channel (`/ws/incidents/{incident_id}`) onto an interactive OpenStreetMap view.

#### Integration and User Workflows
In a complete end-to-end user workflow, the wearer powers on the pendant and pairs it with the SafeGuard mobile app over Bluetooth. When an emergency occurs, the wearer either presses the physical panic button for 3 seconds or speaks the wake keyword phrase clearly. The ESP32 detects the event and sends an alert notification over BLE to the smartphone, which opens the 10-second cancellation screen. Once the countdown finishes, the phone submits the incident and current GPS coordinates to the FastAPI server, stores the record in Supabase, dispatches the emergency SMS, and updates the guardian map every 5 seconds as new GPS coordinates arrive. If the phone is disconnected or powered off, the ESP32 waits 10 seconds for a BLE acknowledgement and automatically switches to its onboard SIM800L GSM module to send a fallback SMS containing a Google Maps link directly to the primary guardian.

---

### 5.3.2 Data and Model Implementation for the Voice Trigger

To enable hands-free emergency activation without writing complex custom training pipelines from scratch, the voice detection module was implemented using the **Edge Impulse Studio** web platform and its open-source Keyword Spotting dataset, following the official Edge Impulse *"Responding to your voice"* workflow.

#### Dataset Description
The model was trained using the open-source **Edge Impulse Keyword Spotting Dataset**, which combines three curated audio sources into a three-class dataset (`helloworld` target keyword phrase, `unknown` general speech, and `noise` background audio):
1. **Target Keyword Phrase (`helloworld` class):** Collected by the Edge Impulse engineering team across multiple speakers and recording environments to represent the spoken wake phrase that triggers the device.
2. **Unknown Speech (`unknown` class):** Sourced from a subset of the open-source **Google Speech Commands Dataset**, containing short spoken words (such as numbers and common commands) so that the model learns not to trigger on everyday human conversation.
3. **Background Noise (`noise` class):** Sourced from the open-source **Microsoft Scalable Noisy Speech Dataset (MS-SNSD)**, providing realistic indoor and outdoor background noise (including street noise, wind, appliances, and babble) so the microphone does not trigger in noisy environments.

Each audio record in the dataset is a 1.0-second mono WAV recording sampled at 16,000 Hz. Table 5.4 summarizes the dataset composition and the 80% training / 20% testing split managed inside Edge Impulse Studio.

**Table 5.4: Edge Impulse keyword spotting dataset summary**

| Class label | Source dataset | Description | Training samples (80%) | Testing samples (20%) | Total samples |
| :--- | :--- | :--- | :---: | :---: | :---: |
| **`helloworld` (Keyword)** | Edge Impulse Team Collection | Spoken target wake phrase used to trigger an voice alert | 400 | 100 | **500** |
| **`unknown`** | Google Speech Commands subset | Other spoken words that must be ignored during normal speech | 408 | 102 | **510** |
| **`noise`** | Microsoft Scalable Noisy Speech Dataset (MS-SNSD) | Background environmental and indoor noise with no keyword | 400 | 100 | **500** |
| **Total** | **Edge Impulse Open-Source KWS Corpus** | **Three-class audio dataset (16 kHz, 1.0 s clips)** | **1,208** | **302** | **1,510** |

#### Data Preparation and Partitioning
Inside the Edge Impulse Studio **Data Acquisition** and **Create Impulse** tabs, all uploaded audio files were automatically split into an **80% training set (1,208 clips)** and a **20% held-out test set (302 clips)**. Each 1,000 ms audio window (`16,000` samples at 16 kHz) was processed using the Edge Impulse **Audio (MFCC)** digital signal processing block. The MFCC block sliced each 1-second recording into overlapping 20 ms frames with a 20 ms frame stride, extracted **13 Mel-Frequency Cepstral Coefficients (MFCCs)** per frame using 32 Mel filterbanks (300 Hz to 8,000 Hz) and a 256-point FFT, and produced a compact **650-feature vector (50 time frames x 13 MFCCs)** for each 1-second audio clip.

#### Model Training and Selection
In the Edge Impulse **NN Classifier** tab, the default lightweight **1D Convolutional Neural Network (1D ConvNet)** architecture recommended by Edge Impulse for microcontroller keyword spotting was selected. This simple, low-footprint neural network consists of:
- **Input layer:** 650 MFCC features (reshaped into 50 time frames x 13 channels).
- **First 1D Convolution block:** 1D Convolution layer (`8 filters`, kernel size `3`, ReLU activation) followed by Max Pooling (`pool_size = 2`) and Dropout (`0.25`).
- **Second 1D Convolution block:** 1D Convolution layer (`16 filters`, kernel size `3`, ReLU activation) followed by Max Pooling (`pool_size = 2`) and Dropout (`0.25`).
- **Output layer:** Flatten layer connected to a 3-neuron Softmax classification layer (`helloworld`, `unknown`, `noise`).

The model was trained in Edge Impulse Studio for **100 training cycles (epochs)** using a learning rate of **0.005**, the Adam optimizer, categorical cross-entropy loss, and Edge Impulse's built-in **noise and frequency masking data augmentation** enabled. To ensure the model ran fast and used minimal memory on the ESP32, the **Edge Impulse EON Compiler** with **INT8 quantization** was selected during deployment export.

#### Model Evaluation and Application Testing
After training in Edge Impulse Studio, the model was evaluated on the 20% held-out test set (`302` unseen samples) using the **Model Testing** tab. Once validated, the model was exported from the **Deployment** tab as a ready-to-use **Arduino Library (`.zip`)** and included directly inside the ESP32 firmware sketch. On the device, the firmware runs continuous 1-second audio slices through `run_classifier()` and triggers an alert only when the `helloworld` keyword probability exceeds **0.80** in two consecutive windows.

---

### 5.3.3 Hardware, Firmware and Integration

#### Component Assembly and Connections
Building on Table 5.2, the wearable prototype assembled the ESP32 microcontroller with four peripheral modules on a compact prototype carrier powered by the 3.7 V, 500 mAh LiPo battery:
- **INMP441 I2S Microphone to ESP32:** Connected via digital I2S pins (`SCK` to GPIO 14, `WS` to GPIO 15, `SD` to GPIO 32, `VDD` to 3.3 V, and `GND` to Ground).
- **NEO-6M GPS Module to ESP32:** Connected via UART2 (`GPS TX` to ESP32 `RX2` GPIO 16, `GPS RX` to ESP32 `TX2` GPIO 17, `VCC` to 3.3 V).
- **SIM800L GSM Module to ESP32:** Connected via UART (`SIM800L TX` to GPIO 26, `SIM800L RX` to GPIO 27) and powered directly from the 3.7 V LiPo rail to handle cellular transmission current peaks.
- **Panic Button and Vibration Motor:** The push button was wired between GPIO 4 and Ground using the internal pull-up resistor, and the coin vibration motor was driven through GPIO 25.

#### Firmware and Data Acquisition
On startup, the ESP32 firmware initializes the serial interfaces, starts the BLE GATT server (`SafeGuard-Pendant`), configures the I2S peripheral at 16,000 Hz (16-bit mono), and loads the Edge Impulse neural network classifier. During normal operation, the firmware executes a continuous loop that:
1. Checks GPIO 4 every 20 ms with a 50 ms debounce filter to detect either a 3-second continuous button hold or a triple-tap within 1.5 seconds.
2. Reads 1-second audio buffers from the INMP441 microphone and passes them to the Edge Impulse classifier (`run_classifier`). If the target keyword score is at least `0.80` twice within 3 seconds, the voice trigger flag is raised.
3. Parses incoming NMEA sentences from the NEO-6M GPS module every 1 second using `TinyGPSPlus`, retaining the last valid latitude and longitude fix if satellite visibility temporarily drops indoors.

#### Communication and System Integration
When either the button or voice trigger activates, the ESP32 vibrates the motor for 300 ms and transmits a BLE notification packet containing the trigger code (`0x01` for button or `0x02` for voice) and the latest GPS coordinates to the paired Android phone. The phone acknowledges the packet and starts the 10-second cancellation timer before forwarding the incident to the FastAPI backend and Supabase database. If the Bluetooth connection is lost or no acknowledgement arrives from the phone within 10 seconds, the ESP32 automatically sends `AT+CMGS` commands to the SIM800L module to transmit an emergency SMS containing a Google Maps link (`https://maps.google.com/?q=lat,lng`) directly over the cellular network.

---

## 5.4 Testing and Evaluation

### 5.4.1 Test Strategy and Acceptance Criteria

Testing was planned and executed across three levels to verify that all functional and non-functional requirements from Chapter 3 were met:
1. **Unit and Model Testing:** Evaluated the Edge Impulse keyword spotting model on the held-out 20% test set in Edge Impulse Studio (`acceptance threshold: >= 85% overall accuracy and < 100 ms inference latency on ESP32`).
2. **Component and Integration Testing:** Verified individual hardware interfaces (I2S microphone capture, GPS coordinate parsing, BLE packet transmission, and FastAPI to Supabase database writes) using black-box and grey-box test inputs.
3. **End-to-End System and Exception Testing:** Tested complete emergency workflows including manual button SOS, voice keyword SOS, false-alarm PIN cancellation within 10 seconds, live map tracking, and Bluetooth-disconnected GSM fallback (`acceptance threshold: end-to-end alert delivery under 15 seconds`).

Each physical test case was repeated 5 times under controlled indoor and outdoor conditions to verify consistency.

---

### 5.4.2 Test Cases, Defects and Retesting

Table 5.5 presents the repeatable test cases, their requirement traceability, test conditions, expected results, and actual observed results.

**Table 5.5: Test cases and results**

| Test ID | Traceability | Scenario, data and conditions | Expected result | Actual result, evidence and verdict |
| :--- | :--- | :--- | :--- | :--- |
| **TC-001** | **FR-01 / Manual SOS Trigger** | Press and hold the physical panic button on the ESP32 wearable for 3.0 seconds (5 repetitions, paired via BLE at 2 m distance). | Wearable vibrates, sends BLE alert byte `0x01`, and opens the 10-second countdown screen on the mobile app within 1 second. | BLE alert received in an average of 0.3 s across all 5 runs; phone vibrated and displayed the countdown screen. **PASS** |
| **TC-002** | **FR-02 / Voice Keyword Trigger** | Speak the trained wake phrase (`"Hello World"`) 30 cm from the microphone in a quiet room (5 repetitions) and test normal non-keyword conversation. | Edge Impulse model scores >= 0.80 on the wake phrase, triggers BLE alert `0x02`, and ignores normal conversation. | Wake phrase triggered the alert in 5 out of 5 trials; normal conversation remained classified as `unknown` or `noise`. **PASS** |
| **TC-003** | **FR-03 / False-Alarm Cancellation** | Trigger an SOS alert, tap *"Cancel Alert"* on the companion phone within the 10-second window, and enter a valid 4-digit PIN (and test an invalid PIN). | Valid PIN cancels the alert, sends BLE reset (`0x00`), and stops SMS dispatch; invalid PIN is rejected and countdown continues. | Valid PIN cancelled the alert immediately with zero SMS sent; invalid PIN showed an error message as expected. **PASS** |
| **TC-004** | **FR-04 / GPS Coordinate Acquisition** | Power on the wearable outdoors under clear sky and log NMEA sentences via Arduino Serial Monitor for 3 minutes. | NEO-6M acquires a valid 3D GPS fix with horizontal accuracy within 5 meters and updates every 5 seconds. | Warm fix acquired in 3.2 s with 2.5 m to 3.8 m accuracy; coordinates streamed every 5 seconds. **PASS** |
| **TC-005** | **FR-05 / Cloud Incident and Live Map** | Allow the 10-second SOS countdown to expire without cancellation while connected to 4G/Wi-Fi. | App sends `POST /api/v1/incidents`; record is saved in Supabase `incidents` and `location_logs`; guardian map updates live. | Incident row created in Supabase; SMS alert and live OpenStreetMap marker updated within 4.1 seconds. **PASS** |
| **TC-006** | **FR-06 / Offline GSM Fallback** | Turn off Bluetooth on the smartphone and trigger a manual SOS on the wearable. | After 10 seconds with no BLE acknowledgement, the ESP32 triggers the SIM800L module to send a fallback SMS with GPS coordinates. | Fallback SMS containing Google Maps link was received on the guardian phone in 14.5 seconds. **PASS** |
| **TC-007** | **NFR-01 / Edge Inference Latency** | Run continuous 1-second audio classification on the ESP32 and record DSP + Neural Network execution time over 50 windows in Serial Monitor. | Total on-device inference time per 1-second window must be under 100 ms, using less than 50% of ESP32 RAM. | Measured DSP (MFCC) time was 16 ms and NN classification time was 12 ms (28 ms total), using 14.6 KB RAM. **PASS** |

#### Defects Encountered and Retesting
During initial testing, two defects were identified, corrected, and retested:
1. **DEF-01 (Single-Window Voice False Triggers):** During initial testing of `TC-002`, coughing or speaking words with similar vowel sounds occasionally produced a single-window confidence spike above `0.70`, causing an unintended alert. **Fix:** The confidence threshold in the ESP32 firmware was raised to `0.80` and a two-window confirmation rule (requiring two detections within 3 seconds) was added. **Retest outcome:** Passed with zero false triggers during 15 minutes of normal conversation.
2. **DEF-02 (SIM800L Brownout Reset During GSM Transmission):** During initial testing of `TC-006`, the SIM800L module reset when attempting to join the cellular network because it was initially wired to the ESP32's regulated 3.3 V pin, which could not supply the 2 A current burst. **Fix:** The SIM800L `VCC` pin was rewired directly to the 3.7 V LiPo battery terminal with a 470 uF decoupling capacitor. **Retest outcome:** Passed across 5 consecutive fallback SMS tests without resetting.

---

### 5.4.3 Project-Type-Specific Evaluation

Because SafeGuard combines an Edge AI keyword spotting model with an IoT wearable and mobile app, evaluation covered both the Edge Impulse model metrics and the embedded hardware performance:

#### Edge Impulse Model Evaluation (Validation and Held-Out Test Set)
Table 5.6 compares the Edge Impulse 1D ConvNet model performance on the validation set (`20%` internal split during training) and the held-out test set (`302` samples) inside Edge Impulse Studio, alongside the on-device resource usage estimated by the EON Compiler.

**Table 5.6: Edge Impulse 1D ConvNet performance and on-device resource usage**

| Evaluation metric | Validation set result | Held-out test set result (`N = 302`) | Target requirement |
| :--- | :---: | :---: | :---: |
| **Overall Classification Accuracy** | 93.8% | **91.7%** | >= 85.0% |
| **`helloworld` Keyword Recall (Sensitivity)** | 94.0% | **92.0%** | >= 85.0% |
| **`helloworld` Keyword Precision** | 92.2% | **90.2%** | >= 85.0% |
| **`unknown` Speech Recall** | 92.5% | **90.2%** | >= 85.0% |
| **`noise` Background Recall** | 95.0% | **93.0%** | >= 90.0% |
| **Macro F1-Score** | 0.94 | **0.92** | >= 0.85 |
| **On-Device DSP + Inference Latency (ESP32)** | 28 ms (16 ms MFCC + 12 ms NN) | **28 ms** | <= 100 ms |
| **Peak RAM Usage (EON Compiler INT8)** | 14.6 KB | **14.6 KB** (2.8% of 520 KB SRAM) | <= 64 KB |
| **Flash Memory Usage (EON Compiler INT8)** | 35.2 KB | **35.2 KB** (0.9% of 4 MB Flash) | <= 200 KB |

Table 5.7 shows the confusion matrix recorded in Edge Impulse Studio across the three classes on the held-out test set (`302` samples).

**Table 5.7: Edge Impulse test set confusion matrix (`N = 302`)**

| Actual / Predicted | Predicted `helloworld` | Predicted `unknown` | Predicted `noise` | Total actual | Class recall |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Actual `helloworld`** | **92** | 6 | 2 | 100 | **92.0%** |
| **Actual `unknown`** | 8 | **92** | 2 | 102 | **90.2%** |
| **Actual `noise`** | 2 | 5 | **93** | 100 | **93.0%** |

---

### 5.4.4 Results Presentation and Interpretation

The results in Table 5.5, Table 5.6, and Table 5.7 demonstrate three key findings:
1. **High Keyword Recognition Accuracy with Minimal Compute:** Using Edge Impulse's MFCC preprocessing block (`13` coefficients) and a lightweight 2-layer 1D ConvNet achieved **91.7% overall test accuracy** and **92.0% recall** on the target keyword phrase while requiring only **14.6 KB of RAM**, **35.2 KB of Flash**, and **28 ms of processing time** on the ESP32. This leaves more than 95% of the ESP32's memory available for Bluetooth Low Energy, GPS parsing, and GSM communication.
2. **Strong Rejection of Street Noise and Normal Speech:** Including the Microsoft Scalable Noisy Speech Dataset (`noise`) and Google Speech Commands (`unknown`) during training allowed the model to correctly reject **93.0% of background noise clips** and **90.2% of non-keyword spoken words**. The remaining 8% to 10% single-window false positives (`8` `unknown` clips and `2` `noise` clips predicted as `helloworld`) were effectively filtered out during live operation by the two-window confirmation rule (`DEF-01`) and the 10-second mobile cancellation screen (`TC-003`).
3. **Fast End-to-End Emergency Delivery:** Across 5 repeated trials (`TC-001` to `TC-006`), BLE alert transmission from the wearable to the phone took **0.3 seconds**, cloud incident logging and SMS notification via the companion phone took **4.1 seconds** after the countdown, and direct SIM800L GSM fallback took **14.5 seconds** when the phone was disconnected.

---

## 5.5 Version Control and Implementation Evidence

All source code, firmware sketches, database migration scripts, and documentation for the project were maintained under Git version control in a structured GitHub repository:

- **Project Repository:** `gps-safety-wearable` (organised into `/firmware` for the ESP32 Arduino sketch, `/app` for the Flutter mobile application, `/backend` for the FastAPI REST and WebSocket server, and `/docs` for database schemas and architecture documentation).
- **Reproducibility and Configuration Files:** The repository includes a root `README.md` with step-by-step setup instructions, `setup_supabase.sql` for reproducing the PostgreSQL schema, `backend/requirements.txt` for Python dependencies, and `app/pubspec.yaml` for Flutter package versions.
- **Credential Hygiene:** A `.gitignore` file was configured to exclude `.env` environment files, Supabase service keys, build directories (`/build`, `__pycache__`, `.dart_tool`), and personal phone numbers from version control. A sanitized `.env.example` template is provided so authorized evaluators can supply their own credentials safely.

---

## 5.6 Author Oversight and Use of AI-Assisted Tools

In accordance with departmental guidelines on academic integrity and transparency, AI-assisted coding and writing tools (including Google Gemini / Antigravity and Edge Impulse Studio's automated EON Compiler) were used during the implementation and documentation phases of this project. Specifically, Edge Impulse Studio automated the MFCC extraction, neural network quantization, and C++ library generation from the uploaded dataset, while AI coding assistance was used to help debug Flutter BLE state management, refine FastAPI Pydantic validation schemas, and improve the clarity and formatting of this report. All generated code, database queries, firmware logic, and written explanations were manually reviewed, tested on the physical ESP32 and Android hardware, and verified against the project requirements by the author, who takes full responsibility for the submitted work.

---

## 5.7 Evaluation Results, Discussion and Limitations

### Evaluation Against Project Objectives
Table 5.8 maps the implemented outputs and measured test results directly against the research objectives of the study.

**Table 5.8: Summary evaluation against project objectives**

| Research objective | Implemented output and evidence | Acceptance criterion | Observed result | Conclusion |
| :--- | :--- | :--- | :--- | :--- |
| **Objective 1: Design and build a discreet wearable emergency trigger with GPS tracking** | Assembled ESP32 wearable prototype with physical panic button, INMP441 microphone, NEO-6M GPS, and BLE service (`Table 5.2`, `TC-001`, `TC-004`). | Detect button trigger in < 1 s and acquire GPS coordinates within 5 m outdoor accuracy. | Button trigger delivered via BLE in 0.3 s; GPS accuracy measured at 2.5 m to 3.8 m outdoors. | **Objective achieved** |
| **Objective 2: Implement an on-device voice keyword spotting model for hands-free activation** | Trained 1D ConvNet in Edge Impulse Studio on the open-source KWS dataset (`helloworld`, `unknown`, `noise`) and deployed as an INT8 Arduino library (`Table 5.6`, `TC-002`, `TC-007`). | Achieve >= 85% test accuracy and < 100 ms inference time on the microcontroller. | Achieved **91.7% test accuracy** (`92.0%` keyword recall) and **28 ms** total latency in 14.6 KB RAM. | **Objective achieved** |
| **Objective 3: Develop a companion mobile app and cloud backend with false-alarm prevention** | Implemented Flutter Android app (`10 s` PIN cancellation screen, live map) and FastAPI + Supabase backend (`TC-003`, `TC-005`). | Allow cancellation of accidental triggers within 10 s and log active incidents in < 5 s. | 10-second PIN cancellation prevented 100% of test false alarms; cloud incident logged in 4.1 s. | **Objective achieved** |
| **Objective 4: Provide an independent communication fallback when the phone is unreachable** | Integrated SIM800L GSM module on the wearable with automatic 10-second BLE timeout failover (`TC-006`). | Automatically send fallback SMS with GPS link within 20 s of BLE timeout. | Fallback SMS with Google Maps coordinate link delivered in 14.5 s after timeout. | **Objective achieved** |

### Discussion of Findings
The evaluation results confirm that combining an edge-deployed keyword spotting model with a dual-path communication architecture (Bluetooth Low Energy to the companion smartphone, backed up by direct SIM800L GSM SMS) overcomes the primary weaknesses of existing personal safety products reviewed in Chapter 2. Smartphone-only SOS apps fail when the user cannot reach their phone during an attack, whereas cloud-based voice assistants require continuous internet streaming and high battery power. By using Edge Impulse Studio's MFCC + 1D ConvNet pipeline, all voice processing happens locally on the ESP32 in `28 ms` without sending private audio to the cloud. Furthermore, pairing the two-window voice confirmation rule on the microcontroller with the 10-second PIN cancellation countdown on the mobile app effectively resolves the trade-off between high emergency sensitivity (`92.0%` keyword recall) and false-alarm prevention.

### Limitations of the Current Study
Despite meeting all prototype acceptance criteria, four practical limitations were identified during evaluation:
1. **Single Wake-Phrase Vocabulary:** Because the model was trained on the open-source Edge Impulse `"Hello World"` dataset (`1,510` clips) rather than a custom multi-language dataset of local Kenyan distress cries (such as *"Help"* or *"Msaada"*), the current prototype only responds to the trained wake phrase. Retraining the same Edge Impulse pipeline with locally recorded Kiswahili and English distress phrases is required before public field deployment.
2. **High-Noise and Far-Field Microphone Sensitivity:** While the model achieved `93.0%` noise recall on the MS-SNSD test set and performed reliably when spoken within 30 to 50 cm of the pendant in quiet or moderate noise, very loud environments (such as heavy traffic or loud music) reduce voice recognition accuracy, requiring the user to rely on the physical panic button.
3. **Indoor GPS Cold-Start Delay:** The u-blox NEO-6M GPS module acquires a warm outdoor satellite fix in `3.2 seconds`, but a cold start inside a concrete building can take 30 to 45 seconds. When an alert is triggered indoors before a satellite fix is obtained, the system relies on the last cached GPS fix or the companion smartphone's network location.
4. **Breadboard/Module Prototype Size:** Using off-the-shelf development modules (ESP32 board, NEO-6M breakout, SIM800L module, and 500 mAh LiPo battery) produced a working proof-of-concept unit, but its physical enclosure is larger than commercial jewellery. Miniaturizing the hardware into a true locket or bracelet requires designing a custom printed circuit board (PCB) in future work, as discussed in Chapter 6.
