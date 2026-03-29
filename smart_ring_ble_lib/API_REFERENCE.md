# Smart Ring BLE Library — API Reference

A Flutter BLE library (`smart_ring_ble_lib`) for communicating with the Lumie Smart Ring (X6B) device over Bluetooth Low Energy.

---

## Table of Contents

1. [Setup & Installation](#setup--installation)
2. [BLE Protocol Overview](#ble-protocol-overview)
3. [Data Models](#data-models)
   - [HrvRecord](#hrvrecord)
   - [SleepRecord](#sleeprecord)
4. [BleService Class](#bleservice-class)
   - [Constructor & Configuration](#constructor--configuration)
   - [Streams](#streams)
   - [Connection Management](#connection-management)
   - [Time Commands](#time-commands)
   - [User Info Commands](#user-info-commands)
   - [Device Info Commands](#device-info-commands)
   - [Real-time Streaming](#real-time-streaming)
   - [Health Measurement Commands](#health-measurement-commands)
   - [Measurement Interval Commands](#measurement-interval-commands)
   - [Exercise Mode Commands](#exercise-mode-commands)
   - [Historical Data Commands](#historical-data-commands)
   - [High-Level Data Fetching](#high-level-data-fetching)
   - [Raw Message Sending](#raw-message-sending)
5. [Response Parsing](#response-parsing)
   - [Parsed Message Format](#parsed-message-format)
   - [Command Response Reference](#command-response-reference)
6. [Usage Examples](#usage-examples)
7. [Error Handling](#error-handling)
8. [Protocol Quick Reference](#protocol-quick-reference)

---

## Setup & Installation

Add the library as a path dependency in your `pubspec.yaml`:

```yaml
dependencies:
  smart_ring_ble_lib:
    path: ../smart_ring_ble_lib
```

Required permissions (add to `AndroidManifest.xml` and `Info.plist`):

```xml
<!-- Android -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

```xml
<!-- iOS Info.plist -->
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Required to connect to the smart ring</string>
```

---

## BLE Protocol Overview

All communication uses 16-byte packets over BLE GATT:

| Field | Bytes | Description |
|-------|-------|-------------|
| B1 | 1 | Command byte (0x00–0x7F); bit 7 = 0 for requests |
| B2–B15 | 14 | Payload bytes |
| B16 | 1 | CRC = `(B1 + B2 + ... + B15) & 0xFF` |

**Service & Characteristic UUIDs:**

```dart
static const String serviceUuid          = '0000fff0-0000-1000-8000-00805f9b34fb';
static const String writeCharacteristicUuid = '0000fff6-0000-1000-8000-00805f9b34fb';
static const String notifyCharacteristicUuid = '0000fff7-0000-1000-8000-00805f9b34fb';
```

**Error responses** set bit 7 of the command byte (e.g., `0x82` for failed `0x02`).

**Timestamp encoding:** All timestamps use `2000 + YY` (e.g., `0x25` → 2025). BCD format is used for time fields in some commands.

**Multi-record responses** (0x51–0x66) are variable-length and end with `CMD FF` (e.g., `0x56 FF`). There is no CRC on these responses.

---

## Data Models

### HrvRecord

Represents a single HRV (Heart Rate Variability) measurement.

```dart
class HrvRecord {
  final int      index;         // Record index (ID1)
  final int      page;          // Page number (ID2)
  final DateTime timestamp;     // Measurement time
  final int      hrvMs;         // HRV value in milliseconds
  final int      heartRateBpm;  // Heart rate in BPM
  final int      fatigue;       // Fatigue/stress level (0–100)
  final int      systolic;      // Systolic blood pressure (mmHg, approximate)
  final int      diastolic;     // Diastolic blood pressure (mmHg, approximate)
}
```

**toString()** returns:
```
HRV[0/0] 2025-07-02T13:58:48.000 HRV=57ms HR=61 BPM Fatigue=30 BP=119/62
```

---

### SleepRecord

Represents a merged sleep session.

```dart
class SleepRecord {
  final int        index;            // Record index
  final int        page;             // Page number
  final DateTime   startTimestamp;   // Sleep session start time
  final int        durationMinutes;  // Total duration (minutes)
  final int        deepMinutes;      // Time in deep sleep (minutes)
  final int        lightMinutes;     // Time in light sleep (minutes)
  final int        remMinutes;       // Time in REM sleep (minutes)
  final int        awakeMinutes;     // Time awake (minutes)
  final List<int>  stages;           // Per-minute stage values (see below)
}
```

**Sleep Stage Values:**
| Value | Stage |
|-------|-------|
| 1 | Deep sleep |
| 2 | Light sleep |
| 3 | REM sleep |
| other | Awake |

**Merging logic:** The library automatically merges consecutive sleep segments within the same night (defined as 18:00 – 12:00 next day) if the gap between them is ≤ 60 minutes.

---

## BleService Class

### Constructor & Configuration

```dart
BleService({String? deviceName, String? macAddress})
```

Creates a new BLE service instance. Optionally specify a target device by name or MAC address.

```dart
// Connect to a specific device
final ble = BleService(macAddress: 'F8:19:23:14:5C:C8');

// Connect by device name
final ble = BleService(deviceName: 'Lumie Ring');

// No target — scans and picks best match using fuzzy hints
final ble = BleService();
ble.setFuzzyNameHints(['Lumie', 'X6B', 'Ring']);
```

---

#### `setTarget`

```dart
void setTarget({String? deviceName, String? macAddress})
```

Updates the target device at runtime. If both are provided, MAC address takes precedence.

---

#### `setFuzzyNameHints`

```dart
void setFuzzyNameHints(List<String> hints)
```

Sets fallback substrings for device name matching during scanning (case-insensitive `contains()`). Used when no exact `deviceName` or `macAddress` is set.

---

### Streams

All responses from the ring are published to streams. **Subscribe before issuing commands.**

#### `connectionStatusStream`

```dart
Stream<String> get connectionStatusStream
```

Emits connection state strings:
- `"Connected to <DeviceName>"`
- `"Disconnected"`
- `"Connecting..."`
- `"Scanning..."`
- `"Reconnecting..."`

#### `messageStream`

```dart
Stream<String> get messageStream
```

Emits human-readable parsed responses for every incoming BLE packet. Each response begins with an emoji and command-specific prefix (see [Command Response Reference](#command-response-reference)).

**Example listener:**

```dart
ble.messageStream.listen((msg) {
  print(msg);
  // e.g.: "🔋 Battery: 85% | Charging: No | Voltage: 4.12V"
});
```

---

### Connection Management

#### `connectToSmartRing`

```dart
Future<void> connectToSmartRing() async
```

Main entry point for connection. Attempts to reconnect to the last known device first, then falls back to scanning. Enables auto-reconnect with a 5-second timer on disconnection.

#### `scanAndConnect`

```dart
Future<void> scanAndConnect() async
```

Starts a 10-second BLE scan and connects to the first matching device. Matching priority:
1. Exact MAC address match
2. Exact device name match (case-insensitive)
3. Fuzzy name hint match (contains)

#### `disconnect`

```dart
Future<void> disconnect() async
```

Disconnects from the current device and cancels the auto-reconnect timer.

#### `dispose`

```dart
Future<void> dispose()
```

Disconnects and closes all stream controllers. Call in your widget's `dispose()`.

---

### Time Commands

#### `sendSetTimeCommand` *(via `sendMessage`)*

Sends command `0x01` to set the ring's clock.

```dart
// Build and send manually (time fields use BCD; year is 2-digit offset from 2000)
await ble.sendMessage('01 25 02 27 14 30 00 00 00 00 00 00 00 00 00 CRC');
```

**Protocol:**
```
0x01 YY MM DD hh mm ss 00 00 00 00 00 00 00 00 CRC
```
- `YY`: Year minus 2000 in BCD (e.g., `0x25` = 2025)
- `MM`: Month in BCD
- `DD`: Day in BCD
- `hh`: Hour in BCD
- `mm`: Minute in BCD
- `ss`: Second in BCD

**Observed behavior:** The tested ring firmware ACKs `0x01` even when the outgoing time fields are plain decimal, but the RTC may not actually update. Using BCD-encoded time fields successfully updates the ring clock.

**Verification:** After sending `0x01`, immediately send `0x41` and confirm the returned ring time matches the requested timestamp.

**Response:** `0x01 F4 00 ... CRC` (F4 = max BT packet length = 244 bytes)

#### `sendGetTimeCommand`

```dart
Future<void> sendGetTimeCommand() async
```

Sends command `0x41`. Response via `messageStream`:

```
🕐 Time: 2025-02-27 14:30:00 (Thursday) | BT MTU: 244
```

---

### User Info Commands

#### `sendSetUserInfoCommand`

```dart
Future<void> sendSetUserInfoCommand({
  required int gender,        // 0 = Female, 1 = Male
  required int age,           // Years (0–120)
  required int heightCm,      // Centimetres (50–250)
  required int weightKg,      // Kilograms (10–300)
  required int stepLengthCm,  // Step length in cm (20–120)
  String ringId = '000000',   // ASCII string up to 6 characters
}) async
```

Sends command `0x02`. Writes personal info to the ring used for step/calorie calculations.

**Example:**
```dart
await ble.sendSetUserInfoCommand(
  gender: 1,
  age: 25,
  heightCm: 175,
  weightKg: 70,
  stepLengthCm: 75,
  ringId: 'LUMIE1',
);
```

**Response via `messageStream`:**
```
✅ Set User Info: Success
```

#### `sendGetUserInfoCommand`

```dart
Future<void> sendGetUserInfoCommand() async
```

Sends command `0x42`. Response via `messageStream`:

```
👤 User Info: Female, Age 25, Height 175cm, Weight 70kg, Step 75cm | Ring ID: LUMIE1
```

---

### Device Info Commands

#### `sendGetBatteryCommand`

```dart
Future<void> sendGetBatteryCommand() async
```

Sends command `0x13`. Response via `messageStream`:

```
🔋 Battery: 85% | Charging: No | Voltage: 4.12V
```

#### `sendGetMacAddressCommand`

```dart
Future<void> sendGetMacAddressCommand() async
```

Sends command `0x22`. Response via `messageStream`:

```
📍 MAC: F8:19:23:14:5C:C8
```

#### `sendGetFirmwareVersionCommand`

```dart
Future<void> sendGetFirmwareVersionCommand() async
```

Sends command `0x27`. Response via `messageStream`:

```
🔧 Firmware: v1.2.3.4 (2025-01-15) ID: 0xAB
```

#### `sendGetRingTemperatureCommand`

```dart
Future<void> sendGetRingTemperatureCommand() async
```

Sends command `0x14`. Returns the highest reading from 3 NTC sensors. Response via `messageStream`:

```
🌡️ Ring Temp: 32.8°C (decimal: 32.8°C) | NTC1: 32.5°C NTC2: 32.8°C NTC3: 32.1°C
```

---

### Real-time Streaming

Real-time mode sends continuous `0x09` packets from the ring approximately every second, carrying live HR, steps, calories, distance, temperature, and SpO2.

#### `sendStartRealtimeMode`

```dart
Future<void> sendStartRealtimeMode({bool enableTemperature = true}) async
```

Sends command `0x09 01 BB ...` where `BB = 1` if temperature enabled.

**Streaming response via `messageStream` (emitted every ~1 second):**

```
📡 Real-time Mode: Steps=1024 | Cal=5.12 kcal | Dist=0.82 km | HR=78 bpm | Temp=36.5°C | SpO2=98%
```

#### `sendStopRealtimeMode`

```dart
Future<void> sendStopRealtimeMode() async
```

Sends command `0x09 00 00 ...` to stop streaming.

---

### Health Measurement Commands

These commands start/stop on-demand measurements (not historical data retrieval).

#### `sendStartMultiParamMeasurement`

```dart
Future<void> sendStartMultiParamMeasurement({
  required int mode,          // 0x01: HRV/BP, 0x02: Heart rate, 0x03: SpO2
  int durationSeconds = 30,   // Minimum 30 seconds (device enforces)
}) async
```

Sends command `0x28 AA 01 00 00 CC DD ...`.

**Example — start heart rate measurement for 60 seconds:**
```dart
await ble.sendStartMultiParamMeasurement(mode: 0x02, durationSeconds: 60);
```

While measurement is active, issue `sendStartRealtimeMode()` to receive live data.

#### `sendStopMultiParamMeasurement`

```dart
Future<void> sendStopMultiParamMeasurement({required int mode}) async
```

Stops an ongoing measurement. Use the same `mode` value as the start command.

#### `sendQueryMultiParamStatus`

```dart
Future<void> sendQueryMultiParamStatus() async
```

Sends `0x28 80 ...`. Response via `messageStream`:

```
📊 Measurement Status: HR active (mode=1)
```

---

### Measurement Interval Commands

Configure the ring to automatically measure HR, SpO2, or HRV on a schedule.

#### `sendSetMeasurementIntervalCommand`

```dart
Future<void> sendSetMeasurementIntervalCommand({
  required int measurementType,  // 1=HR, 2=SpO2, 4=HRV
  required int workingMode,      // 0=Off, 2=Interval
  required int startHour,        // 0–23 (stored as BCD, e.g. 23 → 0x23)
  required int startMinute,      // 0–59 (BCD)
  required int endHour,          // 0–23 (BCD)
  required int endMinute,        // 0–59 (BCD)
  required int weekdayBits,      // Bitmask: bit0=Sun, bit1=Mon, ..., bit6=Sat
  required int intervalMinutes,  // Measurement interval in minutes
}) async
```

Sends command `0x2A`.

**Weekday bitmask examples:**
- `0x7F` = All days
- `0x3E` = Mon–Fri only (bits 1–5)
- `0x41` = Sun + Sat (bits 0, 6)

**Example — measure SpO2 every 5 minutes, all day, all week:**
```dart
await ble.sendSetMeasurementIntervalCommand(
  measurementType: 2,
  workingMode: 2,
  startHour: 0,
  startMinute: 0,
  endHour: 23,
  endMinute: 59,
  weekdayBits: 0x7F,
  intervalMinutes: 5,
);
```

#### `sendGetMeasurementIntervalCommand`

```dart
Future<void> sendGetMeasurementIntervalCommand(int measurementType) async
```

Sends command `0x2B AA ...` where `AA` is the measurement type.

**Response via `messageStream`:**
```
⏰ Measurement Interval [SpO2]: Mode=Interval | 00:00–23:59 | All days | Every 5 min
```

---

### Exercise Mode Commands

#### `sendStartExerciseCommand`

```dart
Future<void> sendStartExerciseCommand() async
```

Sends `0x19 01 00 00 00 ...` to start exercise mode (default: running).

**Response via `messageStream`:**
```
🏃 Exercise: Started at 2025-02-27 14:30:00
```

#### `sendEndExerciseCommand`

```dart
Future<void> sendEndExerciseCommand() async
```

Sends `0x19 04 00 00 00 ...` to end the current exercise session.

#### `sendGetExerciseDataCommand`

```dart
Future<void> sendGetExerciseDataCommand() async
```

Sends `0x19 05 ...` to query the current exercise status.

**Response via `messageStream`:**
```
🏃 Exercise Status: Active | Type: Running | Started: 2025-02-27 14:30:00
```
or
```
🏃 Exercise: Ended/Not active
```

During exercise, the ring automatically pushes live `0x18` packets (no polling needed):

```
🏃 Live Exercise: HR=132 bpm | Steps=850 | Cal=48.5 kcal | Time=0:05:30 | Dist=0.62 km
```

When the ring detects low activity it sends exit notifications:
- After 10 min with <80 steps → `18 AA 01` (prompt user to confirm end)
- After 20 min with <80 steps → `18 AA 02` (second prompt)
- After 30 min with <80 steps → `18 FF 02` (forced end)

---

### Historical Data Commands

These send a single command; responses arrive as multiple BLE packets on `messageStream`. Use the [high-level fetching methods](#high-level-data-fetching) for structured results.

| Method | Command | Description |
|--------|---------|-------------|
| `sendGetTotalStepCountCommand()` | `0x51` | Daily step summaries (up to 15 days) |
| `sendGetDetailedStepCountCommand()` | `0x52` | Per-10-minute step data |
| `sendGetSleepDataCommand()` | `0x53` | Sleep sessions with per-minute stages |
| `sendGetDetailedHeartRateCommand()` | `0x54` | 15 HR readings per record (5-sec intervals) |
| `sendGetHeartRateHistoryCommand()` | `0x55` | Individual HR measurements |
| `sendHrvCommand()` | `0x56` | HRV + blood pressure + fatigue records |
| `sendGetTemperatureDataCommand()` | `0x62` | Temperature measurement history |
| `sendGetBloodOxygenDataCommand()` | `0x66` | SpO2 measurement history |

#### Exercise History Commands

```dart
Future<void> sendGetExerciseModeDataLatest({
  // Optional: filter by timestamp
  int year = 0, int month = 0, int day = 0,
  int hour = 0, int minute = 0, int second = 0,
}) async
```

Sends `0x5C 00 ...` to retrieve the latest exercise history records.

```dart
Future<void> sendGetExerciseModeDataContinue() async
```

Sends `0x5C 02 ...` to continue reading the next batch.

```dart
Future<void> sendDeleteExerciseModeDetails() async
```

Sends `0x5C 99 ...` to delete all stored exercise records.

---

### High-Level Data Fetching

These methods handle multi-packet assembly and return typed Dart objects.

#### `fetchHrvData`

```dart
Future<List<HrvRecord>> fetchHrvData({
  Duration timeout = const Duration(seconds: 2),
}) async
```

Sends `0x56`, waits for `timeout`, parses all received `0x56` packets, deduplicates by `(index, page)`, and returns a sorted `List<HrvRecord>`.

**Example:**
```dart
final records = await ble.fetchHrvData(timeout: Duration(seconds: 3));
for (final r in records) {
  print('${r.timestamp}: HRV=${r.hrvMs}ms, HR=${r.heartRateBpm}bpm, Stress=${r.fatigue}');
}
```

#### `fetchSleepData`

```dart
Future<List<SleepRecord>> fetchSleepData({
  Duration timeout = const Duration(seconds: 2),
}) async
```

Sends `0x53`, waits for `timeout`, parses all `0x53` packets, deduplicates and merges by night window (18:00–12:00). Returns an unmodifiable sorted `List<SleepRecord>`.

**Example:**
```dart
final nights = await ble.fetchSleepData(timeout: Duration(seconds: 4));
for (final night in nights) {
  print('${night.startTimestamp.toLocal()}: '
        '${night.durationMinutes}min total — '
        'Deep=${night.deepMinutes}min Light=${night.lightMinutes}min '
        'REM=${night.remMinutes}min Awake=${night.awakeMinutes}min');
}
```

#### `bulkDownloadAllData`

```dart
Future<Map<String, dynamic>> bulkDownloadAllData({
  Function(String)? onProgress,
}) async
```

Sequentially sends 8 commands with 2-second delays each, collects all responses with a 5-second inactivity timeout, and returns a structured map.

**`onProgress` callback** receives status strings like:
```
"📦 Sending 0x51 (total_steps)..."
"📦 Sending 0x52 (detailed_steps)..."
...
"✅ Collection complete: 245 records"
```

**Return value structure:**

```dart
{
  'timestamp': '2025-02-27T14:30:00.000Z',   // ISO8601
  'total_records': 245,                        // Sum of all records
  'summary': '...',                            // Human-readable summary
  'commands': {
    'total_steps': {
      'count': 15,
      'records': ['0x51 00 24 08 27 ...', ...],
    },
    'detailed_steps': { 'count': 150, 'records': [...] },
    'sleep':          { 'count': 12,  'records': [...] },
    'heart_rate_details': { 'count': 20, 'records': [...] },
    'heart_rate_history': { 'count': 30, 'records': [...] },
    'hrv':            { 'count': 10,  'records': [...] },
    'temperature':    { 'count': 11,  'records': [...] },
    'blood_oxygen':   { 'count': 17,  'records': [...] },
  }
}
```

**Example:**
```dart
final data = await ble.bulkDownloadAllData(
  onProgress: (msg) => setState(() => _status = msg),
);
final hrvRecords = data['commands']['hrv']['records'] as List;
print('Downloaded ${data['total_records']} records');
```

---

### Raw Message Sending

```dart
Future<void> sendMessage(String hexMessage) async
```

Sends any arbitrary hex string directly to the ring. Accepts hex bytes separated by spaces, dashes, or no separator.

**Examples:**
```dart
await ble.sendMessage('41 00 00 00 00 00 00 00 00 00 00 00 00 00 00 41'); // Get time
await ble.sendMessage('56-00-00-00-00-00-00-00-00-00-00-00-00-00-00-56'); // Get HRV
```

> **Note:** The library does not auto-compute CRC when using `sendMessage`. You must provide the correct CRC byte or use the dedicated command methods which compute it automatically.

---

## Response Parsing

The library automatically parses all incoming BLE packets and emits human-readable strings on `messageStream`. No manual parsing is required for typical use.

### Parsed Message Format

Each `messageStream` emission is a UTF-8 string. Multi-record responses (e.g., 0x56 history) emit one string per record.

### Command Response Reference

| Command | Success Response on `messageStream` |
|---------|--------------------------------------|
| `0x01` Set time | `✅ Set Time: Success (MTU=244)` |
| `0x02` Set user info | `✅ Set User Info: Success` |
| `0x09` Real-time data | `📡 Real-time Mode: Steps=N \| Cal=X kcal \| Dist=Y km \| HR=Z bpm \| Temp=T°C \| SpO2=S%` |
| `0x13` Battery | `🔋 Battery: 85% \| Charging: No \| Voltage: 4.12V` |
| `0x14` Ring temp | `🌡️ Ring Temp: 32.8°C (decimal: 32.8°C) \| NTC1: 32.5°C ...` |
| `0x18` Live exercise | `🏃 Live Exercise: HR=132 bpm \| Steps=850 \| Cal=48.5 kcal \| Time=0:05:30 \| Dist=0.62 km` |
| `0x19` Exercise status | `🏃 Exercise: Started at 2025-02-27 14:30:00` |
| `0x22` MAC address | `📍 MAC: F8:19:23:14:5C:C8` |
| `0x27` Firmware | `🔧 Firmware: v1.2.3.4 (2025-01-15) ID: 0xAB` |
| `0x28` Measurement | `📊 Measurement Status: HR active (mode=1)` |
| `0x2A` Set interval | `✅ Measurement Interval Set: Success` |
| `0x2B` Get interval | `⏰ Measurement Interval [SpO2]: Mode=Interval \| 00:00–23:59 \| All days \| Every 5 min` |
| `0x41` Get time | `🕐 Time: 2025-02-27 14:30:00 (Thursday) \| BT MTU: 244` |
| `0x42` Get user info | `👤 User Info: Male, Age 25, Height 175cm, Weight 70kg, Step 75cm \| Ring ID: LUMIE1` |
| `0x51` Total steps | `👣 Daily Steps [2025-08-27]: 226 steps \| Exercise: 17s \| Dist: 0.03km \| Cal: 1.47kcal` |
| `0x52` Detail steps | `📊 Step Detail [ID=9]: 2025-08-27 09:10:19 \| Steps=33 \| Cal=1.30kcal \| Dist=0.00km \| Per-min: [14, 4, ...]` |
| `0x53` Sleep | `😴 Sleep [ID=0]: 2024-08-23 13:36 \| 36min total (Deep=Xmin Light=Ymin REM=Zmin Awake=Wmin)` |
| `0x54` HR detail | `❤️ HR Detail [ID=1]: 2024-08-08 22:58:12 \| Readings (5s): [76, 73, 74, 77, 80, ...]` |
| `0x55` HR history | `💓 HR History [ID=0]: 2024-08-27 09:01:30 \| HR=70 bpm` |
| `0x56` HRV | `🫀 HRV [ID=0]: 2025-07-02 13:58:48 \| HRV=57ms HR=61bpm Fatigue=30 BP=119/62` |
| `0x5C` Exercise history | `🏃 Exercise Mode Data [ID=0]: 2024-09-03 10:36:47 \| Running \| HR=138bpm \| Time=1:07 \| Steps=117 \| Cal=2.39kcal \| Dist=0.06km \| Pace=0:00/km` |
| `0x62` Temperature | `🌡️ Temp [ID=0]: 2024-08-27 08:56:59 \| 34.6°C / 34.5°C / 32.9°C` |
| `0x66` Blood oxygen | `🫁 SpO2 [ID=1]: 2024-08-27 09:00:19 \| SpO2=98%` |

**Error responses** include the original command with bit 7 set and a description, e.g.:
```
❌ Error response for command 0x13 (battery) — CRC error or execution failure
```

---

## Usage Examples

### Minimal Integration

```dart
import 'package:smart_ring_ble_lib/ble_service.dart';

class RingController {
  final BleService _ble = BleService(macAddress: 'F8:19:23:14:5C:C8');

  Future<void> init() async {
    _ble.connectionStatusStream.listen((status) {
      print('Connection: $status');
    });
    _ble.messageStream.listen((msg) {
      print('Data: $msg');
    });
    await _ble.connectToSmartRing();
  }

  Future<void> dispose() async {
    await _ble.dispose();
  }
}
```

### Reading Battery and Device Info

```dart
await _ble.connectToSmartRing();
await _ble.sendGetBatteryCommand();
await _ble.sendGetTimeCommand();
await _ble.sendGetFirmwareVersionCommand();
await _ble.sendGetMacAddressCommand();
// Responses appear on messageStream
```

### Real-time Heart Rate Monitoring

```dart
// Start streaming
await _ble.sendStartRealtimeMode(enableTemperature: true);

// Listen for live data
_ble.messageStream.listen((msg) {
  if (msg.startsWith('📡 Real-time Mode:')) {
    // Parse HR from: "📡 Real-time Mode: Steps=X | Cal=Y | Dist=Z | HR=W bpm | ..."
    final hrMatch = RegExp(r'HR=(\d+) bpm').firstMatch(msg);
    if (hrMatch != null) {
      final hr = int.parse(hrMatch.group(1)!);
      print('Heart rate: $hr bpm');
    }
  }
});

// Stop after a while
await Future.delayed(Duration(seconds: 60));
await _ble.sendStopRealtimeMode();
```

### On-demand HRV Measurement

```dart
// Start 60-second HRV measurement
await _ble.sendStartMultiParamMeasurement(mode: 0x01, durationSeconds: 60);

// Poll real-time data while measuring
await _ble.sendStartRealtimeMode();

// After measurement completes, fetch results
await Future.delayed(Duration(seconds: 65));
await _ble.sendStopRealtimeMode();

final hrvRecords = await _ble.fetchHrvData(timeout: Duration(seconds: 3));
for (final r in hrvRecords) {
  print('HRV: ${r.hrvMs}ms, Fatigue: ${r.fatigue}, BP: ${r.systolic}/${r.diastolic}');
}
```

### Fetching Sleep History

```dart
final nights = await _ble.fetchSleepData(timeout: Duration(seconds: 5));
for (final night in nights) {
  final start = night.startTimestamp.toLocal();
  print('Night of ${start.year}-${start.month}-${start.day}: '
        '${night.durationMinutes} min | '
        'Deep=${night.deepMinutes}min REM=${night.remMinutes}min');
}
```

### Bulk Download All Health Data

```dart
String progressStatus = '';

final data = await _ble.bulkDownloadAllData(
  onProgress: (msg) {
    setState(() => progressStatus = msg);
  },
);

print('Total records: ${data['total_records']}');
print(data['summary']);

// Access specific data type
final spO2Records = data['commands']['blood_oxygen']['records'] as List;
print('SpO2 entries: ${spO2Records.length}');
```

### Exercise Session

```dart
// Start exercise
await _ble.sendStartExerciseCommand();
await _ble.sendStartRealtimeMode();

// Listen for live exercise updates (0x18 packets arrive automatically)
_ble.messageStream.listen((msg) {
  if (msg.startsWith('🏃 Live Exercise:')) {
    print(msg);
  }
  // Ring may auto-end exercise after inactivity:
  if (msg.contains('Exercise ended') || msg.contains('FF')) {
    print('Exercise auto-ended by ring');
  }
});

// End exercise manually
await _ble.sendStopRealtimeMode();
await _ble.sendEndExerciseCommand();

// Fetch stored exercise records
await _ble.sendGetExerciseModeDataLatest();
```

### Configuring Automatic SpO2 Monitoring

```dart
// Measure SpO2 every 15 minutes, Mon–Fri, 8:00–22:00
await _ble.sendSetMeasurementIntervalCommand(
  measurementType: 2,         // SpO2
  workingMode: 2,             // Interval mode
  startHour: 8,
  startMinute: 0,
  endHour: 22,
  endMinute: 0,
  weekdayBits: 0x3E,          // Mon–Fri (bits 1–5)
  intervalMinutes: 15,
);

// Verify the setting was applied
await _ble.sendGetMeasurementIntervalCommand(2);
```

---

## Error Handling

All command methods throw exceptions on BLE write failure. Wrap in try/catch:

```dart
try {
  await _ble.sendGetBatteryCommand();
} catch (e) {
  print('BLE error: $e');
}
```

Error responses from the ring (bit 7 set on command byte) are emitted on `messageStream` with `❌` prefix and do not throw.

**Common error scenarios:**
| Scenario | Handling |
|----------|----------|
| Not connected | Exception thrown from `sendMessage` |
| CRC error on ring side | Error response on `messageStream` (0x80+cmd) |
| Conflicting exercise start | `0xA6` response on `messageStream` |
| Timeout during `fetchHrvData` / `fetchSleepData` | Returns whatever was collected before timeout |
| Disconnection | `connectionStatusStream` emits "Disconnected", auto-reconnect fires after 5s |

---

## Protocol Quick Reference

| Command | Hex | Function |
|---------|-----|----------|
| Set time | `0x01` | Write clock to ring |
| Set user info | `0x02` | Gender, age, height, weight, step length |
| Real-time stream | `0x09` | Start/stop HR/steps/SpO2/temp streaming |
| Factory reset | `0x12` | Restore factory settings (enters sleep mode) |
| Read battery | `0x13` | Battery %, charging status, voltage |
| Read ring temp | `0x14` | Real-time temperature from 3 NTC sensors |
| Exercise control | `0x19` | Start/pause/resume/end/query exercise |
| Read MAC | `0x22` | Bluetooth MAC address |
| Read firmware | `0x27` | Software version and build date |
| Multi-param measure | `0x28` | HR, HRV/BP, or SpO2 on-demand measurement |
| Set meas. interval | `0x2A` | Auto-measurement schedule |
| Get meas. interval | `0x2B` | Read auto-measurement schedule |
| MCU reset | `0x2E` | Soft-reset the ring MCU |
| Get time | `0x41` | Read clock from ring |
| Get user info | `0x42` | Read stored personal info |
| Set ring ID | `0x05` | Write 6-byte device ID |
| Total steps | `0x51` | Daily step summaries (up to 15 days) |
| Detailed steps | `0x52` | Per-10-minute step data |
| Sleep data | `0x53` | Nightly sleep with per-minute stages |
| HR detail | `0x54` | 15 readings/record @ 5-sec intervals |
| HR history | `0x55` | Individual HR measurement records |
| HRV / stress | `0x56` | HRV ms, fatigue, blood pressure |
| Exercise history | `0x5C` | Stored exercise sessions (run, cycle, etc.) |
| Temperature history | `0x62` | Stored temperature measurements |
| Blood oxygen history | `0x66` | Stored SpO2 measurements |

**Exercise types** (used in `0x19` BB field and `0x5C` TY field):

| Value | Sport |
|-------|-------|
| 0 | Run |
| 1 | Cycling |
| 2 | Badminton |
| 3 | Football |
| 4 | Tennis |
| 5 | Yoga |
| 6 | Meditation |
| 7 | Dance |
| 8 | Basketball |
| 9 | Walk |
| 10 | Workout |
| 11 | Cricket |
| 12 | Hiking |
| 13 | Aerobics |
| 14 | Ping-Pong |
| 15 | Rope Jump |
| 16 | Sit-ups |
| 17 | Volleyball |
