-- Monitor wiki https://wiki.hypr.land/Configuring/Basics/Monitors/
-- Example: output can be found with hyprctl monitors. Edit variables.lua for the monitor outputs instead of here directly
-- hl.monitor({
--     output    = MONITOR_HDMI,
--     mode      = "1920x1080@60",
--     position  = "0x0",
--     scale     = "1",
-- })

local x_offset = 0 
local function addMonitor(monitor_name, mode, scale)
    scale = scale or 1
    
    local width = 1920
    if mode ~= "preferred" and mode ~= "highres" then
        local w_str = mode:match("^(%d+)x")
        if w_str then
            width = tonumber(w_str)
        end
    end

    local position = string.format("%dx0", x_offset)

    hl.monitor({ 
        output = monitor_name, 
        mode = mode, 
        position = position, 
        scale = scale 
    })

    x_offset = x_offset + math.floor(width / scale)
end


-- These are the monitors arranged left to right, switch them if you want
-- Will be ignored if not connected
if MONITOR_LAPTOP then addMonitor(MONITOR_LAPTOP, "1920x1080@180.00Hz", 1) end
if MONITOR_USBC   then addMonitor(MONITOR_USBC, "preferred", 1) end
if MONITOR_HDMI   then addMonitor(MONITOR_HDMI, "preferred", 1) end

-- If you want to disable an specific Monitor
--hl.monitor({output=MONITOR_LAPTOP, disabled=true})
--hl.monitor({output=MONITOR_USBC, disabled=true})
--hl.monitor({output=MONITOR_HDMI, disabled=true})