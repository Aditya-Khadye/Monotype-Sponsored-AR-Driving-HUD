#!/usr/bin/env python3
"""
Post-hoc gaze analysis for the BeamNG HUD attention study (Option C).
========================================================================

Takes a screen recording of a session (with the visionOS accessibility
eye-pointer visible), finds the pointer dot in each frame, maps it to your
named regions (road / hud / psychopy / ...), and reports glance + dwell stats.

This is the post-hoc pipeline for the "keep Moonlight & PsychoPy as their own
windows + record the eye-pointer" approach. See README.md.

Outputs (in --out dir):
  gaze_frames.csv    per-frame: frame, t_s, x, y, region, confidence
  gaze_summary.json  per-region dwell %, glance count, mean glance ms, TTFF
  gaze_overlay.mp4   (with --overlay) the video with regions + detected dot drawn
                     >>> ALWAYS eyeball this first to confirm detection works <<<

Usage:
  python3 gaze_analysis.py session.mp4 --regions regions.json --out ./out --overlay

Detection methods (set in regions.json -> "detect.method"):
  color     HSV range threshold — set a distinctive accessibility pointer color [default]
  template  match a cropped PNG of the dot (--template dot.png)
"""

import argparse
import csv
import json
import sys
from pathlib import Path

try:
    import cv2
    import numpy as np
except ImportError:
    sys.exit("Missing dependencies. Run:  pip install -r requirements.txt   (opencv-python, numpy)")


# ── Detection ─────────────────────────────────────────────────

def detect_color(frame_bgr, det):
    """Find the pointer as the largest blob in an HSV color range."""
    hsv = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2HSV)
    mask = cv2.inRange(hsv, np.array(det["hsv_lower"], np.uint8),
                            np.array(det["hsv_upper"], np.uint8))
    # optional second range (e.g. red wraps around hue 0/180)
    if "hsv_lower2" in det and "hsv_upper2" in det:
        mask = cv2.bitwise_or(mask, cv2.inRange(
            hsv, np.array(det["hsv_lower2"], np.uint8), np.array(det["hsv_upper2"], np.uint8)))
    min_area = det.get("min_area", 20)
    cnts, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    best, best_area = None, 0.0
    for c in cnts:
        a = cv2.contourArea(c)
        if a >= min_area and a > best_area:
            best, best_area = c, a
    if best is None:
        return None, 0.0
    m = cv2.moments(best)
    if m["m00"] == 0:
        return None, 0.0
    return (m["m10"] / m["m00"], m["m01"] / m["m00"]), float(best_area)


def detect_template(frame_bgr, tmpl, det):
    """Find the pointer by template-matching a cropped image of it."""
    res = cv2.matchTemplate(frame_bgr, tmpl, cv2.TM_CCOEFF_NORMED)
    _, maxv, _, maxloc = cv2.minMaxLoc(res)
    if maxv < det.get("threshold", 0.6):
        return None, float(maxv)
    h, w = tmpl.shape[:2]
    return (maxloc[0] + w / 2, maxloc[1] + h / 2), float(maxv)


def classify(pt, regions):
    if pt is None:
        return "none"
    x, y = pt
    for name, (rx, ry, rw, rh) in regions.items():
        if rx <= x <= rx + rw and ry <= y <= ry + rh:
            return name
    return "other"


# ── Summary stats ─────────────────────────────────────────────

def runs_of(seq):
    """Yield (label, start_idx, end_idx_exclusive) contiguous runs."""
    out = []
    if not seq:
        return out
    cur, start = seq[0], 0
    for i in range(1, len(seq) + 1):
        if i == len(seq) or seq[i] != cur:
            out.append((cur, start, i))
            if i < len(seq):
                cur, start = seq[i], i
    return out


def compute_summary(seq, fps, region_names, min_glance_ms):
    total = len(seq)
    detected = sum(1 for s in seq if s != "none")
    runs = runs_of(seq)
    min_frames = (min_glance_ms / 1000.0) * fps

    per = {}
    for name in list(region_names) + ["other", "none"]:
        frames = sum(1 for s in seq if s == name)
        glance_lens = [(e - st) for (rg, st, e) in runs if rg == name and (e - st) >= min_frames]
        ttff = next((round(st / fps, 3) for (rg, st, e) in runs if rg == name), None)
        per[name] = {
            "frames": frames,
            "time_s": round(frames / fps, 3) if fps else None,
            "pct_of_session": round(100 * frames / total, 1) if total else 0,
            "pct_of_detected": (round(100 * frames / detected, 1)
                                if detected and name != "none" else None),
            "glances": len(glance_lens),
            "mean_glance_ms": round(float(np.mean(glance_lens)) / fps * 1000, 1) if glance_lens else 0,
            "total_glance_ms": round(sum(glance_lens) / fps * 1000, 1) if glance_lens else 0,
            "time_to_first_s": ttff,
        }
    return {
        "fps": round(fps, 2),
        "frames": total,
        "duration_s": round(total / fps, 2) if fps else None,
        "detection_rate_pct": round(100 * detected / total, 1) if total else 0,
        "min_glance_ms": min_glance_ms,
        "transition_count": max(0, len(runs) - 1),
        "regions": per,
    }


