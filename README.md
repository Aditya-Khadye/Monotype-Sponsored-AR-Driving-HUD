# BeamNG HUD v2 — Data Collection Pipeline

AR driving telemetry HUD for Apple Vision Pro with synchronized data collection, 
real-time analysis, and streaming to a Mac Mini hub.

## Architecture

```
Vision Pro                                Mac Mini (Hub)
┌────────────────────────────────┐       ┌─────────────────────────────┐
│                                │       │                             │
│  BeamNG UDP :4444              │       │  mac_receiver.py :5555      │
│    ↓                           │       │    ↓                        │
│  UDPReceiver                   │       │  Session auto-detection     │
│    ↓                           │       │    ↓                        │
│  SessionManager                │       │  data/sessions/             │
│    ├─ SessionClock (time-lock) │       │    └─ 20260413_142530/      │
│    ├─ TelemetryRecord          │──TCP──│       ├─ telemetry.json     │
│    ├─ RingBuffer (60s local)   │ NDJSON│       ├─ telemetry.csv      │
│    ├─ DrivingAnalyzer (CoreML) │       │       ├─ analysis_events.json│
│    └─ NetworkStreamer           │       │       └─ session_meta.json  │
│                                │       │                             │
│  SpeedHUD (world-anchored)     │       └─────────────────────────────┘
│  ControlPanel (session mgmt)   │
└────────────────────────────────┘
```

## New in v2

### Time-locking engine (`SessionClock`)
Every data source gets stamped with:
- **sessionTimeMs** — monotonic offset from session start (for synchronizing subsystems)
- **utcISO** — wall-clock UTC (for absolute reference)
- **epochSeconds** — Unix timestamp (for sorting/merging in R/Python)

### Data collection (`SessionManager`)
- Manual start/stop via control panel
- Auto-start when first packet arrives, auto-stop after 10s silence
- Manual event markers (flag button in UI)
- Ring buffer holds last 60s on-device for network resilience

### Driving analysis (`DrivingAnalyzer`)
Rule-based detection (CoreML-ready structure):

**Driving behavior:**
- Hard braking (brake delta > 0.4 in 250ms)
- Rapid acceleration (throttle delta > 0.5 in 250ms)  
- Gear hunting (4+ gear changes in 2s)

**Cognitive load indicators:**
- Erratic throttle (high variance over 1s window)
- Prolonged high RPM (6500+ for 1.5s)

Events are logged with confidence scores and details, streamed alongside telemetry.

### Mac Mini receiver (`mac_receiver.py`)
- TCP server on port 5555
- Receives NDJSON, writes JSON + CSV per session
- Auto-detects session boundaries
- Separate analysis_events.json for quick review
- Session metadata with summary stats

## File structure

```
BeamNGHUD_v2/
├── BeamNGHUD/
│   ├── BeamNGHUDApp.swift              ← App entry point
│   ├── OutGaugePacket.swift            ← 96-byte packet parser (from v1)
│   ├── UDPReceiver.swift               ← UDP listener (from v1)
│   ├── SpeedHUDView.swift              ← World-anchored HUD (from v1)
│   ├── ControlPanelView.swift          ← Session management UI (NEW)
│   ├── Info.plist
│   ├── BeamNGHUD.entitlements
│   │
│   ├── DataCollection/                  ← NEW: Data pipeline
│   │   ├── SessionClock.swift          ← Monotonic time-locking
│   │   ├── TelemetryRecord.swift       ← Canonical data record
│   │   ├── RingBuffer.swift            ← On-device buffer
│   │   ├── NetworkStreamer.swift        ← TCP streamer to Mac Mini
│   │   └── SessionManager.swift        ← Pipeline orchestrator
│   │
│   └── Analysis/                        ← NEW: On-device analysis
│       └── DrivingAnalyzer.swift       ← Rule-based (CoreML-ready)
│
├── MacMini/
│   └── mac_receiver.py                  ← NEW: Data hub server
│
├── BeamNG_Side/
│   └── outgauge.lua                     ← Lua extension (from v1)
│
└── Testing/
    └── mock_emitter.py                  ← Fake packet sender (from v1)
```

## Quick start

### 1. Mac Mini (start receiver first)
```bash
cd MacMini
python3 mac_receiver.py --port 5555
```

### 2. Vision Pro
- Open the app → Control Panel window
- Enter Mac Mini IP address
- Toggle auto-start or hit "Start" manually
- The HUD appears in immersive space

### 3. BeamNG (on gaming PC)
- Copy `outgauge.lua` to BeamNG extensions folder
- Set `TARGET_IP` to Vision Pro's IP
- Activate extension in-game
- Spawn vehicle and drive

### 4. Data output
Sessions appear in `data/sessions/<session_id>/`:
- `telemetry.json` — full structured data
- `telemetry.csv` — tabular for R/Python analysis
- `analysis_events.json` — flagged driving events only
- `session_meta.json` — summary stats

## Upgrading to CoreML

The `DrivingAnalyzer` is structured to swap in a CoreML model:

1. Train a classifier on collected CSV data (labels from rule-based events)
2. Export as `.mlmodel` via Create ML or coremltools
3. Add the model to the Xcode project
4. Replace rule-based logic in `analyze()` with:
```swift
let model = try DrivingClassifier(configuration: .init())
let input = DrivingClassifierInput(features: windowFeatures)
let output = try model.prediction(input: input)
```

The record structure, streaming, and storage all stay the same.

## Network requirements

| Connection          | Protocol | Port | Direction              |
|---------------------|----------|------|------------------------|
| BeamNG → Vision Pro | UDP      | 4444 | PC → Vision Pro        |
| Vision Pro → Mac    | TCP      | 5555 | Vision Pro → Mac Mini  |

All devices must be on the same LAN/WiFi network.
