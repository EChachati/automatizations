-- Hyprland default apps

TERMINAL     = "kitty"
FILE_MANAGER = "dolphin"
BROWSER      = "zen-browser"
EDITOR       = "gnome-text-editor --new-window"
CALCULATOR   = "gnome-calculator"

-- Monitors
-- The connector names are hardware specific, so they are not stored here.
-- config/machine.lua holds them and is kept out of the repository on
-- purpose: a wrong connector name does not error, it silently leaves a
-- monitor dark. Copy machine.lua.example and fill in your own, then check
-- it against `hyprctl monitors`.
-- When that file is missing we fall back to the names below, which is what
-- a single-display laptop usually has.
local machine_ok, machine = pcall(require, "config.machine")
if machine_ok then
    MONITOR_HDMI   = machine.HDMI
    MONITOR_USBC   = machine.USBC
    MONITOR_LAPTOP = machine.LAPTOP
    PRIMARY_MONITOR = machine.PRIMARY
else
    -- run 'hyprctl monitors all' and change the names accordingly  
    MONITOR_HDMI   = "HDMI-A-1"
    MONITOR_USBC   = "DP-1"
    MONITOR_LAPTOP = "eDP-1"
    PRIMARY_MONITOR = MONITOR_USBC
    print("[hyprland] config/machine.lua not found, using fallback connectors. Copy machine.lua.example and set your own, or an unplugged monitor will stay dark.")
end

-- Workspaces
NUM_WPM = 9 -- Number of workspaces per monitor (Max 10)
