# LD59 Signal Game

```bash
butler push LD59.zip akatona/geordi-la-forge:web
```

## fixes
- fan blade animation stutters like I repeat the first frame at the end

## to-do
- [ ] environment
  - [ ] build models
  - [ ] world
    - [ ] rooms/doors/props
    - [ ] lighting (switches, lamps, fires, etc.)
    - [ ] particles (dust, etc.)
- [ ] HUD
  - [ ] refine noise overlay
- sound
  - [ ] placeholder music 
  - [ ] placeholder sound fx
    - [ ] ping
    - [ ] footsteps

Questions:
- what are you doing when "Validation: headless Godot 4.6.1 startup passed cleanly. A manual playtest is still needed to confirm the reset timing feels right in-game."

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
It exports to build\web\index.html, creates build\arana-grande-web.zip, then runs butler push build\web username/game:web.
Useful flags:
-Configure to change the saved itch target
-SkipPush to export and zip only
-DryRun to preview the butler upload
-UserVersion 1.2.3 to pass a version to butler
What I validated:

Ran powershell -File .\scripts\deploy-web.ps1 -SkipPush
Godot export succeeded with 4.6.stable
Zip creation succeeded
butler validate build\web succeeded and detected index.html as an HTML5 app
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