#!/usr/bin/env python3
"""
BeamNG HUD — Mac Mini Data Receiver
====================================

TCP server that receives NDJSON telemetry from the Vision Pro
and writes to both JSON and CSV files, organized by session.

Sessions are auto-detected from SESSION_START / SESSION_END markers.
If no markers are present, records are grouped into 
time-based sessions (new session after 30s gap).

Output structure:
    data/
    └── sessions/
        ├── 20260413_142530/
        │   ├── telemetry.json      (array of records)
        │   ├── telemetry.csv       (tabular)
        │   ├── analysis_events.json (filtered: analysis only)
        │   └── session_meta.json   (summary stats)
        └── 20260413_150000/
            └── ...

Usage:
    python3 mac_receiver.py
    python3 mac_receiver.py --port 5555 --data-dir ./data
"""

import asyncio
import json
import csv
import os
import sys
import argparse
from datetime import datetime, timezone
from pathlib import Path
from dataclasses import dataclass, field
from typing import Optional


# ── Configuration ─────────────────────────────────────────────

DEFAULT_PORT = 5555
DEFAULT_DATA_DIR = "./data/sessions"
GAP_THRESHOLD_S = 30  # seconds of silence = new session


# ── Session state ─────────────────────────────────────────────

@dataclass
class Session:
    session_id: str
    output_dir: Path
    records: list = field(default_factory=list)
    analysis_events: list = field(default_factory=list)
    start_time: Optional[float] = None
    end_time: Optional[float] = None
    record_count: int = 0

    # CSV writer state
    csv_file: Optional[object] = None
    csv_writer: Optional[csv.writer] = None
    csv_handle: Optional[object] = None

    def ensure_dir(self):
        self.output_dir.mkdir(parents=True, exist_ok=True)

    def open_csv(self, header: list[str]):
        self.ensure_dir()
        path = self.output_dir / "telemetry.csv"
        self.csv_handle = open(path, "w", newline="", encoding="utf-8")
        self.csv_writer = csv.writer(self.csv_handle)
        self.csv_writer.writerow(header)

    def write_csv_row(self, row: list):
        if self.csv_writer:
            self.csv_writer.writerow(row)
            self.csv_handle.flush()

    def close(self):
        if self.csv_handle:
            self.csv_handle.close()

        self.ensure_dir()

        # Write full JSON
        json_path = self.output_dir / "telemetry.json"
        with open(json_path, "w", encoding="utf-8") as f:
            json.dump(self.records, f, indent=2, ensure_ascii=False)

        # Write analysis events only
        if self.analysis_events:
            analysis_path = self.output_dir / "analysis_events.json"
            with open(analysis_path, "w", encoding="utf-8") as f:
                json.dump(self.analysis_events, f, indent=2, ensure_ascii=False)

        # Write session metadata
        meta = {
            "session_id": self.session_id,
            "record_count": self.record_count,
            "analysis_event_count": len(self.analysis_events),
            "start_time": self.start_time,
            "end_time": self.end_time,
            "duration_s": (self.end_time - self.start_time)
                          if self.start_time and self.end_time else None,
            "sources": list(set(
                r.get("source", "unknown") for r in self.records
            )),
        }
        meta_path = self.output_dir / "session_meta.json"
        with open(meta_path, "w", encoding="utf-8") as f:
            json.dump(meta, f, indent=2)

        print(f"  [Session] Saved {self.record_count} records → {self.output_dir}")


# ── CSV field mapping ─────────────────────────────────────────

CSV_HEADER = [
    "session_time_ms", "utc", "epoch_s", "source",
    "speed_kmh", "speed_ms", "rpm", "gear",
    "throttle", "brake", "clutch", "fuel",
    "eng_temp", "oil_temp", "oil_pressure", "turbo",
    "abs", "tc", "signal_l", "signal_r", "handbrake",
    "head_yaw", "head_pitch", "head_roll", "look_region", "dwell_ms",
    "click_gaze_x", "click_gaze_y", "click_kind", "click_seq",
    "analysis_label", "analysis_confidence",
    "marker_label", "marker_notes",
]


def record_to_csv_row(rec: dict) -> list:
    """Extract CSV row from a JSON record."""
    ts = rec.get("timestamp", {})

    def g(key):
        """Get value, return empty string if None."""
        v = rec.get(key)
        if v is None:
            return ""
        if isinstance(v, bool):
            return "1" if v else "0"
        if isinstance(v, float):
            return f"{v:.4f}"
        return str(v)

    return [
        ts.get("sessionTimeMs", ""),
        ts.get("utcISO", ""),
        ts.get("epochSeconds", ""),
        rec.get("source", ""),
        g("speedKMH"), g("speedMS"), g("rpm"), g("gear"),
        g("throttle"), g("brake"), g("clutch"), g("fuel"),
        g("engTemp"), g("oilTemp"), g("oilPressure"), g("turbo"),
        g("absActive"), g("tcActive"), g("signalLeft"), g("signalRight"),
        g("handbrake"),
        g("headYaw"), g("headPitch"), g("headRoll"), g("lookRegion"), g("dwellMs"),
        g("clickGazeX"), g("clickGazeY"), g("clickKind"), g("clickSeq"),
        g("analysisLabel"), g("analysisConfidence"),
        g("markerLabel"), g("markerNotes"),
    ]


