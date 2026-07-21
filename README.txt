KH1FM SORA COMBO VISUALS v9 — PROOF OF CONCEPT
================================================

FILES
-----
mod.yml
  OpenKH asset replacement rule. It copies this package's xa_ex_0010.mset
  over the game's built xa_ex_0010.mset.

xa_ex_0010.mset
  Expanded Sora moveset containing the requested motion records.
  SHA-256: 674e9588b0959bcfadc986cb394c7d9e5d0f3c937ec93cb8659c1371ce1cd2ea

KH1FM_SoraComboVisuals_Controller_v9_POC.lua
  LuaBackend controller for real-second-press transitions.
  SHA-256: 5e628a4e0cadfc857fab6be8ad9f39ae050d4aa3e9c44272f5cd46bc2a6faacb


INSTALL
-------
1. Remove or disable every older C8/C9, mandatory-catch, motion-pointer,
   move-speed, or combo-test Lua file.
2. Install this entire folder as an OpenKH mod and rebuild the game patch.
3. Copy KH1FM_SoraComboVisuals_Controller_v9_POC.lua into the LuaBackend
   scripts/kh1 folder.
4. Start the game and open the F2 console. Confirm this line appears:
     [SoraComboVisualsV9] READY for the v9 POC MSET.
5. If the controller says the MSET does not match v9, stop testing and send
   the complete console message.


EXPECTED CONTROLS
-----------------
C8 ground attack 1
  First press: Raid throw
  Real second press: Raid catch
  No second press: normal exit

C9 ground attack 2
  First press: Raid throw
  Real second press: Raid catch
  No second press: normal exit

D0 Sliding Dash
  First press: Judgement Raid, the final Strike Raid throw
  Real second press: Raid catch
  No second press: normal exit

CC or CD air attack
  First press: Aerial Sweep
  Real second press: Ragnarok F7 finisher
  No second press: normal exit

D4 Guard
  Ripple Drive visual
  Guard's original non-damaging control tail

DC Dodge Roll
  Zantetsuken visual
  Dodge Roll's original non-damaging control tail


TEST ORDER
----------
Record gameplay and the F2 console together if possible.

1. C8: one press only, then two presses.
2. C9: one press only, then two presses.
3. Sliding Dash: one press only, then two presses.
4. Air attack 1: one press only, then two presses.
5. Air attack 2: one press only, then two presses.
6. Guard once where nothing can hit Sora. Confirm Ripple Drive's visual and
   that no enemy is damaged.
7. Dodge Roll once where nothing can be hit. Confirm Zantetsuken's visual and
   that no enemy is damaged.
8. Test Guard and Dodge Roll against an enemy attack near the beginning,
   middle, and end of each replacement animation.


DEFENSE / INVULNERABILITY STATUS
--------------------------------
The offensive Ripple Drive and Zantetsuken trigger tails are NOT imported, so
this POC should not create their attack hitboxes or damage.

Guard and Dodge Roll retain their original native defensive control tails.
Because both replacement visuals are now 100 frames long, this test must show
whether the engine keeps the D4/DC defensive state active for the full visual.
This version deliberately does not write an unknown invulnerability address.
If either move can be hit before its visual ends, report approximately when it
happens; the next revision will add a targeted, verified full-duration defense
controller rather than guessing at a global game-state flag.


SAFETY / SCOPE
--------------
- No synthetic input.
- No animation-ID, resolved-index, or animation-time writes.
- No damage, hitbox, HP, speed, movement, or global-timescale writes.
- Runtime map entries are byte-identical to the verified v4 base.
- Ground C8/C9/CB motion records remain the already tested v4 layout.
- Larger imported records were given new space; neighboring motions were not
  overwritten.