def print_summary(s):
    print("\n=== Gaze summary ===")
    print(f"duration {s['duration_s']}s @ {s['fps']}fps | "
          f"pointer detected in {s['detection_rate_pct']}% of frames | "
          f"{s['transition_count']} transitions")
    if s["detection_rate_pct"] < 80:
        print("  ⚠️  LOW detection rate — tune the pointer color/template in regions.json "
              "and re-check gaze_overlay.mp4.")
    print(f"\n{'region':<10}{'%(detect)':>10}{'glances':>9}{'mean ms':>9}{'TTFF s':>9}")
    for name, d in s["regions"].items():
        if d["frames"] == 0 and name in ("other", "none"):
            continue
        pct = d["pct_of_detected"] if d["pct_of_detected"] is not None else "-"
        ttff = d["time_to_first_s"] if d["time_to_first_s"] is not None else "-"
        print(f"{name:<10}{str(pct):>10}{d['glances']:>9}{d['mean_glance_ms']:>9}{str(ttff):>9}")


# ── Main ──────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description="Post-hoc eye-pointer → region gaze analysis")
    ap.add_argument("video")
    ap.add_argument("--regions", required=True, help="regions.json from define_regions.py")
    ap.add_argument("--out", default="./gaze_out")
    ap.add_argument("--template", help="cropped PNG of the pointer (template method)")
    ap.add_argument("--overlay", action="store_true", help="write a debug video with detection drawn")
    ap.add_argument("--min-glance-ms", type=float, default=100,
                    help="ignore runs shorter than this when counting glances")
    args = ap.parse_args()

    cfg = json.loads(Path(args.regions).read_text())
    det = cfg.get("detect", {"method": "color"})
    regions = {k: tuple(v) for k, v in cfg["regions"].items()}
    method = det.get("method", "color")

    tmpl = None
    if method == "template":
        tp = args.template or det.get("template")
        if not tp:
            sys.exit("template method needs --template or detect.template in regions.json")
        tmpl = cv2.imread(tp)
        if tmpl is None:
            sys.exit(f"could not read template image: {tp}")

    cap = cv2.VideoCapture(args.video)
    if not cap.isOpened():
        sys.exit(f"could not open video: {args.video}")
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    W = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    H = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    outdir = Path(args.out)
    outdir.mkdir(parents=True, exist_ok=True)

    writer = None
    if args.overlay:
        writer = cv2.VideoWriter(str(outdir / "gaze_overlay.mp4"),
                                 cv2.VideoWriter_fourcc(*"mp4v"), fps, (W, H))

    colors = {"road": (0, 200, 0), "hud": (255, 120, 0), "psychopy": (0, 140, 255),
              "other": (160, 160, 160), "none": (0, 0, 255)}

    rows, seq = [], []
    i = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        pt, conf = (detect_template(frame, tmpl, det) if method == "template"
                    else detect_color(frame, det))
        region = classify(pt, regions)
        seq.append(region)
        t = i / fps
        rows.append([i, round(t, 3),
                     "" if pt is None else round(pt[0], 1),
                     "" if pt is None else round(pt[1], 1),
                     region, round(conf, 3)])
        if writer is not None:
            ov = frame.copy()
            for name, (rx, ry, rw, rh) in regions.items():
                col = colors.get(name, (200, 200, 200))
                cv2.rectangle(ov, (rx, ry), (rx + rw, ry + rh), col, 2)
                cv2.putText(ov, name, (rx + 4, ry + 20),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.6, col, 2)
            if pt is not None:
                cv2.circle(ov, (int(pt[0]), int(pt[1])), 12, colors.get(region, (0, 0, 255)), 3)
            cv2.putText(ov, f"{t:6.2f}s  {region}", (10, H - 15),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)
            writer.write(ov)
        i += 1

    cap.release()
    if writer is not None:
        writer.release()

    with open(outdir / "gaze_frames.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["frame", "t_s", "x", "y", "region", "confidence"])
        w.writerows(rows)

    summary = compute_summary(seq, fps, list(regions.keys()), args.min_glance_ms)
    (outdir / "gaze_summary.json").write_text(json.dumps(summary, indent=2))
    print_summary(summary)
    print(f"\nwrote: {outdir/'gaze_frames.csv'}, {outdir/'gaze_summary.json'}"
          + (f", {outdir/'gaze_overlay.mp4'}" if writer is not None else ""))


if __name__ == "__main__":
    main()
