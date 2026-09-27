-- Hyprland default apps

TERMINAL     = "kitty"
FILE_MANAGER = "dolphin"
BROWSER      = "zen-browser"
EDITOR       = "gnome-text-editor --new-window"
CALCULATOR   = "gnome-calculator"

-- Monitors
-- The connector names are hardware specific, so they are not stored here.
-- scripts/install-machine.sh detects the connected outputs and writes
-- config/machine.lua. When that file is missing we fall back to the
-- connector names below, which is what a single-display laptop usually has.
local machine_ok, machine = pcall(require, "config.machine")
if machine_ok then
    MONITOR_HDMI   = machine.HDMI
    MONITOR_USBC   = machine.USBC
    MONITOR_LAPTOP = machine.LAPTOP
    PRIMARY_MONITOR = machine.PRIMARY
else
    MONITOR_HDMI   = "HDMI-A-1"
    MONITOR_USBC   = "eDP-1"
    MONITOR_LAPTOP = "eDP-1"
    PRIMARY_MONITOR = MONITOR_USBC
    print("[hyprland] config/machine.lua not found, using fallback connectors. Run scripts/install-machine.sh to detect your displays.")
end

-- Workspaces
NUM_WPM = 9 -- Number of workspaces per monitor (Max 10)
