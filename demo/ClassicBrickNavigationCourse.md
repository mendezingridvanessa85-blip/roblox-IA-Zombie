# Classic Brick Navigation Course

The demonstration course is intentionally built as a visual stress test for the R6 zombie AI.

## Design rules

- Visible geometry uses black, grey and white classic brick materials.
- No billboards or futuristic presentation props are required.
- The course looks restrictive, but its navigation geometry is deliberate.
- Alternate wall openings are kept wide enough for the configured R6 agent radius.
- Low barriers are below the configured jump capability.
- The maze uses staggered masses instead of dead ends.
- Decorative staircase blocks are non-colliding; a continuous hidden navigation ramp provides a reliable traversal surface.
- The final elevated bridge removes the ambiguous downward transition that caused inconsistent navmesh results during early testing.

## Runtime debug view

Set this Attribute on a zombie:

```lua
workspace.Zombie:SetAttribute("DebugMode", true)
```

The planner renders:

- Cyan: winning route.
- Orange: jump waypoints.
- Muted purple: evaluated alternatives.

The debug geometry is temporary and is cleared every time a path is replaced or the controller is destroyed.
