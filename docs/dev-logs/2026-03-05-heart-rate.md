# Dev Log: Heart Rate Feature
**Date:** 2026-03-05

## What Was Built

A Heart Rate screen accessible from a tappable card on the Dashboard. When the ring is connected, users can view today's HR trend chart and take an on-demand 15-second heart rate measurement.

## Decisions Made

- **No backend required:** All HR data is fetched directly from the ring via BLE. The ring stores HR history internally (command 0x55); live measurement uses real-time streaming (command 0x09).
- **`ChangeNotifierProxyProvider`:** `HeartRateProvider` depends on `RingProvider` for BLE access. Used `ChangeNotifierProxyProvider` so it automatically receives updated `RingProvider` references on each notify, and auto-fetches history when the ring first becomes paired.
- **`fl_chart` library added** (`^0.68.0`) for the daily trend line chart. No chart library previously existed in the project.
- **Daily history fetch:** On screen open (when ring is paired), the app sends a 0x55 command and collects response packets for up to 3 seconds or until the end-of-data marker (`0x55 0xFF`). Only today's readings are kept.
- **Live measurement:** Sends 0x09 start (streaming with temp enabled), subscribes to notify stream, emits each valid HR value (0 < hr < 250). Auto-stops after 15 seconds via `Timer`. User can also stop manually.
- **Dashboard card hidden when ring unpaired** — `Consumer2<RingProvider, HeartRateProvider>` returns `SizedBox.shrink()` if ring is not paired.

## New Files Created

**Frontend:**
- `lib/shared/models/heart_rate_models.dart` — `HrDataPoint` model (`time`, `bpm`)
- `lib/features/heart_rate/providers/heart_rate_provider.dart` — `HeartRateProvider` (ChangeNotifier): manages daily readings, measure state, live BPM, auto-stop timer
- `lib/features/heart_rate/screens/heart_rate_screen.dart` — Full HR screen with trend chart, stats row, and animated measure section

## Modified Files

- `pubspec.yaml` — Added `fl_chart: ^0.68.0`
- `lib/core/services/ring_ble_service.dart`:
  - Added `fetchHrHistory()` — command 0x55, collects today's stored readings
  - Added `startHrStreaming()` — command 0x09, returns `Stream<int>` of BPM values
  - Added `stopHrStreaming()` — command 0x09 stop, cleans up subscription/controller
  - Updated `disconnect()` to cancel HR stream subscription and close controller
- `lib/features/ring/providers/ring_provider.dart` — Added 3 delegation methods (`fetchHrHistory`, `startHrStreaming`, `stopHrStreaming`) guarded by `isPaired`
- `lib/main.dart` — Added `HeartRateProvider` (via `ChangeNotifierProxyProvider`) and `/heart-rate` route
- `lib/features/dashboard/screens/dashboard_screen.dart` — Added `_buildHrCard()` which renders between the score row and activity ring; hidden when ring not paired

## API Endpoints Added

None — feature is entirely BLE-local.

## New DB Collections / Indexes

None.

## BLE Commands Used

| Command | Purpose |
|---|---|
| `0x55` (byte[1]=0x00) | Fetch stored HR history from ring; end marker is `0x55 0xFF` |
| `0x09` (byte[1]=0x01, byte[2]=0x01) | Start real-time HR streaming (~1 update/sec) |
| `0x09` (byte[1]=0x00) | Stop real-time HR streaming |

**Response parsing:**
- 0x55 records: 10 bytes — BCD timestamp at bytes [3..8], BPM at byte [9]
- 0x09 Format A (16 bytes): HR at byte [13]
- 0x09 Format B (26 bytes): HR at byte [21]

## Testing Checklist

- [ ] Ring paired → HR card appears on Dashboard with last BPM or "Tap to measure"
- [ ] Ring unpaired → HR card hidden on Dashboard
- [ ] Tap card → navigates to `/heart-rate`
- [ ] Screen opens → `fetchDailyHistory()` called → 0x55 sent to ring → today's readings populate chart
- [ ] Chart renders with time on X axis, BPM on Y axis; tooltip on touch shows exact time + BPM
- [ ] Stats row shows Avg / Min / Max when readings exist
- [ ] Tap "Measure Heart Rate" → heart pulse animation starts, live BPM updates, countdown from 15
- [ ] After 15s → auto-stops, shows final BPM prominently
- [ ] "Stop" button mid-measurement → stops early, shows last reading
- [ ] "Measure Again" → resets to idle state
- [ ] Result BPM appended to trend chart after measurement

## Future Work / Deferred

- **Backend persistence:** Currently all HR data is ring-local. Future work: upload via `POST /ring/sync/upload` with `data_type: "heart_rate"` so history persists across ring disconnects.
- **Background polling:** Could run 0x09 streaming passively while app is open to build a richer intraday trend.
- **Scheduled measurements (0x2A):** Program ring to auto-measure HR on a repeating interval without the app being active.
- **HR history pagination:** 0x55 with `byte[1]=0x02` continues fetching older pages; current implementation only fetches the latest batch.
