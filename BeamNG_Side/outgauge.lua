-- ═══════════════════════════════════════════════════════════
-- BeamNG OutGauge UDP Broadcaster
-- Place at: BeamNG.drive/lua/ge/extensions/outgauge.lua
-- Activate in-game: Extensions menu > outgauge
-- ═══════════════════════════════════════════════════════════

local M = {}
local socket = require("socket")
local udp = nil

-- ┌─────────────────────────────────────────────────────────┐
-- │  CONFIGURE: Set TARGET_IP to your Vision Pro's IP       │
-- │  Find it: Settings > Wi-Fi > tap network > IP Address   │
-- └─────────────────────────────────────────────────────────┘
local TARGET_IP   = "192.168.1.XXX"   -- <-- CHANGE THIS
local TARGET_PORT = 4444
local SEND_RATE   = 0.016             -- ~60 Hz

local sendTimer = 0

-- ── Helpers ───────────────────────────────────────────────

local function packFloat(val)
    local packed = string.pack("<f", val or 0)
    return packed
end

local function packUint32(val)
    return string.pack("<I4", val or 0)
end

local function packUint16(val)
    return string.pack("<I2", val or 0)
end

local function packInt32(val)
    return string.pack("<i4", val or 0)
end

local function packString(str, len)
    str = str or ""
    if #str > len then str = str:sub(1, len) end
    return str .. string.rep("\0", len - #str)
end

-- ── Build 96-byte OutGauge packet ─────────────────────────

local function buildPacket(veh)
    local electrics = veh and veh:getController("electrics")
    if not electrics then return nil end

    local d = electrics.values or {}

    local speedMs   = d.airspeed or d.wheelspeed or 0
    local rpm       = d.rpm or 0
    local gearRaw   = d.gearIndex or 0      -- -1=R, 0=N, 1=1st ...
    local gear      = gearRaw + 1            -- 0=R, 1=N, 2=1st ...
    if gear < 0 then gear = 0 end

    local throttle  = d.throttle_input or d.throttle or 0
    local brake     = d.brake_input or d.brake or 0
    local clutch    = d.clutch_input or d.clutch or 0
    local fuel      = d.fuel or 1
    local engTemp   = d.waterTemp or d.oilTemp or 85
    local oilTemp   = d.oilTemp or 90
    local turbo     = d.turboBoost or 0
    local oilPress  = d.oilPressure or 3.5

    -- Flag bits
    local flags = 0
    if d.signal_L      then flags = flags + 32  end  -- bit 5
    if d.signal_R      then flags = flags + 64  end  -- bit 6
    if d.lowfuel       then flags = flags + 128 end  -- bit 7 (oil warn reused)
    if d.abs           then flags = flags + 512 end  -- bit 9
    flags = flags + 32768  -- bit 15: KM/H

    -- Car name (first 4 chars of vehicle model)
    local carName = veh:getJBeamFilename() or "beam"
    carName = carName:sub(1, 4)

    local packet = packUint32(math.floor(os.clock() * 1000))  -- 0:  time
                 .. packString(carName, 4)                      -- 4:  car
                 .. packUint16(flags)                            -- 8:  flags
                 .. string.char(math.max(0, math.min(255, gear)))  -- 10: gear
                 .. string.char(0)                               -- 11: plid
                 .. packFloat(speedMs)                           -- 12: speed
                 .. packFloat(rpm)                               -- 16: rpm
                 .. packFloat(turbo)                             -- 20: turbo
                 .. packFloat(engTemp)                           -- 24: engTemp
                 .. packFloat(fuel)                              -- 28: fuel
                 .. packFloat(oilPress)                          -- 32: oilPressure
                 .. packFloat(oilTemp)                           -- 36: oilTemp
                 .. packFloat(throttle)                          -- 40: throttle
                 .. packFloat(brake)                             -- 44: brake
                 .. packFloat(clutch)                            -- 48: clutch
                 .. packString("", 16)                           -- 52: display1
                 .. packString("", 16)                           -- 68: display2
                 .. packInt32(1)                                 -- 84: id
                 .. packFloat(0)                                 -- 88: dashLightShift
                 .. packFloat(0)                                 -- 92: dashLightFullBeam

    return packet  -- 96 bytes
end

-- ── Extension lifecycle ───────────────────────────────────

function M.onInit()
    udp = socket.udp()
    udp:settimeout(0)
    log("I", "outgauge", string.format("OutGauge broadcaster -> %s:%d @ %.0fHz",
        TARGET_IP, TARGET_PORT, 1 / SEND_RATE))
end

function M.onUpdate(dtSim)
    sendTimer = sendTimer + dtSim
    if sendTimer < SEND_RATE then return end
    sendTimer = 0

    local veh = be:getPlayerVehicle(0)
    if not veh then return end

    local packet = buildPacket(veh)
    if packet and #packet == 96 then
        udp:sendto(packet, TARGET_IP, TARGET_PORT)
    end
end

function M.onExtensionUnloaded()
    if udp then udp:close() end
    log("I", "outgauge", "OutGauge broadcaster stopped")
end

return M
