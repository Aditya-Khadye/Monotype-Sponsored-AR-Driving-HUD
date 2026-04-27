#!/usr/bin/env python3
"""
Mock OutGauge UDP emitter for testing the Vision Pro HUD
without needing BeamNG.drive running.

Sends fake 96-byte OutGauge packets at 60 Hz.
Speed ramps up and down in a sine wave to simulate driving.

Usage:
    python3 mock_emitter.py <VISION_PRO_IP>
    python3 mock_emitter.py 192.168.1.42
    python3 mock_emitter.py localhost       # for visionOS Simulator
"""

import struct
import socket
import time
import math
import sys

TARGET_IP   = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
TARGET_PORT = 4444
SEND_HZ     = 60

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
print(f"Sending OutGauge packets to {TARGET_IP}:{TARGET_PORT} @ {SEND_HZ}Hz")
print("Press Ctrl+C to stop\n")

t0 = time.time()

try:
    while True:
        elapsed = time.time() - t0

        # Simulate driving: speed oscillates 0-140 km/h
        speed_kmh = 70 + 70 * math.sin(elapsed * 0.3)
        speed_ms  = speed_kmh / 3.6

        # RPM follows speed roughly
        rpm = 800 + (speed_kmh / 140) * 6200

        # Gear based on speed
        if speed_kmh < 20:
            gear = 2   # 1st (0=R, 1=N, 2=1st)
        elif speed_kmh < 50:
            gear = 3   # 2nd
        elif speed_kmh < 80:
            gear = 4   # 3rd
        elif speed_kmh < 110:
            gear = 5   # 4th
        else:
            gear = 6   # 5th

        # Throttle/brake based on acceleration direction
        accel = math.cos(elapsed * 0.3)  # derivative of sin
        throttle = max(0, accel)
        brake    = max(0, -accel * 0.5)

        # Fuel slowly drains
        fuel = max(0.05, 1.0 - (elapsed % 300) / 300)

        # Pack 96-byte OutGauge packet (little-endian)
        packet = struct.pack(
            '<I 4s H BB'           # time, car, flags, gear, plid
            'ff'                    # speed, rpm
            'fffff'                 # turbo, engTemp, fuel, oilPressure, oilTemp
            'fff'                   # throttle, brake, clutch
            '16s 16s'              # display1, display2
            'i ff',                # id, dashLightShift, dashLightFullBeam
            int(elapsed * 1000) & 0xFFFFFFFF,   # time (ms, wrapping)
            b'mock',                             # car name
            0x8000,                              # flags (bit 15 = KM/H)
            gear,                                # gear
            0,                                   # plid
            speed_ms,                            # speed (m/s)
            rpm,                                 # rpm
            0.0,                                 # turbo
            85.0 + 10 * math.sin(elapsed * 0.1), # engTemp
            fuel,                                # fuel
            3.5,                                 # oilPressure
            90.0,                                # oilTemp
            throttle,                            # throttle
            brake,                               # brake
            0.0,                                 # clutch
            b'\x00' * 16,                        # display1
            b'\x00' * 16,                        # display2
            1,                                   # id
            0.0,                                 # dashLightShift
            0.0,                                 # dashLightFullBeam
        )

        assert len(packet) == 96, f"Packet size: {len(packet)} (expected 96)"
        sock.sendto(packet, (TARGET_IP, TARGET_PORT))

        # Print status every second
        if int(elapsed * SEND_HZ) % SEND_HZ == 0:
            print(f"  {speed_kmh:6.1f} km/h | Gear {gear-1} | RPM {rpm:5.0f} | "
                  f"THR {throttle*100:3.0f}% | BRK {brake*100:3.0f}% | FUEL {fuel*100:3.0f}%")

        time.sleep(1 / SEND_HZ)

except KeyboardInterrupt:
    print("\nStopped.")
    sock.close()
