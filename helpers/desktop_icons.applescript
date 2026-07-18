-- Prints the desktop icon size followed by every icon's center position, all
-- comma-separated on one line: "64,1641,82,1146,591,..."
-- Run as: osascript helpers/desktop_icons.applescript
-- (Positions are in macOS points from the top-left of the primary display.
--  The first run triggers a one-time "control Finder" permission prompt.)
tell application "Finder"
	set iconSize to icon size of icon view options of window of desktop
	set posList to desktop position of every item of desktop
end tell
set out to (iconSize as string)
repeat with p in posList
	set out to out & "," & ((item 1 of p) as string) & "," & ((item 2 of p) as string)
end repeat
return out
