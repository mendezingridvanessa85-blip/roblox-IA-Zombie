# Roblox Zombie AI

A server-authoritative R6 zombie AI system for Roblox Studio.

Designed and implemented by **Kj52058** as a modular gameplay-programming portfolio project. The system is built to make an enemy feel persistent around obstacles instead of behaving like a single `MoveTo` call pointed at the player.

## Features

- Server-only authority for target selection, movement state, damage, stun and death.
- R6 validation, primary-part setup and server network ownership.
- Explicit finite-state machine: `Idle`, `Patrol`, `Chase`, `Attack`, `Stunned` and `Dead`.
- Independent controllers for multiple zombies.
- Multi-route path planning using direct goals, sensor steering and recovery-ring candidates.
- Route scoring based on distance, turns, climb cost, jump cost, waypoint density and goal deviation.
- Target prediction, line of sight, last-known-position memory and search behavior.
- Local wall, drop, blocked-path and stuck recovery.
- Server-side hitboxes using `GetPartBoundsInBox` and line-of-sight validation.
- Animator-based R6 animations loaded once per zombie.
- Live debug route rendering: cyan for the selected route, orange for jumps and muted alternatives for rejected candidates.
- Classic black, grey and white brick navigation course designed for reliable R6 traversal.

## Portfolio intent

This project intentionally prioritizes readable architecture, navigation behavior, recovery options and route diagnostics over minimum runtime cost. `DebugMode` can visualize every route evaluated by the planner.

For a production horde, disable debug rendering and tune `PathCandidateCount`, `PathCandidateRings` and the path recompute intervals in `ZombieConfig`.

## Project structure

```text
src/ServerScriptService/ZombieSystem/
├── ZombieBootstrap.server.lua
├── ZombieService.lua
├── ZombieController.lua
├── ZombieStateMachine.lua
├── ZombiePathfinding.lua
├── ZombieNavigationSensor.lua
├── ZombieTargeting.lua
├── ZombieCombat.lua
├── ZombieAnimation.lua
├── ZombieConfig.lua
├── ZombieDemoDirector.server.lua
└── ZombieREADME.lua
```

## Installation

1. Copy `ZombieSystem` into `ServerScriptService`.
2. Place a compatible R6 model named `Zombie` in `Workspace`, or set `IsZombie = true` on the model.
3. The model needs a `Humanoid`, `HumanoidRootPart`, `Head`, `Torso`, both arms and both legs.
4. Set `DebugMode` to `true` on a zombie to show route diagnostics.

## Integration

```lua
local ZombieService = require(game.ServerScriptService.ZombieSystem.ZombieService)

local clone = workspace.Zombie:Clone()
clone.Parent = workspace
clone:PivotTo(CFrame.new(0, 5, 0))

ZombieService:Stun(workspace.Zombie, 2)

workspace.Zombie:SetAttribute("AttackDamage", 25)
workspace.Zombie:SetAttribute("RunSpeed", 18)
workspace.Zombie:SetAttribute("DetectionRange", 80)
```

## Runtime diagnostics

`AIState`, `NavigationMode`, `PathScore`, `PathCandidateIndex`, `PathWaypointCount`, `PathJumpCount` and `PathFailures` are exposed as model Attributes.

## Demonstration course

The demo geometry looks restrictive while preserving R6-safe navigation:

- Alternating walls retain safe side lanes.
- Low barriers are jumpable.
- The maze has no dead ends.
- Brick staircase visuals sit over a continuous navigation ramp.
- A final elevated bridge removes ambiguous descent geometry.

## Limits

Roblox PathfindingService depends on the engine navmesh. Ledge climbing, crawling, off-mesh traversal and fully custom movement need dedicated abilities beyond normal humanoid pathfinding.

## Author

**Kj52058**