# ── TCP connection handler ────────────────────────────────────

class ReceiverServer:
    def __init__(self, data_dir: str):
        self.data_dir = Path(data_dir)
        self.current_session: Optional[Session] = None
        self.last_record_time: float = 0
        self.total_records: int = 0

    def new_session(self, session_id: Optional[str] = None) -> Session:
        """Create and activate a new session."""
        if self.current_session:
            self.current_session.close()

        if not session_id:
            session_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")

        session = Session(
            session_id=session_id,
            output_dir=self.data_dir / session_id,
        )
        session.open_csv(CSV_HEADER)
        self.current_session = session
        print(f"\n  [Session] New session: {session_id}")
        return session

    def process_record(self, record: dict):
        """Process a single telemetry record."""
        source = record.get("source", "unknown")
        ts = record.get("timestamp", {})
        epoch = ts.get("epochSeconds", 0)
        marker_label = record.get("markerLabel", "")

        # Handle session lifecycle markers
        if marker_label == "SESSION_START":
            sid = ts.get("utcISO", "").replace(":", "").replace("-", "")[:15]
            self.new_session(sid or None)
            self.last_record_time = epoch
            return

        if marker_label == "SESSION_END":
            if self.current_session:
                self.current_session.end_time = epoch
                self.current_session.records.append(record)
                self.current_session.record_count += 1
                self.current_session.close()
                self.current_session = None
            return

        # Auto-detect session boundaries by time gap
        if epoch - self.last_record_time > GAP_THRESHOLD_S and self.last_record_time > 0:
            self.new_session()

        if not self.current_session:
            self.new_session()

        session = self.current_session
        self.last_record_time = epoch

        # Track timing
        if not session.start_time:
            session.start_time = epoch
        session.end_time = epoch

        # Store record
        session.records.append(record)
        session.record_count += 1
        self.total_records += 1

        # Write CSV row
        session.write_csv_row(record_to_csv_row(record))

        # Collect analysis events separately
        if source == "analysis":
            session.analysis_events.append(record)
            label = record.get("analysisLabel", "?")
            conf = record.get("analysisConfidence", 0)
            print(f"  ⚡ {label} (confidence: {conf:.2f})")

        # Progress indicator (every 60 records ≈ 1s at 60Hz)
        if self.total_records % 60 == 0:
            speed = record.get("speedKMH", 0) or 0
            rpm = record.get("rpm", 0) or 0
            sys.stdout.write(
                f"\r  📡 Records: {self.total_records:,} | "
                f"Speed: {speed:.1f} km/h | RPM: {rpm:.0f}    "
            )
            sys.stdout.flush()

    async def handle_client(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ):
        addr = writer.get_extra_info("peername")
        print(f"\n  [Connect] Vision Pro connected from {addr}")

        buffer = b""
        try:
            while True:
                data = await reader.read(8192)
                if not data:
                    break

                buffer += data

                # Process complete NDJSON lines
                while b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    line = line.strip()
                    if not line:
                        continue

                    try:
                        record = json.loads(line.decode("utf-8"))
                        self.process_record(record)
                    except json.JSONDecodeError as e:
                        print(f"\n  [Warn] Bad JSON: {e}")

        except asyncio.CancelledError:
            pass
        except Exception as e:
            print(f"\n  [Error] {e}")
        finally:
            writer.close()
            await writer.wait_closed()
            print(f"\n  [Disconnect] {addr}")

            # Finalize current session
            if self.current_session:
                self.current_session.close()
                self.current_session = None

    async def run(self, port: int):
        server = await asyncio.start_server(
            self.handle_client, "0.0.0.0", port
        )

        addrs = ", ".join(str(s.getsockname()) for s in server.sockets)
        print(f"""
╔══════════════════════════════════════════════════╗
║  BeamNG HUD — Mac Mini Data Receiver             ║
║  Listening on {addrs:<35s}║
║  Data dir: {str(self.data_dir):<38s}║
║  Waiting for Vision Pro connection...            ║
╚══════════════════════════════════════════════════╝
        """)

        async with server:
            await server.serve_forever()


# ── Entry point ───────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="BeamNG HUD Mac Mini Receiver")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--data-dir", type=str, default=DEFAULT_DATA_DIR)
    args = parser.parse_args()

    receiver = ReceiverServer(args.data_dir)

    try:
        asyncio.run(receiver.run(args.port))
    except KeyboardInterrupt:
        print("\n\nShutting down...")
        if receiver.current_session:
            receiver.current_session.close()


if __name__ == "__main__":
    main()
