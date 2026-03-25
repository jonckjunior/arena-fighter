# Arena Fighter Architecture

## Overview

The project is split into two layers:

- **Pure simulation**: deterministic game state, match flow, world mutation, gameplay input consumption
- **Love runtime/presentation**: window boot, raw device input, cursor/camera, rendering, audio, UI

The main reason for this split is to let us run the game simulation outside of Love. That is what enables `lua lua_test.lua`, determinism checks, monkey-style simulation runs, and future tooling.

The important rule is:

- `game.lua` and the simulation layer must not depend on `love.*`
- the runtime layer may depend on `love.*`

## Main Pieces

### `game.lua`

`game.lua` is the simulation session.

It owns:

- match lifecycle: `waiting`, `playing`, `roundOver`, `matchOver`
- round/match resets
- world creation
- fixed timestep accumulation
- optional lockstep/network progression
- the public instance API:
  - `Game.new(config)`
  - `game:load()`
  - `game:update(dt, frameInputs)`
  - `game:getState()`
  - `game:getWorld()`
  - `game:getStateHash()`

It does **not** own:

- asset loading
- drawing
- cursor state
- camera state
- UI
- audio playback
- Love boot

### `systems/systems_sim.lua`

This is the pure simulation facade.

It runs:

- input application
- physics
- combat
- death/lifetime
- round-over queries

It also provides `discardPresentationEvents(w)` for headless runs. This matters because gameplay systems can spawn `soundEvent` and `shakeEvent` entities, and in a pure simulation run there may be no presentation layer installed to consume them.

### `systems/systems_present_runtime.lua`

This is the Love-facing runtime adapter.

It owns:

- `Runtime.init()`
- turning raw Love input into gameplay-ready `frameInputs`
- cursor updates
- camera updates
- drawing
- presentation hooks installed into `Game`

This module is allowed to use `love.graphics`, `love.audio`, `love.mouse`, etc.

### `main.lua`

`main.lua` is the app wiring layer.

It does this:

1. initialize Love/window/canvas
2. initialize runtime/presentation
3. create a `Game` instance
4. install runtime hooks into that instance
5. each frame:
   - read raw input
   - update presentation input state
   - build gameplay-ready frame inputs
   - call `game:update(...)`
   - update the camera
   - draw through the runtime

### `lua_test.lua`

This is the proof that the split is real.

It requires only `game.lua`, creates a game instance, feeds gameplay-ready inputs, and checks:

- deterministic replay
- full match lifecycle progression

If this file starts needing Love, the architecture has regressed.

## Data Flow

Normal runtime flow:

1. Love gives us raw input in `main.lua`
2. `systems_present_runtime.lua` converts raw input into gameplay-ready per-player frame inputs
3. `game:update(dt, frameInputs)` advances the fixed-step simulation
4. simulation mutates the world
5. runtime hooks update presentation-only state
6. runtime draws the current world

Headless flow:

1. test/tool code creates `Game.new()`
2. test/tool code directly provides gameplay-ready frame inputs
3. `game:update(...)` advances simulation with no Love dependency

## Important Rules For Future Changes

### 1. Keep simulation pure

If you are editing `game.lua` or `systems/systems_sim.lua`, do not introduce:

- `love.graphics`
- `love.audio`
- `love.mouse`
- asset loading
- cursor reads
- camera reads

If a feature needs those things, it belongs in the runtime layer.

### 2. Gameplay input is not presentation state

Gameplay systems should consume **frame inputs**, not cursor objects.

The simulation input contract is effectively:

- `up`
- `dn`
- `lt`
- `rt`
- `fire`
- `reload`
- `aimAngle`

If input behavior changes, prefer changing the runtime’s input-building path or the pure input mapping helpers, not the simulation loop.

### 3. `SCursor` is visual

`SCursor` still exists, but only for presentation:

- drawing the cursor
- camera look target

It should not become a gameplay dependency again.

### 4. Presentation events must be consumed or discarded

Gameplay can spawn presentation-only entities like:

- `soundEvent`
- `shakeEvent`

In the runtime path, presentation consumes and destroys them.
In the pure path, simulation discards them via `discardPresentationEvents(w)`.

If you add new presentation-only event entities later, update **both** paths:

- runtime consumption
- headless discard fallback

Otherwise pure tests will silently accumulate junk entities.

### 5. Prefer hooks over back-coupling

`Game` supports hooks:

- `beforeSimulationTick`
- `afterSimulationTick`

If the runtime needs to do per-tick presentation work around simulation, use hooks instead of making `game.lua` import runtime modules.

### 6. Be careful with networking

Networking currently stays inside `Game`, but it is lazy-loaded.

That means:

- plain Lua can still require `game.lua` without immediately loading network dependencies
- if you expand networking, keep that property intact unless you intentionally redesign the boundary

### 7. Avoid wrapper modules unless they add real value

We removed old umbrella/wrapper modules because they hid the actual dependency graph and made it easier to accidentally pull Love-bound code into pure code.

As a rule:

- small focused modules are good
- pass-through wrapper modules are usually not

## When Adding Features

A good way to decide where code belongs:

- **Does it mutate the game world or affect match outcome?**
  - put it in simulation
- **Does it only affect what the player sees/hears?**
  - put it in runtime/presentation
- **Does it create data for both?**
  - produce pure data in simulation, consume it in runtime

Examples:

- bullet hit logic: simulation
- screen shake: runtime consumption of a sim-spawned event
- new HUD widget: runtime
- win-condition logic: simulation
- mouse-to-aim conversion: runtime input building

## Sanity Checks After Refactors

When making architectural changes, these are the fastest regression checks:

- `lua lua_test.lua`
- `luac -p game.lua main.lua systems/systems_sim.lua systems/systems_present_runtime.lua`

If `lua_test.lua` fails because of a Love dependency, the split has probably been violated.
