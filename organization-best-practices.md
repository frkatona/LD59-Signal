# Organization Best Practices

## Recommended structure for this project

As this level grows to 6+ rooms, the main scene should stop being the place where every room, interactable, and gameplay dependency is authored inline.

The practical structure I recommend is:

- `main.tscn` as the composition root
- one scene per room
- one scene per reusable interactable
- one local controller script per room or interactable
- one small global controller for menu / game-state orchestration

## What should stay in `main.tscn`

`main.tscn` should own:

- the player
- global UI and pause menu
- global audio
- global progression state
- high-level room sequencing
- references to the active room scenes

It should not own deep room internals like:

- a specific door mesh
- a specific switch animation player
- a specific room light node
- a specific win-orb collision area

## Room boundaries

Each room should ideally be its own scene:

- `room_01.tscn`
- `room_02.tscn`
- `room_03.tscn`
- `room_04.tscn`
- `room_05_large.tscn`
- `room_06_final.tscn`

Each room scene should expose a narrow interface through a room-local controller script, for example:

- entry marker
- exit marker
- room-local `NavigationRegion3D`
- arrays or groups for enemies and interactables
- references to its doorway controllers

That way, `main.tscn` talks to the room controller, not to deep internal node paths.

## Dependency wiring

For anything outside a script's own local subtree, prefer explicit exported references over hardcoded `$A/B/C/D` paths.

Recommended usage:

- use `%UniqueName` for tightly local children inside a reusable scene
- use `@export var some_node: Node3D` for cross-branch dependencies
- use groups only for multi-node discovery, like sonar reveal / sonar occluders / enemies

Avoid relying on absolute tree shape for gameplay logic. Tree shape changes often during level design, and deep hardcoded paths are fragile in collaborative work.

## Reusable interactables

These should become their own scenes with local scripts:

- door
- light switch
- win object
- enemy spawn or enemy placement helper

Each should own its own logic as much as possible. For example, a door scene should know how to open itself and expose a simple signal or method, instead of depending on a global level script to animate a specific node.

## Collaboration benefits

This structure reduces Git conflicts because:

- room edits land in room scene files, not always in `main.tscn`
- interactable behavior lands in local scripts, not one global script
- two people can work on different rooms without constantly rebasing a giant scene file
- scene refactors become less likely to silently break unrelated gameplay code

## Immediate next-step recommendation

Before adding many more rooms, the next practical cleanup should be:

1. move repeated room geometry into room scenes
2. move door and switch behavior into scene-local scripts
3. replace the most fragile root-level `@onready $...` lookups with exported references
4. keep `main.tscn` responsible for sequencing rooms, not micromanaging their internal nodes

That is the safest path if this level is going to keep expanding or be edited collaboratively.
