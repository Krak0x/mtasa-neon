# Fog and far-clip distance test

This server-side diagnostic resource separates GTA fog from the camera far
clip while validating Neon's extended rendering settings.

Commands:

- `/seefar [distance|reset]` sets or restores the server fog-distance override.
- `/seefar2 [distance|reset]` sets or restores the server far-clip override.

Calling either command without an argument prints the current override and its
usage. The commands broadcast successful changes so every connected tester can
see which visibility condition is active.
