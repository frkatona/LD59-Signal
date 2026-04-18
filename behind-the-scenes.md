# Behind The Scenes: Sonar Static Vision Mode

This file explains how the sonar vision feature works, why it was built this way, and where to look if you want to extend it.

## Goal

The player has two visual states:

- Normal first-person view.
- A sonar mode toggled with `G`, where the screen is covered by a mostly black static effect.

While sonar mode is active, pressing `F` sends out a pulse. That pulse briefly reveals tagged objects inside the camera view as a world-space expanding shell. The room itself stays hidden, and walls still block the reveal.

That combination of requirements drives the architecture. A simple material swap on the original scene would not be enough.

## Why This Was Not Implemented As A Single Post-Process

The obvious first idea is "draw static on top of the screen, then reveal things with a shader." That falls apart once you need all of these at once:

- The base world should remain unreadable.
- Only specific objects should be revealable.
- Room geometry should still block those reveals.
- The reveal should be based on world-space distance from the camera when the ping starts.

If the effect were only a screen-space post-process on the main camera, the shader would not easily know which pixels belong to revealable props versus non-revealable room geometry. It also would not have a clean way to keep walls as occluders while preventing them from becoming visible themselves.

The chosen solution is a second render pass in a `SubViewport`:

- The main camera still renders the real scene normally.
- A full-screen static overlay hides that normal scene when sonar mode is active.
- A second camera renders a stripped-down proxy version of the scene into a texture.
- That texture is composited on top of the static overlay, but only bright revealed pixels survive.

This keeps the gameplay scene intact and gives explicit control over what can be seen in sonar mode.

## Files And Responsibilities

- `scripts/sonar_vision_controller.gd`
  Owns the feature state, ping timing, camera sync, proxy generation, and shader parameter updates.
- `scenes/main.tscn`
  Wires the feature into the level by attaching the controller to `Main`, adding the sonar viewport and overlay nodes, and tagging scene nodes with sonar groups.
- `shaders/sonar_static_overlay.gdshader`
  Generates the mostly-black animated static layer.
- `shaders/sonar_reveal.gdshader`
  Makes revealable proxy meshes light up only when the expanding shell reaches them.
- `shaders/sonar_composite.gdshader`
  Converts the sonar render texture into an alpha-blended overlay by discarding near-black pixels.

## Scene Structure

The main additions to `scenes/main.tscn` are:

- `Main`
  Now has `sonar_vision_controller.gd` attached.
- `SonarViewport`
  A dedicated off-screen 3D render target.
- `SonarViewport/SonarCamera`
  Mirrors the player camera so the sonar pass sees the same view.
- `SonarViewport/RevealProxies`
  Holds proxy meshes for objects in the `sonar_reveal` group.
- `SonarViewport/OccluderProxies`
  Holds proxy meshes for objects in the `sonar_occluder` group.
- `VisionOverlay`
  A `CanvasLayer` that sits above the game view.
- `VisionOverlay/OverlayRoot/StaticRect`
  Full-screen black/static layer.
- `VisionOverlay/OverlayRoot/SonarRect`
  Full-screen texture showing the sonar `SubViewport` result.

The room bodies are tagged with `sonar_occluder`. The placed chair is tagged with `sonar_reveal`.

That group split is the public contract for the system. New props become sonar-visible by joining `sonar_reveal`. Geometry that should block visibility but never appear in the pulse belongs in `sonar_occluder`.

## Runtime Flow

### 1. Startup

When `sonar_vision_controller.gd` enters `_ready()` it does five important things:

1. Ensures the `toggle_sonar_mode` and `sonar_ping` input actions exist.
2. Creates the shader materials in code.
3. Configures the full-screen overlay UI.
4. Configures the sonar `SubViewport`.
5. Builds proxy meshes for every tagged sonar node in the scene.

The materials are created in code instead of being embedded directly in the scene so the logic and shader ownership stay in one place.

### 2. Proxy Scene Build

The controller does not render the original tagged nodes directly in the sonar viewport. Instead, it walks each tagged branch, collects `MeshInstance3D` descendants, and creates proxy `MeshInstance3D` nodes inside the viewport.

This is one of the most important implementation choices.

Why proxies were chosen:

- They let the sonar pass use different materials from the main scene.
- They avoid modifying imported assets or room materials.
- They let the sonar viewport render only the minimum geometry needed.
- They separate "normal game rendering" from "special reveal rendering."

Each proxy keeps:

- The source mesh.
- The source global transform.
- The source visibility state.

The controller then re-syncs proxy transforms every frame. That keeps the feature compatible with moving revealable objects later without redesigning the system.

### 3. Camera Sync

The sonar camera copies the player camera transform and projection properties every frame.

That is necessary because the sonar pass must align exactly with the main first-person view. If the projection mismatched, the revealed pulse would drift or appear detached from the real camera framing.

The controller syncs:

- Global transform.
- Projection mode.
- Near/far clip.
- FOV.
- Size/frustum offsets.
- Horizontal and vertical offsets.

### 4. Mode Toggle

Pressing `G` toggles `sonar_mode_enabled`.

When sonar mode turns on:

- The overlay becomes visible.
- The player still moves normally.
- The static layer now hides the world.

When sonar mode turns off:

- The overlay is hidden immediately.
- Any active ping is canceled.
- The pulse radius is reset.

Canceling the pulse on exit avoids stale reveal state when re-entering the mode.

