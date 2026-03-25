# Architecture

This project is structured around a fairly flat game loop:

1. `main.lua` gathers raw Love2D input.
2. `systems/systems_handle_input.lua` turns that into `FrameInputs`.
3. `game.lua` advances fixed-step game state.
4. `systems/systems_sim.lua` runs simulation systems over the ECS world.
5. `systems/systems_present_runtime.lua` updates and draws presentation state.

The optional networking path inserts lockstep input synchronization before the fixed simulation tick.

## Flow And Layers

```mermaid
flowchart TD
    A["Love2D runtime"] --> B["main.lua"]

    B --> C["grabInput()"]
    C --> D["systems_handle_input.lua"]
    D --> E["FrameInputs"]

    B --> F["game.lua::Game.update(dt, frameInputs)"]
    E --> F

    F --> G{"Network enabled?"}
    G -->|No| H["tickFixed()"]
    G -->|Yes| I["lockstep.lua\nreceive() + tick()"]
    I --> H

    H --> J["runFixedGameplayTick()"]
    J --> K["systems_sim.lua"]

    K --> L["systems_physics.lua"]
    K --> M["systems_combat.lua"]

    L --> N["world.lua + components.lua"]
    M --> N
    M --> O["spawners.lua"]

    F --> P["round / match state transitions"]
    P --> O
    O --> Q["maps.lua"]

    B --> R["systems_present_runtime.lua"]
    R --> S["present_camera / pose / draw / ui / cursor / effects"]
    S --> T["assets.lua"]
    S --> N

    U["Optional relay/main.lua"] <---> I
```

## Dependency Overview

```mermaid
flowchart LR
    Main["main.lua"]
    Game["game.lua"]
    Input["systems_handle_input.lua"]
    Runtime["systems_present_runtime.lua"]

    Sim["systems_sim.lua"]
    Physics["systems_physics.lua"]
    Combat["systems_combat.lua"]

    World["world.lua"]
    Components["components.lua"]
    Spawners["spawners.lua"]
    Maps["maps.lua"]
    Assets["assets.lua"]
    Lockstep["lockstep.lua"]
    Relay["relay/main.lua"]

    PresentCamera["systems_present_camera.lua"]
    PresentDraw["systems_present_draw.lua"]
    PresentPose["systems_present_pose.lua"]
    PresentUi["systems_present_ui.lua"]
    Effects["systems_effects.lua"]
    Cursor["systems_cursor.lua"]

    Main --> Game
    Main --> Input
    Main --> Runtime

    Game --> Sim
    Game --> Spawners
    Game --> Maps
    Game --> World
    Game --> Components
    Game -. optional .-> Lockstep

    Input --> World
    Input --> Components

    Sim --> Physics
    Sim --> Combat
    Sim --> World
    Sim --> Components

    Physics --> World
    Physics --> Components

    Combat --> World
    Combat --> Components
    Combat --> Spawners

    Spawners --> World
    Spawners --> Components

    Runtime --> Assets
    Runtime --> Effects
    Runtime --> PresentCamera
    Runtime --> PresentDraw
    Runtime --> PresentPose
    Runtime --> PresentUi
    Runtime --> Cursor

    PresentCamera --> World
    PresentCamera --> Components
    PresentDraw --> World
    PresentDraw --> Components
    PresentDraw --> Assets
    PresentPose --> World
    PresentPose --> Components
    PresentUi --> Assets
    Effects --> World
    Effects --> Components
    Effects --> PresentCamera

    World --> Components

    Relay -. network peer .- Lockstep
```

## Notes

- `game.lua` is the orchestration layer. It owns round state, match state, fixed-step ticking, and the optional lockstep path.
- `world.lua` and `components.lua` form the ECS foundation used by both simulation and presentation systems.
- `systems/systems_sim.lua` is an ordered pipeline over gameplay systems rather than a deep hierarchy.
- `systems/systems_present_runtime.lua` acts as the presentation coordinator, bundling camera, pose, effects, UI, and drawing.
- `spawners.lua` is shared infrastructure used both for world setup and runtime combat effects like bullets and events.
