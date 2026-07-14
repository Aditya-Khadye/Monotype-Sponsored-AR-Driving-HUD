# Apple Vision Pro — Setup & Test Guide

For anyone setting up or testing the Vision Pro side of the driving sim project (Amy, RAs, or anyone new to the headset). Companion to `SETUP.md`, which covers the full PC/Vision Pro/Mac Mini pipeline. This doc is scoped to the Vision Pro specifically: pairing it, deploying the app, verifying telemetry, and setting up gaze recording.

Repo: `Monotype-Sponsored-AR-Driving-HUD`

## 1. First-time headset setup

If this Vision Pro has never been used for development before:

1. **Pair with the Mac.** On the Vision Pro: Settings → General → Remote Devices. The Mac running Xcode must be on the same WiFi network as the headset. Select the Mac when it appears and confirm the pairing code on both devices.
2. **Enable Developer Mode.** Settings → Privacy & Security → Developer Mode → toggle on. The headset will restart.
3. **Trust the developer certificate**, if this is the first time an app built by this Apple ID has been installed. Settings → General → VPN & Device Management → select the developer profile → Trust.

If the headset has already been used for this project before, skip to step 2.

## 2. Deploying the app

On the Mac connected to the headset:

```bash
git clone https://github.com/Aditya-Khadye/Monotype-Sponsored-AR-Driving-HUD.git
cd Monotype-Sponsored-AR-Driving-HUD
open BeamNGHUD.xcodeproj
```

In Xcode:

1. Select the **BeamNGHUD** target, go to **Signing & Capabilities**, and make sure a development team is selected.
2. In the toolbar, select the paired Vision Pro as the build destination (it will appear by name once step 1 above is done).
3. Build and run (⌘R). The app installs and launches on the headset automatically.

If you get a signing error, the Apple ID on the Mac needs to be added under Xcode → Settings → Accounts, and needs to be a member of the development team.

## 3. Verifying telemetry is working

This confirms the core pipeline (PC → Vision Pro → Mac Mini) is intact before running anything with a participant.

1. On the Windows PC, launch BeamNG.drive and spawn a vehicle. Confirm OutGauge is pointed at the Vision Pro's current IP (Options → Other → Protocols → OutGauge UDP — see `SETUP.md` for full details if this needs configuring from scratch).
2. On the Mac Mini, run the receiver:
   ```bash
   cd ~/Downloads/BeamNGHUD_v3/MacMini
   python3 mac_receiver.py
   ```
3. On the Vision Pro, open the BeamNGHUD app and tap **Open HUD Window**. The UDP indicator in the control panel should turn green, and live speed/RPM/gear should appear on the HUD as you drive.
4. Tap **Start** in the control panel to begin recording, drive for a minute, then tap **Stop**. On the Mac Mini, a new folder should appear under `MacMini/data/sessions/` with `telemetry.json`, `telemetry.csv`, and `session_meta.json` inside. Open the CSV to confirm the values look sane (speed climbing, RPM changing with gear).

If the HUD shows "WAITING..." instead of live values, the Vision Pro and PC are most likely on different networks, or the IP entered in BeamNG's OutGauge settings is stale (the Vision Pro's IP can change between WiFi reconnects). Recheck the Vision Pro's current IP under Settings → WiFi → (network name) → IP Address.

## 4. Setting up gaze recording

This is the current approach for capturing where the participant is looking (road / HUD / task screen) during a session. It works by recording the session with the Vision Pro's accessibility eye-pointer visible, then analyzing the recording afterward — no extra hardware or app changes needed. Full detail and the analysis scripts are in the `GazeAnalysis/` folder in the repo; this section is the on-headset setup piece.

1. **Turn on the eye-pointer.** On the Vision Pro: Settings → Accessibility → Pointer Control → set the pointer to follow **Eyes**.
2. **Make the pointer visible and distinct.** In the same menu, set the pointer to a large size and a solid, unusual color (bright magenta works well) so it's easy to isolate in the recording later.
3. **Check dwell-click is off**, or set to a long enough delay that it won't fire accidentally while the participant is just looking around. This matters — if it's on a short dwell, looking at something for a moment could trigger an unintended tap.
4. **Lay out the windows** (Moonlight driving view, PsychoPy, HUD) in fixed positions before recording starts. The gaze analysis defines regions as fixed boxes in the video frame, so windows moving mid-session will throw off the region detection.
5. **Start screen recording** before the driving session begins — either on-headset via Control Center, or by mirroring to a Mac/iPad and recording there.
6. **Run a 2-minute validation pass** before any real session: deliberately look road → HUD → PsychoPy → road, stop the recording, and run it through the analysis scripts with `--overlay` to confirm the pointer is being detected reliably and landing in the right regions. Instructions for this are in `GazeAnalysis/README.md`.

Known limits, worth knowing going in: the eye-pointer gives real eye-gaze direction (not head direction), but it's uncalibrated and there's no pupil or blink data from this method. It's suited to region-level attention questions (how much time did the participant spend looking at the HUD vs. the road), not fixation-precision or pupillometry research questions.

## 5. Quick troubleshooting

| Symptom | Likely cause |
|---|---|
| App won't install / signing error | Apple ID not added to Xcode, or not on the dev team |
| Vision Pro doesn't show up as a build destination | Not paired yet, or not on the same WiFi as the Mac |
| HUD shows "WAITING..." | Vision Pro/PC on different networks, or stale IP in BeamNG's OutGauge settings |
| HUD frozen on stale values | Close and reopen the HUD window from the control panel (known visionOS quirk) |
| Headset feels hot / performance drops during long sessions | Known thermal limit with extended streaming — build in breaks between sessions |
| Eye-pointer not detected reliably in analysis | Pointer color/size not distinct enough, or lighting in the recording is inconsistent — see tuning notes in `GazeAnalysis/README.md` |

## Contact

Aditya Khadye — Sawyer Lab, UCF