### 5. Ping Logic

Pressing `F` only matters while sonar mode is active and the cooldown has expired.

When a ping starts:

- `ping_active` becomes `true`.
- `ping_radius` resets to `0.0`.
- `ping_origin_ws` captures the current camera world position.
- `ping_cooldown_remaining` is reset.

Every frame while the ping is active:

- `ping_radius` expands by `ping_speed * delta`.
- Once the radius exceeds `ping_max_radius`, the pulse ends.

This keeps the pulse deterministic and easy to tune. It also means the reveal is truly world-space: the shell expands outward from the camera position that existed when the user pressed `F`.

## Shader Design

### Static Overlay Shader

`sonar_static_overlay.gdshader` produces the "mostly-black static" layer.

It mixes three ingredients:

- A very dark base value.
- Per-pixel pseudo-random flicker derived from `FRAGCOORD` and `TIME`.
- A fast scanline pattern from a sine wave in UV space.

The output is then clamped so the result stays dark. That clamp matters because the design goal is not TV snow that reveals the scene underneath. The goal is near-black obscuration with a little motion so the effect feels intentional rather than like a plain black screen.

### Reveal Shader

`sonar_reveal.gdshader` is applied to reveal proxies in the sonar viewport.

In the vertex stage it computes each fragment's world position from `MODEL_MATRIX`.

In the fragment stage it computes:

- The distance from the fragment to `ping_origin_ws`.
- The distance between that value and the current `ping_radius`.
- A soft falloff across the shell thickness.

The fragment becomes bright only when it lies near the expanding shell:

`abs(distance(world_position, ping_origin_ws) - ping_radius) <= ping_band_width`

The actual shader uses `smoothstep` for a soft edge rather than a hard threshold. That avoids a brittle, aliased-looking ring.

### Composite Shader

`sonar_composite.gdshader` takes the sonar viewport texture and converts it into an overlay.

The viewport contains:

- Black occluders.
- Black background.
- Bright reveal fragments.

The composite shader treats near-black as transparent and keeps bright pixels. That way:

- The static layer remains dominant everywhere else.
- Only revealed fragments show through.

This is simpler and more reliable than trying to make the sonar viewport itself transparent with mixed depth behavior.

## Why Occluders Are Rendered As Black Geometry

The room should block revealed props, but it should never become visible itself.

Rendering occluders as black geometry inside the sonar pass solves both requirements:

- They still write depth, so props behind them do not render.
- They still produce black output, so the composite shader removes them visually.

This is the central trick that makes the effect work.

If occluders were omitted entirely, the player would see revealable props through walls. If occluders were rendered visibly, the room would leak into sonar mode.

## Why Inputs Are Both In `project.godot` And Ensured In Code

The new actions are registered in `project.godot` so the project has explicit editable bindings.

The controller also calls `_ensure_input_actions()` at runtime. That is defensive. It prevents the feature from silently breaking if someone deletes the actions in project settings, or if the scene is reused elsewhere before the config is updated.

For this project size, that duplication is acceptable. The tradeoff favors robustness over strict single-source purity.

## Tuning Notes

The script exports the key gameplay parameters:

- `ping_cooldown_seconds`
- `ping_speed`
- `ping_max_radius`
- `ping_band_width`
- `ping_band_fade`

The script defaults are conservative. The scene currently overrides some of them on `Main` to make the effect more readable in the current room:

- `ping_cooldown_seconds = 0.3`
- `ping_speed = 50.0`
- `ping_band_width = 3.0`
- `ping_band_fade = 0.5`

Those overrides matter because the room is small. The earlier slower values produced a more literal expanding shell, but the current faster values make the feature feel more responsive in this prototype.

If the room gets larger later, these values should be revisited together rather than individually.

## How To Extend The System

### Add A New Revealable Object

1. Place the object in the scene.
2. Add its root node to the `sonar_reveal` group.
3. Make sure the object contains one or more `MeshInstance3D` descendants.

No shader work is needed.

### Add New Blocking Geometry

1. Add the node to the `sonar_occluder` group.
2. Make sure it contains `MeshInstance3D` descendants.

That geometry will block sonar visibility without becoming visible in sonar mode.

### Add Moving Props

The current controller already syncs proxy transforms every frame, so moving revealable props should work without architectural changes.

### Add Per-Object Colors Or Categories

Right now all reveals are grayscale because the design goal was "sonar shape information," not semantic coloring. If you want different classes of objects later, the clean extension point is the reveal material setup in `sonar_vision_controller.gd`.

## Current Limitations

- Proxy sets are built once at startup. If objects are spawned dynamically later, the controller will need a refresh path.
- The tutorial assumes revealable and occluding content ultimately resolves to `MeshInstance3D` descendants.
- The sonar system currently has no sound, HUD, or gameplay feedback besides the visual effect.
- The effect is tuned for this small prototype room, not for a larger level.

## Why This Architecture Is A Good Fit For The Prototype

This implementation is more structured than a quick material hack, but that was deliberate.

It gives the project:

- A clean separation between gameplay rendering and sonar rendering.
- Explicit authoring rules through scene groups.
- Depth-correct occlusion.
- A world-space pulse instead of a fake screen-space wipe.
- A clear path for extension if more props or rooms are added later.

That makes it a reasonable prototype architecture: simple enough to maintain, but not so disposable that it has to be replaced immediately once the game grows a little.
