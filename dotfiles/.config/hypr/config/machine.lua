-- Machine-specific monitor mapping.
--
-- Local file, deliberately not in the repository: connector names come from
-- the hardware, and a wrong name does not error, it silently leaves a monitor
-- dark. The repo ships machine.lua.example as a starting point.
--
-- These values are the ones that are working right now, frozen so nothing
-- changes. TO CONFIRM: the HDMI port below is the fallback default, not
-- something detected. Nothing is currently plugged into it.
--
--   hyprctl monitors    shows the connector names of what IS connected
--
-- When you know which port you use for the external display, edit HDMI to
-- match and reload with `hyprctl reload`. Until then, an external monitor on
-- the HDMI port will not light up.

return {
    -- TODO: set this to the real connector, e.g. "HDMI-A-2".
    -- Run `hyprctl monitors` with that monitor plugged in and read the name.
    HDMI = "HDMI-A-1",

    -- The external display, connected via USB-C / DisplayPort right now.
    USBC = "DP-1",

    -- The internal panel.
    LAPTOP = "eDP-1",

    -- Bar, background and new windows go here.
    PRIMARY = "DP-1",
}
