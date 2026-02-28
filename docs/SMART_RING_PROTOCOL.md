# Smart Ring BLE Protocol Reference

This document describes the complete BLE communication protocol for the Lumie Smart Ring (X6B). It covers every command, the exact byte layout of every request and response, and step-by-step parsing instructions derived from working implementation code.

---

## Table of Contents

1. [BLE Connection Details](#1-ble-connection-details)
2. [Encoding Conventions](#2-encoding-conventions)
   - [Packet Framing & CRC](#21-packet-framing--crc)
   - [BCD Encoding](#22-bcd-encoding)
   - [Little-Endian Integers](#23-little-endian-integers)
   - [IEEE 754 Float32 Little-Endian](#24-ieee-754-float32-little-endian)
   - [Timestamps](#25-timestamps)
3. [Multi-Record Response Framing](#3-multi-record-response-framing)
4. [Command & Response Reference](#4-command--response-reference)
   - [0x01 — Set Time](#0x01--set-time)
   - [0x41 — Get Time](#0x41--get-time)
   - [0x02 — Set User Info](#0x02--set-user-info)
   - [0x42 — Get User Info](#0x42--get-user-info)
   - [0x05 — Set Ring ID](#0x05--set-ring-id)
   - [0x12 — Factory Reset](#0x12--factory-reset)
   - [0x2E — MCU Soft Reset](#0x2e--mcu-soft-reset)
   - [0x13 — Get Battery Level](#0x13--get-battery-level)
   - [0x14 — Get Ring Temperature (real-time)](#0x14--get-ring-temperature-real-time)
   - [0x22 — Get MAC Address](#0x22--get-mac-address)
   - [0x27 — Get Firmware Version](#0x27--get-firmware-version)
   - [0x09 — Real-time Streaming Mode](#0x09--real-time-streaming-mode)
   - [0x18 — Live Exercise Push Packet](#0x18--live-exercise-push-packet)
   - [0x19 — Exercise Mode Control](#0x19--exercise-mode-control)
   - [0x28 — Multi-Parameter Measurement](#0x28--multi-parameter-measurement)
   - [0x2A — Set Measurement Interval Schedule](#0x2a--set-measurement-interval-schedule)
   - [0x2B — Get Measurement Interval Schedule](#0x2b--get-measurement-interval-schedule)
   - [0x51 — Get Total Step Count History](#0x51--get-total-step-count-history)
   - [0x52 — Get Detailed Step Count History](#0x52--get-detailed-step-count-history)
   - [0x53 — Get Sleep History](#0x53--get-sleep-history)
   - [0x54 — Get Detailed Heart Rate History](#0x54--get-detailed-heart-rate-history)
   - [0x55 — Get Heart Rate History](#0x55--get-heart-rate-history)
   - [0x56 — Get HRV / Stress / BP History](#0x56--get-hrv--stress--bp-history)
   - [0x5C — Get Exercise Mode History](#0x5c--get-exercise-mode-history)
   - [0x62 — Get Temperature History](#0x62--get-temperature-history)
   - [0x66 — Get Blood Oxygen History](#0x66--get-blood-oxygen-history)
5. [Error Response Codes Summary](#5-error-response-codes-summary)
6. [Exercise Type Codes](#6-exercise-type-codes)

---

## 1. BLE Connection Details

| Property | Value |
|----------|-------|
| GATT Service UUID | `0000fff0-0000-1000-8000-00805f9b34fb` |
| Write Characteristic UUID | `0000fff6-0000-1000-8000-00805f9b34fb` |
| Notify Characteristic UUID | `0000fff7-0000-1000-8000-00805f9b34fb` |
| Max BLE packet (MTU) | 244 bytes (`0xF4`) |

**Workflow:**
1. Connect to the device and discover GATT services.
2. Match service containing UUID fragment `fff0`.
3. Enable notifications on the characteristic containing `fff7`.
4. Write commands to the characteristic containing `fff6` (write-with-response).
5. All responses arrive as notify callbacks on `fff7`.

---

## 2. Encoding Conventions

### 2.1 Packet Framing & CRC

All **command packets** are exactly **16 bytes**:

```
Byte[0]      : Command byte (0x00–0x7F)
Byte[1..14]  : Payload (14 bytes, unused bytes = 0x00)
Byte[15]     : CRC = (Byte[0] + Byte[1] + ... + Byte[14]) & 0xFF
```

All **simple response packets** (commands 0x01, 0x02, 0x09 ACK, 0x13, 0x14, 0x19, 0x22, 0x27, 0x28, 0x2A, 0x41, 0x42) are also 16 bytes with the same CRC formula.

**Variable-length historical data responses** (0x51–0x56, 0x5C, 0x62, 0x66) carry **no CRC** at the packet level. Individual records are parsed by fixed size (see each command section). The stream ends with a 2-byte end-of-data marker: `CMD 0xFF` (e.g., `0x56 0xFF`).

**Error responses** set bit 7 of the command byte: e.g., failure for `0x13` returns `0x93`.

### 2.2 BCD Encoding

Binary Coded Decimal stores each decimal digit in a nibble:

```
BCD byte → decimal:  ((byte >> 4) * 10) + (byte & 0x0F)
decimal → BCD byte:  ((value / 10) << 4) | (value % 10)

Examples:
  0x25  →  25
  0x59  →  59
  0x23  →  23
```

All timestamp fields in responses use BCD unless stated otherwise.
All version and firmware date fields use BCD.
Battery voltage fields use BCD.

### 2.3 Little-Endian Integers

Multi-byte integers are little-endian (least significant byte first):

```
2-byte LE:  value = Byte[0] | (Byte[1] << 8)
4-byte LE:  value = Byte[0] | (Byte[1] << 8) | (Byte[2] << 16) | (Byte[3] << 24)
```

### 2.4 IEEE 754 Float32 Little-Endian

Some fields in exercise records use 32-bit IEEE 754 floats stored little-endian:

```
float = Float32.fromBytes([Byte[0], Byte[1], Byte[2], Byte[3]], endian: little)
```

Used in: `0x5C` (calories, distance), `0x18` (calories, distance).

### 2.5 Timestamps

All timestamps follow the pattern:

```
Byte[n+0] = YY  (BCD, year offset from 2000: e.g., 0x25 → 2025)
Byte[n+1] = MM  (BCD, 1–12)
Byte[n+2] = DD  (BCD, 1–31)
Byte[n+3] = HH  (BCD, 0–23)
Byte[n+4] = mm  (BCD, 0–59)
Byte[n+5] = SS  (BCD, 0–59)
```

Full year = 2000 + BCD_decode(YY).

---

## 3. Multi-Record Response Framing

Historical data commands (0x51–0x56, 0x62, 0x66) send multiple records as one or more BLE notifications. Notifications can contain any number of concatenated records (limited by MTU = 244 bytes). Records must be extracted by fixed record size.

**Parsing algorithm for variable-length responses:**

```
1. Collect all notify callbacks for a command until:
   a. A 2-byte end marker is received: [CMD 0xFF]
   b. OR an inactivity timeout fires (5 seconds recommended)

2. Concatenate all received bytes into one buffer.

3. Scan the buffer with offset i = 0:
   while (i + RECORD_SIZE <= buffer.length):
     if (buffer[i] == CMD):
       parse record at buffer[i .. i+RECORD_SIZE-1]
       i += RECORD_SIZE
     else:
       i++   // re-sync
```

**Record sizes by command:**

| Command | Record size | Notes |
|---------|-------------|-------|
| 0x51 | 27 bytes | Fixed |
| 0x52 | 25 bytes | Fixed |
| 0x53 | 10 + N bytes | N = Byte[9], range 1–120. Many firmwares pad to 130 total. |
| 0x54 | 21 bytes | Fixed (9 header + 15 HR values - 3 byte overlap... see section) |
| 0x55 | 10 bytes | Fixed |
| 0x56 | 15 bytes | Fixed |
| 0x5C | 27 bytes | Fixed, with per-record CRC at Byte[26] |
| 0x62 | 15 bytes | Fixed |
| 0x66 | 10 bytes | Fixed |

**For 0x5C only**, each 27-byte record has its own CRC:
```
CRC = (Byte[0] + Byte[1] + ... + Byte[25]) & 0xFF
Stored at Byte[26]
```

---

## 4. Command & Response Reference

---

### 0x01 — Set Time

**Purpose:** Write the current time from app to ring.

**Command (16 bytes):**

```
Byte[0]  = 0x01
Byte[1]  = YY   (decimal, 0–99, year = 2000 + YY)
Byte[2]  = MM   (decimal, 1–12)
Byte[3]  = DD   (decimal, 1–31)
Byte[4]  = HH   (decimal, 0–23)
Byte[5]  = mm   (decimal, 0–59)
Byte[6]  = SS   (decimal, 0–59)
Byte[7..14] = 0x00
Byte[15] = CRC

Note: Time fields are plain decimal (NOT BCD) for this command only.
```

**Example command:**
```
01 25 02 27 14 30 00 00 00 00 00 00 00 00 00 58
   ↑  ↑  ↑  ↑  ↑
   25=2025, 02=Feb, 27=day, 14=hour, 30=min
```

**Success response (16 bytes):**
```
Byte[0]  = 0x01
Byte[1]  = 0xF4   (max BLE MTU = 244 bytes)
Byte[2..14] = 0x00
Byte[15] = CRC
```

**Failure response:**
```
Byte[0]  = 0x81
Byte[1..14] = 0x00
Byte[15] = CRC
```

**Parse steps:**
1. Check `Byte[0] == 0x01` → success. `Byte[0] == 0x81` → failure.
2. `Byte[1]` = max MTU for reference.

---

### 0x41 — Get Time

**Purpose:** Read current time from ring.

**Command (16 bytes):**
```
Byte[0]  = 0x41
Byte[1..14] = 0x00
Byte[15] = CRC  (= 0x41)
```

**Success response (16 bytes):**
```
Byte[0]  = 0x41
Byte[1]  = YY   (BCD, year offset)
Byte[2]  = MM   (BCD)
Byte[3]  = DD   (BCD)
Byte[4]  = HH   (BCD)
Byte[5]  = mm   (BCD)
Byte[6]  = SS   (BCD)
Byte[7]  = WW   (weekday: 1=Mon, 7=Sun — unreliable, ignore)
Byte[8]  = 0xF4 (max MTU)
Byte[9..14] = 0x00
Byte[15] = CRC
```

**Failure response:** `0xC1 00 00 ... CRC`

**Parse steps:**
```
year   = 2000 + bcd(Byte[1])
month  = bcd(Byte[2])
day    = bcd(Byte[3])
hour   = bcd(Byte[4])
minute = bcd(Byte[5])
second = bcd(Byte[6])
```

---

### 0x02 — Set User Info

**Purpose:** Write personal info to ring (used for calorie/step calculations).

**Command (16 bytes):**
```
Byte[0]  = 0x02
Byte[1]  = gender       (0 = Female, 1 = Male)
Byte[2]  = age          (integer years, hex)
Byte[3]  = height_cm    (integer cm, hex)
Byte[4]  = weight_kg    (integer kg, hex)
Byte[5]  = step_len_cm  (integer cm, hex)
Byte[6..11] = ring_id   (6 ASCII bytes, e.g., "000000" = 0x30 0x30 0x30 0x30 0x30 0x30)
Byte[12..14] = 0x00
Byte[15] = CRC
```

**Example:**
```
02 01 19 AF 46 4B 30 30 30 30 30 30 00 00 00 CRC
   ↑  ↑  ↑  ↑  ↑  └──────────────────┘
   M  25 175 70 75   ringId = "000000"
```

**Success response:** `0x02 00 00 00 ... CRC`
**Failure response:** `0x82 00 00 00 ... CRC`

**Parse steps:**
1. `Byte[0] == 0x02` → success.
2. `Byte[0] == 0x82` → failure.

---

### 0x42 — Get User Info

**Purpose:** Read personal info from ring.

**Command (16 bytes):**
```
Byte[0]  = 0x42
Byte[1..14] = 0x00
Byte[15] = CRC  (= 0x42)
```

**Success response (16 bytes):**
```
Byte[0]  = 0x42
Byte[1]  = gender       (0 = Female, 1 = Male)
Byte[2]  = age          (integer years)
Byte[3]  = height_cm    (integer cm)
Byte[4]  = weight_kg    (integer kg)
Byte[5]  = step_len_cm  (integer cm)
Byte[6..11] = ring_id   (6 ASCII bytes)
Byte[12..14] = 0x00
Byte[15] = CRC
```

**Failure response:** `0xC2 00 00 00 ... CRC`

**Parse steps:**
```
gender    = Byte[1]             // 0=Female, 1=Male
age       = Byte[2]
height    = Byte[3]
weight    = Byte[4]
step_len  = Byte[5]
ring_id   = ASCII(Byte[6..11]) // filter to printable 0x20..0x7E
```

---

### 0x05 — Set Ring ID

**Purpose:** Write a 6-byte device ID to the ring.

**Command (16 bytes):**
```
Byte[0]    = 0x05
Byte[1..6] = ID5 ID4 ID3 ID2 ID1 ID0  (6-byte ID, big-endian, high byte first)
Byte[7..14] = 0x00
Byte[15]   = CRC
```

**Success response:** `0x05 00 00 ... CRC`
**Failure response:** `0x85 00 00 ... CRC`

---

### 0x12 — Factory Reset

**Purpose:** Restore factory settings. Puts device into deep sleep (requires charging to wake).

**Command:** `0x12 00 00 00 00 00 00 00 00 00 00 00 00 00 00 CRC`
**Success response:** `0x12 00 ... CRC`
**Failure response:** `0x92 00 ... CRC`

---

### 0x2E — MCU Soft Reset

**Purpose:** Restart the main MCU and reset measurement mode.

**Command:** `0x2E 00 00 00 00 00 00 00 00 00 00 00 00 00 00 CRC`
**Success response:** `0x2E 00 ... CRC`
**Failure response:** `0xAE 00 ... CRC`

---

### 0x13 — Get Battery Level

**Purpose:** Read battery percentage, charging state, and voltage.

**Command (16 bytes):**
```
Byte[0]  = 0x13
Byte[1..14] = 0x00
Byte[15] = CRC  (= 0x13)
```

**Success response (16 bytes):**
```
Byte[0]  = 0x13
Byte[1]  = battery_level  (0–100, integer percent)
Byte[2]  = charging       (0 = not charging, 1 = charging)
Byte[3]  = voltage_high   (BCD, e.g., 0x41 → 4.1 V: divide by 10)
Byte[4]  = voltage_low    (BCD, e.g., 0x02 → 0.2 V: divide by 10)
Byte[5..14] = 0x00
Byte[15] = CRC
```

**Failure response:** `0x93 00 00 ... CRC`

**Parse steps:**
```
battery  = Byte[1]              // 0–100 %
charging = Byte[2]              // 0 or 1
volt_hi  = bcd(Byte[3]) / 10.0 // e.g., 0x41 → 6.5 V (tenths)
volt_lo  = bcd(Byte[4]) / 10.0
```

---

### 0x14 — Get Ring Temperature (real-time)

**Purpose:** Read instantaneous temperature from the ring's 3 NTC sensors.

**Command (16 bytes):**
```
Byte[0]  = 0x14
Byte[1..14] = 0x00
Byte[15] = CRC  (= 0x14)
```

**Success response (16 bytes):**
```
Byte[0]    = 0x14
Byte[1..2] = highest_temp   (2-byte LE, divide by 10 → °C)
Byte[3..4] = decimal_temp   (BCD-packed: e.g., 0x03 0x28 → 32.8°C)
              Parse: cc = bcd(Byte[3]), dd = bcd(Byte[4])
                     temp = (cc * 100 + dd) / 10.0
Byte[5..6] = NTC1_raw       (2-byte LE, divide by 10 → °C)
Byte[7..8] = NTC2_raw       (2-byte LE, divide by 10 → °C)
Byte[9..10]= NTC3_raw       (2-byte LE, divide by 10 → °C)
Byte[11..14] = 0x00
Byte[15] = CRC
```

**Parse steps:**
```
highest  = (Byte[1] | (Byte[2] << 8)) / 10.0

cc = bcd(Byte[3]);  dd = bcd(Byte[4])
decimal_temp = (cc * 100 + dd) / 10.0

ntc1 = (Byte[5] | (Byte[6] << 8)) / 10.0
ntc2 = (Byte[7] | (Byte[8] << 8)) / 10.0
ntc3 = (Byte[9] | (Byte[10] << 8)) / 10.0
```

---

### 0x22 — Get MAC Address

**Purpose:** Read the Bluetooth MAC address of the ring.

**Command (16 bytes):**
```
Byte[0]  = 0x22
Byte[1..14] = 0x00
Byte[15] = CRC  (= 0x22)
```

**Success response (16 bytes):**
```
Byte[0]    = 0x22
Byte[1..6] = MAC0 MAC1 MAC2 MAC3 MAC4 MAC5  (6 bytes, display with ':')
Byte[7..14] = 0x00
Byte[15] = CRC
```

**Failure response:** `0xA2 00 ... CRC`

**Parse steps:**
```
mac = Byte[1..6].map(b => hex(b, 2)).join(':').toUpperCase()
// e.g., F8:19:23:14:5C:C8
```

---

### 0x27 — Get Firmware Version

**Purpose:** Read software version number and build date.

**Command (16 bytes):**
```
Byte[0]  = 0x27
Byte[1..14] = 0x00
Byte[15] = CRC  (= 0x27)
```

**Success response (16 bytes):**
```
Byte[0]  = 0x27
Byte[1]  = version_A  (BCD)
Byte[2]  = version_B  (BCD)
Byte[3]  = version_C  (BCD)
Byte[4]  = version_D  (BCD)
Byte[5]  = build_YY   (BCD, year offset from 2000)
Byte[6]  = build_MM   (BCD)
Byte[7]  = build_DD   (BCD)
Byte[8..14] = 0x00 (Byte[13] = device ID in some firmware variants)
Byte[15] = CRC
```

**Failure response:** `0xA7 00 ... CRC`

**Parse steps:**
```
version   = bcd(B[1]).bcd(B[2]).bcd(B[3]).bcd(B[4])
build_year  = 2000 + bcd(B[5])
build_month = bcd(B[6])
build_day   = bcd(B[7])
```

---

### 0x09 — Real-time Streaming Mode

**Purpose:** Start/stop continuous 1-second push of steps, calories, distance, HR, temperature, SpO2.

#### Start command:
```
Byte[0]  = 0x09
Byte[1]  = 0x01   (start)
Byte[2]  = 0x01   (enable temperature) or 0x00 (disable)
Byte[3..14] = 0x00
Byte[15] = CRC
```

#### Stop command:
```
Byte[0]  = 0x09
Byte[1]  = 0x00   (stop)
Byte[2..14] = 0x00
Byte[15] = CRC
```

**Streamed response — Format A (16 bytes, with valid CRC):**

The ring sends this ~every second when in streaming mode with a valid 16-byte CRC frame:

```
Byte[0]     = 0x09
Byte[1..4]  = steps       (4-byte LE integer)
Byte[5..8]  = cal_raw     (4-byte LE integer, divide by 100 → kcal)
Byte[9..12] = dist_raw    (4-byte LE integer, divide by 100 → km)
Byte[13]    = heart_rate  (integer BPM)
Byte[14]    = temp_raw    (integer, divide by 10 → °C)
Byte[15]    = CRC
```

**Streamed response — Format B (26 bytes, no CRC, extended):**

```
Byte[0]     = 0x09
Byte[1..4]  = steps       (4-byte LE integer)
Byte[5..8]  = cal_raw     (4-byte LE, divide by 100 → kcal)
Byte[9..12] = dist_raw    (4-byte LE, divide by 100 → km)
Byte[13..20]= reserved / padding
Byte[21]    = heart_rate  (integer BPM)
Byte[22..23]= temp_raw    (2-byte LE, divide by 10 → °C)
Byte[24]    = spo2        (integer %)
Byte[25]    = 0x00
```

**How to detect format:**
- If `length == 16` AND `CRC(Byte[0..14]) == Byte[15]` → Format A.
- If `length >= 26` → Format B (use first 26 bytes).

**Parse steps (Format A):**
```
steps    = B[1] | (B[2]<<8) | (B[3]<<16) | (B[4]<<24)
calories = (B[5] | (B[6]<<8) | (B[7]<<16) | (B[8]<<24)) / 100.0
distance = (B[9] | (B[10]<<8) | (B[11]<<16) | (B[12]<<24)) / 100.0
hr       = B[13]
temp     = B[14] / 10.0
```

**Parse steps (Format B):**
```
steps    = B[1] | (B[2]<<8) | (B[3]<<16) | (B[4]<<24)
calories = (B[5] | (B[6]<<8) | (B[7]<<16) | (B[8]<<24)) / 100.0
distance = (B[9] | (B[10]<<8) | (B[11]<<16) | (B[12]<<24)) / 100.0
hr       = B[21]
temp     = (B[22] | (B[23]<<8)) / 10.0
spo2     = B[24]
```

**Failure response:** `0xA4 00 ... CRC` (if command is rejected)

---

### 0x18 — Live Exercise Push Packet

**Purpose:** Automatically pushed by the ring ~every second during an active exercise session. Not a response to any command.

**Packet (up to 21 bytes, no CRC):**
```
Byte[0]     = 0x18
Byte[1]     = heart_rate   (BPM; 0xFF = ring has ended exercise)
Byte[2..5]  = steps        (4-byte LE integer)
Byte[6..9]  = calories     (IEEE 754 float32 LE, kcal)
Byte[10..13]= duration     (4-byte LE, seconds)
Byte[14..17]= distance     (IEEE 754 float32 LE, km)
Byte[18..20]= 0x00
```

**Special values for Byte[1]:**

| Value | Meaning |
|-------|---------|
| 0xFF  | Exercise ended by ring |
| other | Heart rate in BPM |

**Auto-exit push messages (Byte[1] = 0xAA):**

When inactivity is detected (< 80 steps in the window), the ring sends:

| Pattern | Trigger | Meaning |
|---------|---------|---------|
| `18 AA 01 ...` | 10 min < 80 steps | First prompt: ask user to confirm end |
| `18 AA 02 ...` | 20 min < 80 steps | Second prompt: ask user to confirm end |
| `18 FF 02 ...` | 30 min < 80 steps | Force end exercise |

**Parse steps:**
```
hr       = B[1]
if hr == 0xFF: exercise_ended = true

steps    = B[2] | (B[3]<<8) | (B[4]<<16) | (B[5]<<24)
calories = float32_le(B[6], B[7], B[8], B[9])
duration = B[10] | (B[11]<<8) | (B[12]<<16) | (B[13]<<24)  // seconds
dist_km  = float32_le(B[14], B[15], B[16], B[17])
distance = dist_km * 1000  // convert to metres if needed
```

---

### 0x19 — Exercise Mode Control

**Purpose:** Start, pause, resume, end, or query exercise sessions.

**Command (16 bytes):**
```
Byte[0]  = 0x19
Byte[1]  = AA  (action, see below)
Byte[2]  = BB  (exercise type, see Section 6)
Byte[3]  = CC  (meditation level, only when BB=6; else 0x00)
Byte[4]  = DD  (duration minutes, only when BB=6; else 0x00)
Byte[5..14] = 0x00
Byte[15] = CRC
```

**Action codes (AA):**

| AA | Action |
|----|--------|
| 0x01 | Start exercise |
| 0x02 | Pause exercise |
| 0x03 | Resume exercise |
| 0x04 | End exercise |
| 0x05 | Query current status |

**Success response (16 bytes):**
```
Byte[0]  = 0x19
Byte[1]  = status       (0x01 = active/success, 0x00 = ended/inactive)
Byte[2]  = 0x00         (reserved)
Byte[3]  = YY           (BCD, start timestamp year offset)
Byte[4]  = MM           (BCD)
Byte[5]  = DD           (BCD)
Byte[6]  = HH           (BCD)
Byte[7]  = mm           (BCD)
Byte[8]  = SS           (BCD)
Byte[9..14] = 0x00
Byte[15] = CRC
```

**Error response:** `0xA6 00 ... CRC` (e.g., exercise already active when trying to start)

**Parse steps:**
```
status = B[1]
if status == 0x01: exercise_is_active = true

year   = 2000 + bcd(B[3])
month  = bcd(B[4])
day    = bcd(B[5])
hour   = bcd(B[6])
minute = bcd(B[7])
second = bcd(B[8])

// If all timestamp bytes are 0x00, there is no session timestamp.
has_timestamp = (B[3]|B[4]|B[5]|B[6]|B[7]|B[8]) != 0
```

---

### 0x28 — Multi-Parameter Measurement

**Purpose:** Start/stop an on-demand health measurement (HR, HRV/BP, or SpO2). While active, use `0x09` streaming to receive live values.

#### Start measurement:
```
Byte[0]  = 0x28
Byte[1]  = mode         (0x01=HRV/BP, 0x02=HR, 0x03=SpO2)
Byte[2]  = 0x01         (start)
Byte[3..4] = 0x00
Byte[5]  = duration_lo  (duration in seconds, LE byte 0; minimum 30)
Byte[6]  = duration_hi  (duration in seconds, LE byte 1)
Byte[7..14] = 0x00
Byte[15] = CRC
```

**Duration encoding:**
```
duration = seconds (minimum 30)
Byte[5] = duration & 0xFF
Byte[6] = (duration >> 8) & 0xFF
```

#### Stop measurement:
```
Byte[0]  = 0x28
Byte[1]  = mode         (same mode as start)
Byte[2]  = 0x00         (stop)
Byte[3..14] = 0x00
Byte[15] = CRC
```

#### Status query:
```
Byte[0]  = 0x28
Byte[1]  = 0x80         (query)
Byte[2..14] = 0x00
Byte[15] = CRC
```

**Response (16 bytes):**
```
Byte[0]  = 0x28
Byte[1]  = mode_or_status   (echoes mode for start/stop; for query: active mode code or 0x00)
Byte[2]  = result           (for query response: 0x01=active, 0x00=inactive)
Byte[3..14] = 0x00
Byte[15] = CRC
```

**Status query response — Byte[1] meanings (after `0x28 80`):**

| Byte[1] | Byte[2] | Meaning |
|---------|---------|---------|
| 0x01 | 0x01 | HR measurement active |
| 0x02 | 0x01 | HRV measurement active |
| 0x04 | 0x01 | SpO2 measurement active |
| 0x00 | 0x00 | No measurement active |

---

### 0x2A — Set Measurement Interval Schedule

**Purpose:** Program the ring to auto-measure HR, SpO2, or HRV on a repeating schedule.

**Command (16 bytes):**
```
Byte[0]  = 0x2A
Byte[1]  = measurement_type  (1=HR, 2=SpO2, 4=HRV)
Byte[2]  = working_mode      (0=Off, 2=Interval)
Byte[3]  = start_hour        (BCD, 0–23)
Byte[4]  = start_minute      (BCD, 0–59)  [OR end_hour if FF-variant, see below]
Byte[5]  = end_hour          (BCD, 0–23)  [OR end_minute if FF-variant]
Byte[6]  = end_minute        (BCD, 0–59)  [OR 0xFF if full-day FF-variant]
Byte[7]  = weekday_bits      (bitmask, bit0=Sun, bit1=Mon, ... bit6=Sat)
Byte[8]  = interval_lo       (interval minutes, LE byte 0)
Byte[9]  = interval_hi       (interval minutes, LE byte 1; 0x00 in FF-variant)
Byte[10..14] = 0x00
Byte[15] = CRC
```

**Full-day (00:00–23:59) variant layout — use when start=00:00, end=23:59:**
```
Byte[3]  = 0x00   (start_hour BCD = 0)
Byte[4]  = 0x23   (end_hour BCD = 23, NOT start_minute)
Byte[5]  = 0x59   (end_minute BCD = 59)
Byte[6]  = 0xFF   (marker indicating full-day variant)
Byte[8]  = interval_minutes & 0xFF
Byte[9]  = 0x00
```

**Weekday bitmask:**

| Bit | Day | Value |
|-----|-----|-------|
| bit0 (0x01) | Sunday | |
| bit1 (0x02) | Monday | |
| bit2 (0x04) | Tuesday | |
| bit3 (0x08) | Wednesday | |
| bit4 (0x10) | Thursday | |
| bit5 (0x20) | Friday | |
| bit6 (0x40) | Saturday | |
| 0x7F | All days | |
| 0x3E | Mon–Fri | |

**Success response:** `0x2A 00 00 ... CRC`
**Failure response:** `0xAA 00 00 ... CRC`

---

### 0x2B — Get Measurement Interval Schedule

**Purpose:** Read the current auto-measurement schedule for HR, SpO2, or HRV.

**Command (16 bytes):**
```
Byte[0]  = 0x2B
Byte[1]  = measurement_type  (1=HR, 2=SpO2, 4=HRV)
Byte[2..14] = 0x00
Byte[15] = CRC
```

**Success response (16 bytes):**

Response mirrors the `0x2A` set command layout:

```
Byte[0]  = 0x2B
Byte[1]  = measurement_type  (echoed)
Byte[2]  = working_mode      (0=Off, 2=Interval)
Byte[3]  = start_hour        (BCD)
Byte[4]  = start_minute or end_hour (BCD; see FF-variant below)
Byte[5]  = end_hour or end_minute   (BCD)
Byte[6]  = end_minute or 0xFF       (BCD or FF-marker)
Byte[7]  = weekday_bits
Byte[8]  = interval_lo
Byte[9]  = interval_hi
Byte[10..14] = 0x00
Byte[15] = CRC
```

**Parse steps — detect FF-variant:**
```
if Byte[6] == 0xFF:
  // FF-variant (full-day or compact format)
  start_hour   = bcd(Byte[3])
  start_minute = 0
  end_hour     = bcd(Byte[4])
  end_minute   = bcd(Byte[5])
  interval     = Byte[8]
else:
  // Standard
  start_hour   = bcd(Byte[3])
  start_minute = bcd(Byte[4])
  end_hour     = bcd(Byte[5])
  end_minute   = bcd(Byte[6])
  interval     = Byte[8] | (Byte[9] << 8)

working_mode_name = (Byte[2] == 0) ? "Off" : (Byte[2] == 2) ? "Interval" : "Unknown"
```

**Failure response:** `0xAB 00 00 ... CRC`

---

### 0x51 — Get Total Step Count History

**Purpose:** Retrieve daily step totals for up to 15 days.

**Command (16 bytes):**
```
Byte[0]  = 0x51
Byte[1]  = 0x00   (read all)
Byte[2..14] = 0x00
Byte[15] = CRC
```

**Response — variable-length, no CRC. Each record is 27 bytes:**
```
Byte[0]     = 0x51
Byte[1]     = ID        (0=today, 1=yesterday, ... up to 15)
Byte[2]     = YY        (BCD, year offset)
Byte[3]     = MM        (BCD)
Byte[4]     = DD        (BCD)
Byte[5..8]  = steps     (4-byte LE integer)
Byte[9..12] = exercise_time  (4-byte LE, seconds)
Byte[13..16]= distance  (4-byte LE, units of 0.01 km → divide by 100)
Byte[17..20]= calories  (4-byte LE, units of 0.01 kcal → divide by 100)
Byte[21..26]= 0x00      (padding)
```

**End-of-data marker:** `0x51 0xFF`

**Parse steps:**
```
year    = 2000 + bcd(B[2])
month   = bcd(B[3])
day     = bcd(B[4])
steps   = B[5] | (B[6]<<8) | (B[7]<<16) | (B[8]<<24)
ex_time = B[9] | (B[10]<<8) | (B[11]<<16) | (B[12]<<24)  // seconds
dist_km = (B[13] | (B[14]<<8) | (B[15]<<16) | (B[16]<<24)) / 100.0
kcal    = (B[17] | (B[18]<<8) | (B[19]<<16) | (B[20]<<24)) / 100.0
```

---

### 0x52 — Get Detailed Step Count History

**Purpose:** Retrieve per-10-minute step data with per-minute breakdown.

**Command (16 bytes):**
```
Byte[0]  = 0x52
Byte[1]  = AA   (0x00=read latest, 0x02=continue, 0x99=delete)
Byte[2]  = 0x00
Byte[3..8] = YY MM DD HH mm SS  (timestamp filter, all 0x00 for full history)
Byte[9..14] = 0x00
Byte[15] = CRC
```

**Response — each record is 25 bytes:**
```
Byte[0]     = 0x52
Byte[1]     = ID1       (record index high byte)
Byte[2]     = ID2       (record index low byte)
Byte[3]     = YY        (BCD, year offset)
Byte[4]     = MM        (BCD)
Byte[5]     = DD        (BCD)
Byte[6]     = HH        (BCD, timestamp of the 10-min block start)
Byte[7]     = mm        (BCD)
Byte[8]     = SS        (BCD)
Byte[9..10] = total_steps   (2-byte LE)
Byte[11..12]= calories      (2-byte LE, units of 0.01 kcal)
Byte[13..14]= distance      (2-byte LE, units of 0.01 km)
Byte[15..24]= per_minute    (10 bytes, one step count per minute in the block)
```

**End-of-data marker:** `0x52 0xFF`

**Parse steps:**
```
year        = 2000 + bcd(B[3])
month       = bcd(B[4]);  day = bcd(B[5])
hour        = bcd(B[6]);  min = bcd(B[7]);  sec = bcd(B[8])
total_steps = B[9] | (B[10]<<8)
calories    = (B[11] | (B[12]<<8)) / 100.0
distance    = (B[13] | (B[14]<<8)) / 100.0
per_minute  = B[15..24]   // array of 10 step counts (0 = minute not active)
```

---

### 0x53 — Get Sleep History

**Purpose:** Retrieve sleep sessions with per-minute stage data.

**Command (16 bytes):**
```
Byte[0]  = 0x53
Byte[1]  = AA   (0x00=read latest, 0x02=continue, 0x99=delete)
Byte[2]  = 0x00
Byte[3..8] = YY MM DD HH mm SS  (timestamp filter, 0x00 = all)
Byte[9..14] = 0x00
Byte[15] = CRC
```

**Response — each record is variable length:**

**Fixed-size firmware variant (most common): 130 bytes total**
```
Byte[0]      = 0x53
Byte[1]      = ID1         (record index)
Byte[2]      = ID2         (page index)
Byte[3]      = YY          (BCD, year offset)
Byte[4]      = MM          (BCD)
Byte[5]      = DD          (BCD)
Byte[6]      = HH          (BCD, session start hour)
Byte[7]      = mm          (BCD)
Byte[8]      = SS          (BCD)
Byte[9]      = N           (valid stage count, 1–120)
Byte[10..10+N-1] = stage_data  (N bytes, one byte per minute)
Byte[10+N..129]  = 0x00    (padding to fill 130 bytes)
```

**Sleep stage values:**

| Value | Stage |
|-------|-------|
| 0x01 | Deep sleep |
| 0x02 | Light sleep |
| 0x03 | REM sleep |
| other | Awake |

**End-of-data marker:** `0x53 0xFF`

**Framing algorithm:**
```
Try 130-byte fixed frame first:
  if (i + 130 <= buffer.length) and (buffer[i] == 0x53):
    parse 130-byte frame
    i += 130

Fallback to variable length:
  N = buffer[i+9]
  if 1 <= N <= 120:
    parse frame of size (10 + N)
    i += (10 + N)
```

**Parse steps:**
```
year    = 2000 + bcd(B[3]);  month = bcd(B[4]);  day = bcd(B[5])
hour    = bcd(B[6]);  minute = bcd(B[7]);  second = bcd(B[8])
N       = B[9]
stages  = B[10 .. 10+N-1]

deep=0; light=0; rem=0; awake=0
for s in stages:
  if s==1: deep++ elif s==2: light++ elif s==3: rem++ else: awake++

duration_minutes = N  // each stage byte = 1 minute
```

---

### 0x54 — Get Detailed Heart Rate History

**Purpose:** Retrieve dense HR measurements: 15 readings per record at 5-second intervals (75 seconds total per record).

**Command (16 bytes):**
```
Byte[0]  = 0x54
Byte[1]  = AA   (0x00=read latest, 0x02=continue, 0x99=delete)
Byte[2]  = 0x00
Byte[3..8] = YY MM DD HH mm SS  (timestamp filter, 0x00 = all)
Byte[9..14] = 0x00
Byte[15] = CRC
```

**Response — each record is 24 bytes:**
```
Byte[0]      = 0x54
Byte[1]      = ID1         (record index)
Byte[2]      = ID2         (page index)
Byte[3]      = YY          (BCD, year offset)
Byte[4]      = MM          (BCD)
Byte[5]      = DD          (BCD)
Byte[6]      = HH          (BCD)
Byte[7]      = mm          (BCD)
Byte[8]      = SS          (BCD)
Byte[9..23]  = HR[0..14]   (15 bytes, one HR value per 5-second interval)
```

**End-of-data marker:** `0x54 0xFF`

**Parse steps:**
```
year  = 2000 + bcd(B[3]);  month = bcd(B[4]);  day = bcd(B[5])
hour  = bcd(B[6]);  minute = bcd(B[7]);  second = bcd(B[8])
hr    = B[9..23]    // 15 values; 0 = no reading at that 5-sec slot

valid_hr = hr.filter(v => v > 0)
avg_hr = mean(valid_hr)
min_hr = min(valid_hr)
max_hr = max(valid_hr)
```

---

### 0x55 — Get Heart Rate History

**Purpose:** Retrieve individual single-point HR measurements.

**Command (16 bytes):**
```
Byte[0]  = 0x55
Byte[1]  = AA   (0x00=read latest, 0x02=continue, 0x99=delete)
Byte[2]  = 0x00
Byte[3..8] = YY MM DD HH mm SS  (timestamp filter, 0x00 = all)
Byte[9..14] = 0x00
Byte[15] = CRC
```

**Response — each record is 10 bytes:**
```
Byte[0]  = 0x55
Byte[1]  = ID1       (record index)
Byte[2]  = ID2       (page index)
Byte[3]  = YY        (BCD, year offset)
Byte[4]  = MM        (BCD)
Byte[5]  = DD        (BCD)
Byte[6]  = HH        (BCD)
Byte[7]  = mm        (BCD)
Byte[8]  = SS        (BCD)
Byte[9]  = heart_rate  (integer BPM)
```

**End-of-data marker:** `0x55 0xFF`

**Parse steps:**
```
year  = 2000 + bcd(B[3]);  month = bcd(B[4]);  day = bcd(B[5])
hour  = bcd(B[6]);  minute = bcd(B[7]);  second = bcd(B[8])
hr    = B[9]
```

---

### 0x56 — Get HRV / Stress / BP History

**Purpose:** Retrieve HRV measurements including heart rate variability, fatigue score, and estimated blood pressure.

**Command (16 bytes):**
```
Byte[0]  = 0x56
Byte[1]  = 0x01   (read; 0x99=delete, 0x02=continue — but implementation uses 0x01)
Byte[2..14] = 0x00
Byte[15] = CRC
```

**Note:** The implementation sends `0x56 01 00 ...` (AA=0x01, not 0x00).

**Response — each record is exactly 15 bytes:**
```
Byte[0]  = 0x56
Byte[1]  = ID1       (record index)
Byte[2]  = ID2       (page index)
Byte[3]  = YY        (BCD, year offset)
Byte[4]  = MM        (BCD)
Byte[5]  = DD        (BCD)
Byte[6]  = HH        (BCD)
Byte[7]  = mm        (BCD)
Byte[8]  = SS        (BCD)
Byte[9]  = hrv_ms    (HRV value in milliseconds)
Byte[10] = 0x00      (always 0x00, must validate; if non-zero, skip record)
Byte[11] = heart_rate  (BPM)
Byte[12] = fatigue     (stress/fatigue level 0–100)
Byte[13] = systolic    (estimated systolic BP, mmHg approx.)
Byte[14] = diastolic   (estimated diastolic BP, mmHg approx.)
```

**End-of-data marker:** `0x56 0xFF`

**Validation check:** If `Byte[10] != 0x00`, the record is malformed — skip it and advance by 1 byte (not 15) to re-sync.

**Parse steps:**
```
if B[10] != 0x00: skip (re-sync by +1)

year     = 2000 + bcd(B[3]);  month = bcd(B[4]);  day = bcd(B[5])
hour     = bcd(B[6]);  minute = bcd(B[7]);  second = bcd(B[8])
hrv_ms   = B[9]
hr       = B[11]
fatigue  = B[12]   // 0=no stress, higher=more stressed
systolic = B[13]
diastolic= B[14]
```

---

### 0x5C — Get Exercise Mode History

**Purpose:** Retrieve stored exercise session records (runs, cycles, etc.).

**Command (16 bytes):**
```
Byte[0]  = 0x5C
Byte[1]  = AA   (0x00=read latest, 0x02=continue, 0x99=delete)
Byte[2..14] = 0x00
Byte[15] = CRC
```

**Response — each record is 27 bytes (with per-record CRC):**
```
Byte[0]      = 0x5C
Byte[1]      = ID1           (record index)
Byte[2]      = ID2           (page/sub-index)
Byte[3]      = YY            (BCD, year offset)
Byte[4]      = MM            (BCD)
Byte[5]      = DD            (BCD)
Byte[6]      = HH            (BCD, session start hour)
Byte[7]      = mm            (BCD)
Byte[8]      = SS            (BCD)
Byte[9]      = exercise_type (see Section 6)
Byte[10]     = heart_rate    (average or peak HR, BPM)
Byte[11..12] = duration      (2-byte LE, seconds)
Byte[13..14] = steps         (2-byte LE, integer)
Byte[15]     = pace_minutes  (BCD, minutes component of pace per km)
Byte[16]     = pace_seconds  (BCD, seconds component of pace per km)
Byte[17..20] = calories      (IEEE 754 float32 LE, kcal)
Byte[21..24] = distance      (IEEE 754 float32 LE, km)
Byte[25]     = 0x00          (reserved)
Byte[26]     = CRC           (sum of Byte[0..25] & 0xFF)
```

**Per-record CRC validation:**
```
calc = (B[0] + B[1] + ... + B[25]) & 0xFF
if calc != B[26]: record is corrupt, stop framing
```

**Control ACK response (16 bytes):**

Sent after a control command (delete, request-latest, continue):
```
Byte[0]  = 0x5C
Byte[1]  = sub_command  (echoed: 0x00, 0x02, or 0x99)
Byte[2]  = 0x00
Byte[3..14] = 0x00
Byte[15] = CRC
```

**End-of-data marker:** `0x5C 0xFF` (2 bytes only, no CRC)

**Parse steps:**
```
year     = 2000 + bcd(B[3]);  month = bcd(B[4]);  day = bcd(B[5])
hour     = bcd(B[6]);  minute = bcd(B[7]);  second = bcd(B[8])
type     = B[9]              // see Section 6
hr       = B[10]
duration = B[11] | (B[12]<<8)  // seconds
steps    = B[13] | (B[14]<<8)
pace_min = bcd(B[15])
pace_sec = bcd(B[16])
calories = float32_le(B[17], B[18], B[19], B[20])  // kcal
distance = float32_le(B[21], B[22], B[23], B[24])  // km
```

---

### 0x62 — Get Temperature History

**Purpose:** Retrieve stored temperature measurements (from the temperature measurement interface, not real-time ring temp).

**Command (16 bytes):**
```
Byte[0]  = 0x62
Byte[1]  = AA   (0x00=read latest, 0x02=continue, 0x99=delete)
Byte[2]  = 0x00
Byte[3..8] = YY MM DD HH mm SS  (timestamp filter, 0x00 = all)
Byte[9..14] = 0x00
Byte[15] = CRC
```

**Response — each record is 15 bytes:**
```
Byte[0]      = 0x62
Byte[1]      = ID1          (record index)
Byte[2]      = ID2          (page index)
Byte[3]      = YY           (BCD, year offset)
Byte[4]      = MM           (BCD)
Byte[5]      = DD           (BCD)
Byte[6]      = HH           (BCD)
Byte[7]      = mm           (BCD)
Byte[8]      = SS           (BCD)
Byte[9..10]  = temp1_raw    (2-byte LE, divide by 10 → °C)
Byte[11..12] = temp2_raw    (2-byte LE, divide by 10 → °C)
Byte[13..14] = temp3_raw    (2-byte LE, divide by 10 → °C)
```

**End-of-data marker:** `0x62 0xFF`

**Parse steps:**
```
year  = 2000 + bcd(B[3]);  month = bcd(B[4]);  day = bcd(B[5])
hour  = bcd(B[6]);  minute = bcd(B[7]);  second = bcd(B[8])

temperatures = []
i = 9
while i+1 < 15:
  raw = B[i] | (B[i+1] << 8)
  temperatures.append(raw / 10.0)
  i += 2
// temperatures[0], temperatures[1], temperatures[2] → three readings
```

---

### 0x66 — Get Blood Oxygen History

**Purpose:** Retrieve stored SpO2 (blood oxygen saturation) measurements from automatic monitoring.

**Command (16 bytes):**
```
Byte[0]  = 0x66
Byte[1]  = AA   (0x00=read latest, 0x02=continue, 0x99=delete)
Byte[2]  = 0x00
Byte[3..8] = YY MM DD HH mm SS  (timestamp filter, 0x00 = all)
Byte[9..14] = 0x00
Byte[15] = CRC
```

**Response — each record is 10 bytes:**
```
Byte[0]  = 0x66
Byte[1]  = ID1       (record index)
Byte[2]  = ID2       (page index)
Byte[3]  = YY        (BCD, year offset)
Byte[4]  = MM        (BCD)
Byte[5]  = DD        (BCD)
Byte[6]  = HH        (BCD)
Byte[7]  = mm        (BCD)
Byte[8]  = SS        (BCD)
Byte[9]  = spo2      (SpO2 percentage, 0–100)
```

**End-of-data marker:** `0x66 0xFF`

**Parse steps:**
```
year  = 2000 + bcd(B[3]);  month = bcd(B[4]);  day = bcd(B[5])
hour  = bcd(B[6]);  minute = bcd(B[7]);  second = bcd(B[8])
spo2  = B[9]   // percentage
```

---

## 5. Error Response Codes Summary

| Error Code | Original Command | Meaning |
|------------|-----------------|---------|
| 0x81 | 0x01 Set Time | CRC error or failure |
| 0x82 | 0x02 Set User Info | CRC error or failure |
| 0x85 | 0x05 Set Ring ID | CRC error or failure |
| 0x92 | 0x12 Factory Reset | CRC error or failure |
| 0x93 | 0x13 Get Battery | CRC error or failure |
| 0xA2 | 0x22 Get MAC | CRC error or failure |
| 0xA4 | 0x09 Real-time Mode | CRC error or failure |
| 0xA6 | 0x19 Exercise Control | Conflict (e.g., already active) |
| 0xA7 | 0x27 Get Firmware | CRC error or failure |
| 0xAA | 0x2A Set Interval | CRC error or failure |
| 0xAB | 0x2B Get Interval | CRC error or failure |
| 0xAE | 0x2E MCU Reset | CRC error or failure |
| 0xC1 | 0x41 Get Time | CRC error or failure |
| 0xC2 | 0x42 Get User Info | CRC error or failure |

**Pattern:** Error code = original command byte with bit 7 set (`error = cmd | 0x80`).

---

## 6. Exercise Type Codes

Used in `0x19` command (BB field) and `0x5C` response (Byte[9]):

| Code | Exercise |
|------|---------|
| 0x00 | Running |
| 0x01 | Walking |
| 0x02 | Cycling |
| 0x03 | Hiking |
| 0x04 | Yoga |
| 0x05 | Basketball |
| 0x06 | Football |
| 0x07 | Badminton |
| 0x08 | Table Tennis |
| 0x09 | Rope Skipping |
| 0x0A | Sit-ups |
| 0x0B | Push-ups |
| 0x0C | Swimming |

> **Note:** The `0x19` command's original protocol lists additional types (Meditation=6, Dance=7, Basketball=8, Walk=9, Workout=10, Cricket=11, Hiking=12, Aerobics=13, Ping-Pong=14). The exercise history responses (`0x5C`) use a different mapping in the implementation (above table). Use the above table for parsing `0x5C` records.

---

## Appendix: CRC Helper Pseudocode

```
function computeCRC(bytes[0..14]):
    sum = 0
    for i in 0..14:
        sum += bytes[i]
    return sum & 0xFF

function buildCommand(cmd, payload[0..13]):
    bytes = [cmd] + payload
    bytes[15] = computeCRC(bytes[0..14])
    return bytes
```

## Appendix: BCD Helper Pseudocode

```
function bcdToDecimal(bcd):
    return ((bcd >> 4) * 10) + (bcd & 0x0F)

function decimalToBcd(value):
    return ((value / 10) << 4) | (value % 10)
```

## Appendix: Float32 LE Helper Pseudocode

```
function float32LE(b0, b1, b2, b3):
    bytes = [b0 & 0xFF, b1 & 0xFF, b2 & 0xFF, b3 & 0xFF]
    return IEEE754_float32(bytes, endian=LITTLE)
```
