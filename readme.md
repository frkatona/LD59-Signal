# LD59 Signal Game

```bash
butler push LD59.zip akatona/geordi-la-forge:web
```

## fixes
- fan blade animation stutters like I repeat the first frame at the end

## first day to-do
- [ ] basic placeholder environment
  - [x] build models
  - [ ] world
    - [x] rooms/doors/props
    - [x] lighting (switches, lamps, fires, etc.)
    - [ ] particles (dust, etc.)
- [ ] HUD
  - [x] refine noise overlay
  - [x] cooldowns/controls
- sound
  - [x] placeholder music 
  - [x] placeholder sound fx
    - [x] ping
    - [ ] movement (footsteps, jumps, etc.)
      - [x] export as wavs to mitigate latency

- keep player better oriented
  - [x] pause the pulse on hit targets
  - [ ] make some floor/ceiling tiles pulse reactive
- better way to be "signal" theme
- audio still not working in web
- blender
  - model a light switch for the room to make the sonar useful
  - model a handheld oscilloscope
- actually pause the game during pause menu and start screen

### cool clever little ideas
- using enemy's radar occlusion state to still see them by keeping a static pulse illuminating an object behind them 
- encourage the player to pace out the room with their footsteps to navigate while blind

josh ideas:
- make placeholder capsule enemy which hurts player on contact
- make combat system with placeholder stick to swat at enemies, knocking them back (maybe kill them eventually, maybe not, idk)
- ramp up volume on a noise channel when an enemy is near

Questions:
- how to manually run the headless startup in "Validation: headless Godot 4.6.1 startup passed cleanly"

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
