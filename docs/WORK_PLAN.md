# SafeGuard GPS Safety Wearable — 3-Week Master Execution Plan
**Author:** Joy Kipkemboi — Strathmore University  
**Goal:** Complete, test, and present a functional smart jewellery safety wearable, companion mobile app, cloud backend with 3D Mapbox live tracking, and custom PCB.

---

## 📅 High-Level 3-Week Timeline

```
Week 1: Breadboard Wiring + Real Hardware Verification + TinyML Wake-Words
Week 2: Backend Cloud Deployment + 3D Mapbox Live Demo + PCB Design (No Fear!)
Week 3: Hardware Enclosure (Pendant Casing) + Mobile App Final Integration + Project Presentation & Thesis
```

---

## 🛠️ Phase 1: Week 1 — Breadboard Assembly & Live Testing

### 1.1 Breadboard Power & Safety Check (Day 1)
- [ ] Place **ESP32-C3 Super Mini** straddling the centre trough of your breadboard.
- [ ] Connect ESP32 `3V3` to the Red (+) Rail, and `GND` to the Blue (−) Rail.
- [ ] Connect your **2 × 470µF capacitors** in parallel directly across the breadboard rows feeding the **SIM800L VCC and GND**. *(Crucial to absorb the 2A cellular transmit bursts!)*
- [ ] Insert the **1 kΩ + 330 Ω voltage divider** between ESP32 `GPIO 5` and SIM800L `RX` to safely drop 3.3V logic to 2.8V.

### 1.2 Peripheral Connections (Day 2)
- [ ] **TTP223B Touch Sensor:**
  - `VCC` $\rightarrow$ 3V3 Rail
  - `GND` $\rightarrow$ GND Rail
  - `SIG` $\rightarrow$ ESP32 `GPIO 2`
- [ ] **GY-NEO6MV2 GPS:**
  - `VCC` $\rightarrow$ 3V3 Rail
  - `GND` $\rightarrow$ GND Rail
  - `TX` $\rightarrow$ ESP32 `GPIO 6`
  - `RX` $\rightarrow$ ESP32 `GPIO 7`
- [ ] **Mini Speaker (or Buzzer):**
  - Connect via the **22 Ω current-limiting resistor** to ESP32 `GPIO 8`.
- [ ] **Microphone (Electret Capsule):**
  - Connect with **10 kΩ pull-up bias resistor** to `3V3` and `GPIO 1` (ADC).

