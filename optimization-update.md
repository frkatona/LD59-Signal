# Optimization Update

## Why this changed

Fullscreen play on 4K displays was dropping frame rate hard enough to justify trading image quality for stability. The main cost was not just the base 3D scene. This project also renders a second 3D pass for the sonar/noise view through a `SubViewport`, so high display resolutions multiplied the GPU cost quickly.

## Techniques implemented

### 1. Runtime 3D resolution scaling

The main viewport now reduces its internal 3D render scale in the `Performance` profile instead of always rendering at native fullscreen resolution.

- `High`: `scaling_3d_scale = 1.0`
- `Performance`: `scaling_3d_scale = 0.67`

This keeps 2D UI and HUD elements sharp while lowering the cost of the 3D scene.

### 2. Lower-resolution sonar pass

The sonar `SubViewport` no longer always matches the full window size.

- `High`: sonar viewport renders at full window resolution
- `Performance`: sonar viewport renders at `50%` linear resolution

This matters because the sonar effect is effectively a second scene render, not just a fullscreen shader.

### 3. Stop rendering the sonar viewport when sonar mode is off

When sonar mode is disabled, the sonar `SubViewport` is switched to `UPDATE_DISABLED` instead of continuing to refresh every frame. That removes an entire render pass while normal view is active.

### 4. Disable selected expensive effects in the performance tier

The `Performance` profile turns off:

- environment glow
- room omni-light shadows
- orb omni-light shadows

The authored scene values are cached on startup and restored in `High`, so the runtime override is reversible and does not hardcode scene assumptions.

### 5. Add automatic and manual quality selection

The game now supports:

- `Auto`
- `High`
- `Performance`

`Auto` switches to `Performance` at `5,000,000+` pixels, which catches common 4K-like fullscreen cases without forcing lower quality on smaller displays.

### 6. Add debug visibility for graphics state

The debug overlay now shows:

- selected quality mode
- effective quality profile
- current main 3D scale
- current sonar viewport resolution

That makes it easier to verify whether the optimization path is active during testing.

## Sources used

These were the main references used to justify the implementation:

1. Godot resolution scaling docs  
   https://docs.godotengine.org/en/4.3/tutorials/3d/resolution_scaling.html

   This is the basis for lowering `Viewport.scaling_3d_scale` at runtime. The docs explicitly describe resolution scaling as a direct way to reduce GPU cost in GPU-bound scenes, and note that scales below `1.0` reduce rendering cost at the expense of sharpness.

2. Godot viewport / SubViewport update behavior  
   https://docs.godotengine.org/en/4.4/tutorials/rendering/viewports.html  
   https://docs.godotengine.org/en/stable/classes/class_subviewport.html

   These were the basis for disabling sonar viewport updates when the texture is not needed every frame. The key takeaway is that a `SubViewport`'s render target update mode can be controlled explicitly, so it does not have to keep re-rendering when the feature is inactive.

3. Local project inspection

   The repo itself showed the real bottleneck pattern:

- the project uses the `gl_compatibility` renderer
- the sonar system renders a full extra `SubViewport`
- that viewport was previously resized to the full visible window every frame
- the scene also used glow and shadowed omni lights, which become more expensive at large resolutions

The docs informed the engine-side techniques. The exact thresholds and profile values were chosen for this project.

## Resulting strategy

The optimization approach used here is:

- keep the UI crisp
- reduce 3D resolution first
- reduce the sonar pass separately
- avoid rendering work for inactive systems
- disable a few expensive effects only in the lower-quality tier

This is intentionally a pragmatic 4K mitigation pass, not a visual-quality-first solution.
