# Gaze Analysis (Option C) — post-hoc eye-pointer tracking

Measures where the participant looked (road / HUD / PsychoPy) **without** rebuilding
anything: keep Moonlight, PsychoPy, and the HUD as their own windows, record the
session with the visionOS accessibility eye-pointer visible, and analyze the
recording afterward.

This is the chosen approach because it gives **true eye gaze** (head-direction
tracking would miss the quick eye-only glances a font/HUD-readability study cares
about) and requires no streaming/immersive-space integration.

> ⚠️ Limits: the eye-pointer is uncalibrated and gives **no pupil/blink**. If the
> study needs pupillometry or fixation-grade gaze, the Vision Pro can't provide it
> on any path — that needs a dedicated eye tracker on a monitor.

## Setup
```bash
pip install -r requirements.txt        # opencv-python, numpy
```

## Capture a session (the pilot/validation checklist)
1. **Lay out the windows** in the headset: Moonlight (road), PsychoPy, and the HUD,
   in fixed positions — don't move them mid-session (the regions are fixed boxes).
2. **Turn on the eye-pointer:** Settings → Accessibility → **Pointer Control** →
   set the pointer to follow **eyes**. Make it **large and a distinctive solid
   color** (e.g. bright magenta) — this is what makes detection reliable.
   *(Verify the exact toggles on your visionOS build; confirm it doesn't trigger
   dwell-clicks during a trial.)*
3. **Record:** screen-record on the headset (Control Center) or capture the mirror
   on the Mac/iPad. Save the video.
4. **Validate before a real run:** do a 2-minute test where you deliberately look
   road → HUD → PsychoPy → road, then run the analysis with `--overlay` and watch
   `gaze_overlay.mp4`. Confirm the detected dot tracks your eyes and lands in the
   right boxes. Tune until `detection_rate_pct` is high (>~90%).

## Analyze
```bash
# 1) define the regions once per layout (draw boxes on a reference frame)
python3 define_regions.py session.mp4 --frame 300 --out regions.json

# 2) (recommended) tune detection to your pointer color in regions.json
#    -> "detect.hsv_lower"/"hsv_upper", or switch to template matching:
#       "detect": {"method": "template", "threshold": 0.6}  + --template dot.png

# 3) run the analysis (always use --overlay the first time)
python3 gaze_analysis.py session.mp4 --regions regions.json --out ./out --overlay
```

## Outputs (`./out`)
| file | what |
|---|---|
| `gaze_overlay.mp4` | the video with regions + detected dot drawn — **check this first** |
| `gaze_frames.csv` | per frame: `frame, t_s, x, y, region, confidence` |
| `gaze_summary.json` | per region: % of detected time, glance count, mean glance ms, time-to-first-fixation; plus detection rate + transitions |

## Merging with telemetry
`gaze_frames.csv` is timestamped (`t_s` from the recording). Align it to your Mac
Mini telemetry by wall-clock — drop a visible sync marker at session start (e.g.
press the HUD "Mark" button on camera) so the recording clock and the telemetry
`SESSION_START` line up.

## Tuning detection
- **Color method (default):** set a vivid pointer color, then set the HSV range to
  match it. Use `--overlay` to confirm the blob is the pointer and nothing else.
- **Template method:** crop a small PNG of the pointer from one frame, set
  `"method": "template"`, pass `--template dot.png`. More robust on busy scenes.
- Raise `--min-glance-ms` to ignore detection jitter when counting glances.