### 1.3 Live Hardware Smoke Test (Day 3)
- [ ] Insert an active Safaricom micro-SIM card (with airtime and data) into SIM800L.
- [ ] Flash [`firmware/gps_safety_pendant/gps_safety_pendant.ino`](file:///c:/Users/joych/gps-safety-wearable/firmware/gps_safety_pendant/gps_safety_pendant.ino) using Arduino IDE.
- [ ] Open the Serial Monitor at `115200 baud`.
- [ ] Double-tap the TTP223B touch sensor and verify:
  1. Serial prints countdown window.
  2. GPS acquires satellite fix (or falls back to Nairobi default indoors).
  3. Real SMS arrives on your personal phone with the 3D Mapbox live link!

### 1.4 Train the TinyML Micro Keyword Spotter (Day 4–5)
- [ ] Run [`ml/keyword_detection/record_phrases.py`](file:///c:/Users/joych/gps-safety-wearable/ml/keyword_detection/record_phrases.py) on your computer.
- [ ] Record 15–20 short audio samples for:
  - `"tuma msaada"` *(Kiswahili: Send help)*
  - `"send help"` *(English: Send help)*
  - `"piga polisi"` *(Kiswahili: Call police)*
  - `"call police"` *(English: Call police)*
- [ ] Open [`04_train_esp32_micro_model.ipynb`](file:///c:/Users/joych/gps-safety-wearable/ml/keyword_detection/notebooks/04_train_esp32_micro_model.ipynb) on Google Colab (free T4 GPU).
- [ ] Run the cells to train the ~30 KB INT8 quantized model.
- [ ] Download the generated `safeguard_micro_model.h` and copy it to [`firmware/gps_safety_pendant/`](file:///c:/Users/joych/gps-safety-wearable/firmware/gps_safety_pendant/).

---

## 🚀 Phase 2: Week 2 — Backend Deployment & PCB Design (Demystified)

### 2.1 Deploy Backend for a Permanent URL (Day 6–7)
- [ ] Deploy the FastAPI backend to **Render.com** (Free Web Service tier):
  - Connect your GitHub repository.
  - Set Build Command: `pip install -r backend/requirements.txt`
  - Set Start Command: `uvicorn backend.app.main:app --host 0.0.0.0 --port 8000`
  - Add your environment variables (`SUPABASE_URL`, `MAPBOX_WEB_TOKEN`, `AFRICAS_TALKING_API_KEY`).
- [ ] You now have a **permanent, fixed HTTPS URL** (e.g., `https://safeguard-api.onrender.com`).
- [ ] No more ngrok links changing every time!

### 2.2 PCB Design Made Easy (Day 8–10)
> [!NOTE]
> **Why PCB is not scary:** You do NOT need to design complex multi-layer microchip circuit boards from scratch! In modern embedded engineering, you create a **carrier / breakout motherboard** that holds the header sockets for your modular chips.

#### The Safe, Low-Risk PCB Strategy:
1. **Tool:** Use **EasyEDA** (browser-based, drag-and-drop, connects directly to JLCPCB) or **KiCad** (in [`hardware/kicad/`](file:///c:/Users/joych/gps-safety-wearable/hardware/kicad/)).
2. **Components to place on the board:**
   - 2 × Female header rows for **ESP32-C3 Super Mini** (so you can plug and unplug it).
   - 1 × Header for **SIM800L V2**.
   - 1 × Header for **GY-NEO6MV2 GPS**.
   - Footprints for:
     - 2 × Electrolytic capacitors (470µF)
     - 3 × Resistors (1kΩ, 330Ω, 22Ω, 10kΩ)
     - JST 2-pin connector for 3.7V LiPo battery
3. **Double-layer routing:** Simply connect the traces following your breadboard connections.
4. **Backup Option (0% Fear, 100% University Accepted):**
   - If PCB shipping takes longer than 2 weeks, solder the modules onto a standard **perfboard / stripboard (prototyping board)** cut to the size of a jewellery pendant box. Strathmore panels and evaluators happily accept neat perfboards as prototype revisions!

---

## 🎨 Phase 3: Week 3 — Enclosure, App Final Polish & Defense Prep

### 3.1 Pendant Enclosure & Form Factor (Day 11–13)
- [ ] Measure physical dimensions of the assembled board + LiPo battery.
- [ ] House components in a jewellery pendant casing:
  - 3D print a sleek pebble or medallion case (using campus 3D printer), OR
  - Adapt a stylish jewellery pillbox / pendant locket casing with a cutout for the gold TTP223B touch area.
- [ ] Ensure the coin vibration motor is glued flush against the inside wall so vibrations transfer directly to the wearer's skin.

### 3.2 Mobile App & Final Integration (Day 14–16)
- [ ] Run Flutter app with the permanent Render backend URL.
- [ ] Test the full alert flow:
  1. Double-tap pendant.
  2. Mobile app updates panic status in real time via Supabase stream.
  3. Africa's Talking dispatches SMS to emergency contacts.
  4. Recipient opens the live 3D Mapbox tracking link in their browser and sees the real-time distress beacon.
  5. Recipient calls the pendant $\rightarrow$ pendant vibrates silently $\rightarrow$ auto-answers into acoustic listening mode.

### 3.3 Project Presentation & Thesis Report (Day 17–21)
- [ ] Record a 2-minute high-quality video demo showing the pendant trigger, SMS arrival, and 3D map opening.
- [ ] Complete the final thesis write-up using the architecture and trade-off points documented here.
- [ ] Rehearse your presentation and graduate with flying colors!

---

## 📋 Comprehensive Pin & Component Master Checklist

| Component | Pin / Terminal | Connects To | Component Value / Protection |
| :--- | :--- | :--- | :--- |
| **Power Distribution** | `3V3` | Breadboard Red (+) Rail | Clean 3.3V power |
| | `GND` | Breadboard Blue (−) Rail | System common ground |
| **SIM800L V2** | `VCC` / `GND` | Red (+) / Blue (−) Rails | **2 × 470µF capacitors** in parallel across pins |
| | `TX` | ESP32-C3 `GPIO 4` | Direct connection (2.8V $\rightarrow$ 3.3V safe) |
| | `RX` | Resistor Node A | **1 kΩ** to GPIO 5, **330 Ω** to GND |
| **GPS (NEO-6M)** | `VCC` / `GND` | Red (+) / Blue (−) Rails | Direct connection |
| | `TX` / `RX` | ESP32 `GPIO 6` / `GPIO 7` | Direct connection |
| **Touch (TTP223B)** | `VCC` / `GND` / `SIG` | Red (+) / Blue (−) / `GPIO 2` | Active-HIGH digital wake trigger |
| **Mini Speaker** | (+) / (−) | ESP32 `GPIO 8` / Blue (−) Rail | **22 Ω series resistor** |
| **Electret Mic** | (+) / (−) | Resistor Node B / Blue (−) Rail | **10 kΩ pull-up resistor** to 3V3, wire to `GPIO 1` |
| **Vibration Motor** | (+) / (−) | 3V3 / NPN Collector | Driven via 2N2222 transistor on `GPIO 9` |
