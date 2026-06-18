# Gaze / Attention Tracking — Plan & Decision Record

## Research question
Detect **when the participant's attention leaves the driving stream (Moonlight/BeamNG)**
and where it goes — the **HUD**, the **PsychoPy** stream, or elsewhere. Three visual
surfaces total: road (Moonlight), PsychoPy, BeamNG HUD.

## Hard platform constraints (verified)
1. **No eye gaze / pupil / blink to apps.** visionOS never exposes raw eye-tracking data
   to third-party apps (privacy) — not via ARKit, not via enterprise APIs. The
   `gazeX/Y/Z`, `leftPupilDilation`, `rightPupilDilation`, `blinkDetected` fields and the
   `// ARKit eye tracking (future)` comment in `TelemetryRecord.swift` are based on a
   capability that does not and will not exist. **They must be removed/repurposed.**
2. **Head pose requires an immersive space.** `WorldTrackingProvider.queryDeviceAnchor`
   only delivers head/device pose when the app has an `ImmersiveSpace` open. In plain
   windowed "shared space" the app gets no head/gaze data at all.
3. **Opening an immersive space dismisses other apps.** When our HUD opens its immersive
   space, Moonlight and PsychoPy (separate apps) are hidden. visionOS 26 `.coexist` only
   covers the system *environment*, not other apps. And apps cannot read each other's
   window positions anyway.

### Consequence
We **cannot** keep Moonlight/PsychoPy as separate windows *and* get a live tracking
signal. A live signal requires our app to **own all three surfaces** inside its own
immersive space.

## Decision: hybrid (live head-direction + post-hoc true gaze)
- **Live, automatic:** our app renders road + HUD + PsychoPy as surfaces it places in one
  immersive space; `WorldTrackingProvider` head pose → head-ray → `lookRegion` + dwell +
  "left-road" transition events, time-locked via `SessionClock`, streamed to the Mac Mini.
  *Head-resolution only — misses eye-only flicks.*
- **Post-hoc, precise:** enable Accessibility → Pointer Control (eyes) so a gaze dot
  follows the eyes; screen-record over the scene; map dot → region frame-by-frame.
  *True eye gaze; uncalibrated; no pupil/blink.*

### Layout (flexible — design for the method)
Spread the three surfaces ≥ ~25–30° apart so attention switches require a head turn →
makes the live head signal a reliable classifier. Tradeoff: realistic near-road HUDs
produce eye-only glances → for those, rely on the post-hoc gaze dot.

## ⚠️ Make-or-break gate (do before the full rebuild)
**Can BeamNG stream into a visionOS app at drivable latency (~sub-150 ms glass-to-glass)?**
Since Moonlight-as-an-app can't coexist with our immersive space, we must ingest the
stream ourselves (WebRTC preferred; low-latency RTSP fallback).
- **Green** → full Option B (live signal over real driving).
- **Red** → Option C is the primary measure (windowed Moonlight + post-hoc gaze dot);
  head-tracking becomes a separate non-live calibration/validation condition.

## Phased plan
| Phase | What | Owner | Depends on |
|---|---|---|---|
| **C pilot** | Eye-pointer + screen-record on existing windowed app; map dot→region post-hoc | You | nothing — **start now** |
| **Gate** | Low-latency BeamNG→visionOS video spike; measure latency | You (+ spec from me) | gaming PC + LAN |
| **Phase 0** | ImmersiveSpace + WorldTrackingProvider + region classifier + dwell/left-road events; fix schema | Me | nothing (placeholders) |
| **Phase 1** | Real BeamNG stream on the road plane | Me | Gate green |
| **Phase 2** | PsychoPy surface — stream window or reimplement stimuli natively | Me | what PsychoPy shows |
| **Phase 3** | Post-hoc gaze-dot→region extractor, merged with live head data by timestamp | Me | C pilot recordings |

## Schema change (Phase 0)
Replace in `TelemetryRecord.swift` + `mac_receiver.py` CSV:
- remove: `gazeX/Y/Z`, `leftPupilDilation`, `rightPupilDilation`, `blinkDetected`
- add: `headYaw`, `headPitch`, `lookRegion` (road|hud|psychopy|other), `dwellMs`
