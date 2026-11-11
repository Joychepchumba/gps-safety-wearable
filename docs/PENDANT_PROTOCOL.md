# SafeLink Pendant ⇄ App Protocol (v2.1)

This document is the single source of truth for how the SafeLink app talks to the
pendant (ESP32-C3 + SIM800L + NEO-6M) and how nearby phones detect an SOS over
Bluetooth Low Energy (BLE).

## 1. Owner modes

| Mode    | Touch SOS on pendant | Long-hold on pendant              | Who controls it                       |
|---------|----------------------|-----------------------------------|---------------------------------------|
| `adult` | Enabled (double-tap or hold) | Hold = SOS                | The wearer (app + pendant)            |
| `child` | **Disabled** (no accidental SOS) | Hold 3 s = **call parent** (dials guardian 1) | Parent/guardian only (app, PIN-protected) |

In both modes the guardian can remotely: **Locate**, **Call** the pendant (auto-answer
for guardians in child mode), ask the pendant to **call back**, **Find** (LED strobe),
trigger a **remote SOS**, and query **status**.

## 2. BLE GATT (pendant = peripheral, advertises as `SafeGuard`)

Service `0000ffe0-0000-1000-8000-00805f9b34fb`

| Char   | UUID                                   | Props          | Purpose |
|--------|----------------------------------------|----------------|---------|
| Alert  | `0000ffe1-0000-1000-8000-00805f9b34fb` | read, notify   | 1-byte event code (see below) |
| Config | `0000ffe2-0000-1000-8000-00805f9b34fb` | write, read    | App → pendant text commands |
| Status | `0000ffe3-0000-1000-8000-00805f9b34fb` | read, notify   | Pendant → app JSON status / replies |

### 2.1 Alert codes (ffe1 notify)

| Code   | Meaning |
|--------|---------|
| `0x01` | Touch SOS confirmed on pendant (adult mode) |
| `0x02` | Voice / acoustic SOS on pendant |
| `0x03` | Remote SOS started by guardian (SMS or BLE) |
| `0x10` | Child pressed "call parent" (hold 3 s in child mode) |
| `0x00` | SOS cancelled / idle |

### 2.2 Config writes (ffe2, UTF-8 text)

Existing (unchanged): `LOC:<lat>,<lon>` · `URL:<backend>` · `USER:<uuid>,<email>` · `<p1>,<p2>,<p3>` (contacts CSV)

New in v2.1:

| Command                 | Effect |
|-------------------------|--------|
| `MODE:CHILD` / `MODE:ADULT` | Persist owner mode |
| `TOUCH:ON` / `TOUCH:OFF`    | Enable/disable touch SOS (ignored → always OFF in child mode) |
| `HOLD:<ms>`             | Hold-to-panic duration, 1000–10000 ms |
| `GUARD:<p1>,<p2>`       | Guardian numbers authorised for SMS commands + auto-answer |
| `PIN:<4-8 digits>`      | Guardian PIN for SMS commands |
| `CMD:LOCATE`            | Resolve location, reply on ffe3 with a `loc` JSON |
| `CMD:STATUS`            | Reply on ffe3 with a `status` JSON |
| `CMD:SOS`               | Remote SOS (`sendLocationAlert`, reason `remote_guardian`) |
| `CMD:CANCEL`            | Cancel SOS beacon, alert char back to `0x00` |
| `CMD:FIND`              | Strobe LED ~10 s so the pendant can be found |
| `CMD:CALL:<number>`     | Pendant dials `<number>` (parent listen-in / talk) |
| `CMD:HANGUP`            | Hang up active call |

### 2.3 Status JSON (ffe3 notify, compact keys, < 180 bytes)

```json
{"t":"status","mode":"child","touch":0,"hold":3000,"bat":78,"mv":3912,"gsm":1,"sig":18,"fw":"2.1.0","sos":0}
{"t":"loc","lat":"-1.309250","lon":"36.812720","src":"GPS"}
{"t":"ack","cmd":"FIND"}
```

## 3. SMS commands (remote, via the pendant SIM)

Accepted only from guardian numbers (last 9 digits compared) **and** with the PIN.
Case-insensitive. The pendant replies by SMS to the sender.

| SMS                         | Effect / reply |
|-----------------------------|----------------|
| `SL LOCATE <pin>`           | Reply: `SafeLink: <lat>,<lon> (<src>) https://maps.google.com/?q=<lat>,<lon> Bat <n>%` |
| `SL CALL <pin>`             | Pendant calls the sender back |
| `SL SOS <pin>`              | Full SOS (SMS to contacts + BLE SOS beacon) |
| `SL CANCEL <pin>`           | Stop SOS beacon |
| `SL MODE CHILD <pin>` / `SL MODE ADULT <pin>` | Change owner mode |
| `SL TOUCH ON <pin>` / `SL TOUCH OFF <pin>` | Toggle touch SOS |
| `SL STATUS <pin>`           | Reply with mode / touch / battery / signal |

Incoming **voice call** from a guardian while in child mode → pendant auto-answers after 2 rings.

## 4. BLE SOS beacon (community responders, works offline)

During an SOS both the **pendant** and the **victim's phone** broadcast a BLE
advertisement that any SafeLink phone in range (~30–80 m) can pick up without
internet. Responder phones scan for it continuously.

Manufacturer Specific Data, company ID `0xFFFF` (test ID), 15-byte payload:

| Offset | Size | Field |
|--------|------|-------|
| 0      | 2    | Magic `0x53 0x4C` (`"SL"`) |
| 2      | 1    | Source: `0x01` pendant, `0x02` phone |
| 3      | 4    | Latitude × 1e6, int32 little-endian |
| 7      | 4    | Longitude × 1e6, int32 little-endian |
| 11     | 4    | User tag = first 8 hex chars of the user UUID, uint32 little-endian |

The pendant beacon runs for 30 minutes after SOS or until `CMD:CANCEL` / `SL CANCEL`.
Primary advertisement = flags + MSD + 16-bit service UUID `0xFFE0` (fits in 31 bytes);
the device name goes in the scan response.

