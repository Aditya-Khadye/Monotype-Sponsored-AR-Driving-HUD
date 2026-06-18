#!/usr/bin/env python3
"""
Define the screen regions (road / hud / psychopy / ...) for gaze_analysis.py
by drawing boxes on a reference frame of your recording.

Usage:
  python3 define_regions.py session.mp4 --frame 300 --out regions.json
  # for each region: drag a box, press ENTER/SPACE to accept (or just ENTER to skip)

Tip: pick a --frame where all surfaces are clearly visible.
"""

import argparse
import json
from pathlib import Path

try:
    import cv2
except ImportError:
    raise SystemExit("Missing dependency. Run:  pip install -r requirements.txt")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("--frame", type=int, default=0, help="reference frame index")
    ap.add_argument("--out", default="regions.json")
    ap.add_argument("--names", default="road,hud,psychopy",
                    help="comma-separated region names to define")
    args = ap.parse_args()

    cap = cv2.VideoCapture(args.video)
    if not cap.isOpened():
        raise SystemExit(f"cannot open {args.video}")
    cap.set(cv2.CAP_PROP_POS_FRAMES, args.frame)
    ok, frame = cap.read()
    cap.release()
    if not ok:
        raise SystemExit(f"could not read frame {args.frame}")

    regions = {}
    for name in [n.strip() for n in args.names.split(",") if n.strip()]:
        title = f"Drag box for '{name}'  (ENTER/SPACE=accept, ENTER on empty=skip)"
        print(title)
        r = cv2.selectROI(title, frame, showCrosshair=True, fromCenter=False)
        cv2.destroyWindow(title)
        if r[2] > 0 and r[3] > 0:
            regions[name] = [int(r[0]), int(r[1]), int(r[2]), int(r[3])]
            print(f"  {name} = {regions[name]}")
        else:
            print(f"  skipped {name}")

    cfg = {
        "detect": {
            "method": "color",
            "_comment": "Set your accessibility pointer to a distinctive solid color, "
                        "then tune this HSV range. Or switch method to 'template' and "
                        "pass --template dot.png (a small crop of the pointer).",
            "hsv_lower": [140, 80, 80],
            "hsv_upper": [170, 255, 255],
            "min_area": 25,
        },
        "regions": regions,
    }
    Path(args.out).write_text(json.dumps(cfg, indent=2))
    print(f"\nwrote {args.out}  ({len(regions)} regions)")


if __name__ == "__main__":
    main()
