Files used by the F-Droid build recipe.

`export_presets.cfg` exports an unsigned APK with an Android template built from
the Godot sources. The recipe replaces `GODOT_SRC` with the path of the Godot
checkout and moves the file over the regular `export_presets.cfg`.
