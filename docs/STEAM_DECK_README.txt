ECHOES OF THE LAST DAWN — Linux / Steam Deck build
===================================================

This is a native Linux x86_64 build. It does not need Proton.

Install (Desktop Mode)
 1. Copy the .tar.gz to the Deck (e.g. ~/Games) and extract it
    (Dolphin: right-click > Extract > Extract archive here).
 2. If the game won't start, make it executable:
      chmod +x EchoesOfTheLastDawn.x86_64
    (Dolphin: right-click > Properties > Permissions > Is executable.)
 3. Double-click EchoesOfTheLastDawn.x86_64 to test in Desktop Mode.
    Keep EchoesOfTheLastDawn.pck next to the executable.

Add to Gaming Mode
 4. In Steam (Desktop Mode): Games > Add a Non-Steam Game to My Library >
    Browse > select EchoesOfTheLastDawn.x86_64 > Add Selected Programs.
 5. In its Properties > Compatibility, leave "Force the use of a specific
    Steam Play compatibility tool" OFF (native build).
 6. Controller layout: choose "Gamepad" (the default for non-Steam games).
 7. Return to Gaming Mode and launch from your library (Non-Steam tab).

Controls (gamepad, Steam Deck layout)
  Left stick / D-pad   move, menu cursor
  A                    confirm, talk, open, advance dialogue
  B                    back / cancel; hold while moving to run
  X                    party comment (field), repeat last command (battle)
  Y                    main menu (field), toggle auto-battle (battle)
  View (left, two squares)   journal / map
  Menu (right, three lines)  pause (opens Settings)
  L1 / R1              switch menu tabs, party members, shop Buy/Sell,
                       next ready party member in battle
  L2/R2, L3/R3, right stick: unused. Trackpads act as a mouse (optional).
Every bound button above is checked automatically by the gamepad harness
(tests/padtest.gd) against the real game at 1280x800. A test on physical
Deck hardware has not been done yet.

Finding your way: the minimap (top right), gold objective marker and gold
exits show where to go next; exit signs name each destination. Toggle them
in Settings > Gameplay.

Saves live in ~/.local/share/godot/app_userdata/Echoes of the Last Dawn/saves.
Use Load Game > Export to copy a save to/from the browser version.

This build has not been certified by Valve; "Steam Deck Verified" is a
designation only Valve can grant.
