# dmgbuild settings for Vibemetric.dmg (used by scripts/build-app.sh).
# Positions match the arrow in Resources/dmg/background.tiff (scripts/make-dmg-background.swift).
import os.path

app = defines.get("app", "build/Vibemetric.app")  # noqa: F821 (dmgbuild injects `defines`)
app_name = os.path.basename(app)

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
hide_extensions = [app_name]

background = "Resources/dmg/background.tiff"
window_rect = ((200, 120), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 128
text_size = 13
icon_locations = {app_name: (170, 200), "Applications": (490, 200)}
