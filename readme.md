# LD59 Signal Game

```bash
butler push LD59.zip akatona/geordi-la-forge:web
```

## fixes
- fan blade animation stutters like I repeat the first frame at the end

## first day to-do
- basic placeholder environment
  - [x] build models
- world
    - [x] rooms/doors/props
    - [x] lighting (switches, lamps, fires, etc.)
    - [ ] particles (dust, etc.)
- HUD
  - [x] refine noise overlay
  - [x] cooldowns/controls
- sound
  - [x] placeholder music 
  - [x] placeholder sound fx
    - [x] ping
    - [x] movement (footsteps, jumps, etc.)
      - [x] export as wavs to mitigate latency

- keep player better oriented
  - [x] pause the pulse on hit targets
  - [x] make some floor/ceiling tiles pulse reactive
- [x] better way to be "signal" theme
  - [x] 180d out-of-phase sine waves on oscilloscope screen begin to emerge from noise with proximity to enemy
  - [ ] something else?  still doesn't feel quite appropriate
- blender
  - [x] model a light switch for the room to make the sonar useful
  - [x] model a handheld oscilloscope
- [x] swap in the dalek model
- [ ] actually pause the game during pause menu and start screen?
- [x] sfx for for enemy movement and/or oscilloscopes sinewaves
- [x] make enemy turn towards player
- [x] make sure the ping cooldown is longer than the pulse duration
- [x] stick (crowbar? bat? wrench?)
  - [x] model
  - [x] swing animation
  - [x] tune sound for a hit vs missed swing (currently needs louder)
- [x] fix the awkward noise overlay punchout for the oscilloscope
- [x] extend the hitbox for a push by at least 2x
- [ ] implement enemy collision = death screen (try to make it clear to the player what happened...maybe pull back the camera and make a short-range omnilight at the player position to show the enemy for a moment before the 'retry' screen?)
- [x] working web audio
  - [x] make sure web audio either has a good starting volume or it's overwhelmingly clear to the player immediately at the start screen how to get to the volume control...maybe just start volume at 0.5
- [?] why is it so laggy in full screen?  what can I do to keep it lightweight?

josh test play results:
- [x] start volume at ~5-10%
- [x] HUD scaling (the sliders get small on big screen)
- his resolution is do-able, but his mouse is crazy
  - [x] add a mouse sensitivity slider
- even he struggles to get the rhythm for the geordi-vision and ping tool
  - [x]add the hotkeys to the sliders and controls hints in the pause menu
  - design the rooms with gradual concept introductions:
    - [x] room 1: basic movement
      - [x] make it clear that doors/lights will require a button
    - [x] room 2: introduce the ping tool and the noise overlay
    - [ ] room 3: introduce a disabled, static enemy (light color to indicate disabled? also implement a short stun to the hit enemies in general which will trigger this light color); pick up the crowbar
    - [ ] room 4: introduce the stick and combat
- [x] simplify door shader, make it parallel the door buttons
- stetch:
  - [x] variations in wave generation for mcguffins
  - [ ] polish: sine waves scroll speed

- next josh ideas?
  - let's expand to a bigger space --> give the enemies a patrol with a leash
    - [x] line of sight -> investigate last known position, then return to patrol if they lose sight of the player
    - [x] visual indicator for active state (light color: yellow investigate, red chase, blue return to patrol?)
  - [x] audio still not working in web

### cool clever little ideas
- finding the lightswitch is the first part of the puzzle
- using enemy's radar occlusion state to still see them by keeping a static pulse illuminating an object behind them 
- encourage the player to pace out the room with their footsteps to navigate while blind

josh ideas:
- [x] make placeholder capsule enemy which hurts player on contact
- [x]make combat system with placeholder stick to swat at enemies, knocking them back (maybe kill them eventually, maybe not, idk)
- [x] ramp up volume on a noise channel when an enemy is near

Questions:
- how to manually run the headless startup in "Validation: headless Godot 4.6.1 startup passed cleanly"

### final day to-do
- fix daleks running backwards sometimes (are they not pulling from the same scene or is the chase logic dependant on something inconsistent?)
- consider how to make the player want to use the sonar tool in the second room (the door button is visible because of its shader...maybe cover it until the lights are on?  maybe reverse its color scheme and make it non-emissive until it is pressed?)
- replace door open sound with bolt hatch opening like halo
- did the 'broken enemy' checkbox come through?  make it work for room 3
- add the crowbar as a pickup like a doom weapon in room 3 or 4
- get collision on the lab benches for room 4 to demonstrate line of sight and leashing
- final room ideas
  - lights flicker?
  - new bgm?
  - bigger challenge
    - box jumping?
    - give player a unique vantage when they jump down?
- check on performance dips in the profiler
- update the notifications boxes
- add xbox achievement for the bottom stepping stones
- it's not very clear what color the robot lights are

### exporter
```
The simplest reliable setup is: export the Web build to a folder, zip that folder as an artifact, then have butler push the folder. butler can accept a zip, but its own docs say that for portable builds there’s no real upside to pushing the zip directly because it extracts it anyway. I built that flow for this project.

Files added:

One-click launcher: deploy-web.cmd (line 1)
Deploy logic: scripts/deploy-web.ps1 (line 1)
Godot Web export preset: export_presets.cfg (line 1)
Ignore build output and saved local target: .gitignore (line 1)
How it works:

First run prompts once for the itch target in username/game:web form and saves it to itch-deploy.local.json.
It auto-detects a Godot executable that has matching export templates installed.
It exports to web-export\index.html, creates build\LD59.zip, then runs butler push web-export username/game:web.
Useful flags:
-Configure to change the saved itch target
-SkipPush to export and zip only
-DryRun to preview the butler upload
-UserVersion 1.2.3 to pass a version to butler
What I validated:

Ran powershell -File .\scripts\deploy-web.ps1 -SkipPush
Godot export succeeded with 4.6.stable
Zip creation succeeded
butler validate web-export succeeded and detected index.html as an HTML5 app
I did not run a real push because no itch target was configured yet
Use it:

Double-click deploy-web.cmd
Or run .\scripts\deploy-web.ps1
One required manual step remains on itch.io after the first upload: set the page type to HTML and mark that channel as playable in browser.

References:

Godot CLI export flow: https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html
Butler push behavior and HTML channel setup: https://itch.io/docs/butler/pushing.html
If you want, the next improvement is trimming the Web export so it stops packaging unused addon example assets.
```
