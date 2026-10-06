# Project Rules

## Tech stack

- Godot version: 4.4.1 (absolute path: "C:\Godot_v4.4.1\Godot_v4.4.1-stable_win64.exe")
- Language: GDScript
- Preserve compatibility with the Godot version used by `project.godot`.
- Do not assume APIs from another Godot version.

## Core architecture

- Prefer composition over inheritance.
- Gameplay systems must not depend directly on UI.
- UI may observe gameplay state and request actions, but must not become the authoritative owner of gameplay state.
- Use signals where they reduce coupling between systems.
- Configuration and tunable gameplay data should generally live in `Resource` objects.
- Avoid hardcoded `NodePath` values when exported references, groups, resources, signals, or explicit dependency injection are more appropriate.
- Do not introduce Autoload/global singletons unless the state is genuinely application-wide and the choice is justified.
- Avoid duplicated sources of truth.

## Existing code

This is an existing game project, not a greenfield project.

### Project map and design evidence

- Start orientation with `docs/PROJECT_MAP.md`, `docs/ARCHITECTURE.md`, and `docs/GAMEPLAY.md`; verify affected facts against current source before editing.
- These documents describe the existing implementation. Keep them aligned with relevant changes and distinguish `VERIFIED`, `LIKELY`, and `UNKNOWN`; source wiring is not proof of runtime behavior.
- For gameplay requirements, inspect `assets/Ремейк игры/мегапомятка.docx`, relevant `помятка*.txt` files under that tree, and `FNAB.md`. Preserve table headers when reading the DOCX. Treat notes as design evidence, not proof that a feature is implemented.
- The memo's first-night difficulty row is Berry/Blacky/Dog/Sann/Old Creeper = 0/0/0/1/0. N1 activates only Sann. `RouteAI` activates the remaining four characters when their configured levels are nonzero. Profiles `resources/night_1.tres` through `night_6.tres` contain the memo's levels; they do not implement menu selection or saved progression.
- Character identities confirmed by the user: Blacky (`BLACKY`, also spelled Блеки/Блэки in assets) is the bear; Berry (`BERRY`, Берри) is the rabbit. The user subsequently clarified that Dog walks and uses door defense; vents/fan defense belong to Blacky. Berry also uses the door. OC uses the camera-2 shocker; its reset, cost 20 and cooldown 8 seconds are approved provisional rules.
- Consult `docs/GAMEPLAY_PARAMETERS.md` for confirmed decisions, implemented provisional values and remaining proposals. Runtime N1 tuning lives in `NightConfig` (`scripts/night_config.gd`, `resources/night_1.tres`); the ledger is not loaded by the game. Consult `docs/AUDIO_MAP.md` for night sound wiring and unused audio.
- If notes conflict with current behavior or leave gameplay rules unclear, report the distinction and ask the user before changing those rules.
- Current room IDs, positions and route indexes belong to `AnimatronicMgnt`; route data lives in `AnimatronicRoutes` Resource. `RouteAI` owns attack/check counters and receives time from Night. Night owns fans, shock cooldown, power and accepted camera state. Surveillance buttons select `CameraPicture` functions and manager events refresh the selected view; `Camera.gd` controls office panning. No room graph exists.
- Use existing assets under `assets/Ремейк игры/камера/` when repairing legacy camera resource references. Check the exact filename and its import UID; preserve scene resource IDs, node composition and signal wiring unless explicitly required otherwise.
- Validate changed scenes explicitly. A clean editor import or menu startup alone does not establish that Night loads or that its gameplay works.

Before modifying an unfamiliar system:

1. Inspect the relevant scenes, scripts, resources, and signal connections.
2. Determine what is already implemented.
3. Trace where the authoritative state lives.
4. Reuse existing systems when practical.
5. Do not create a parallel implementation of functionality that already exists.

Do not rewrite existing architecture merely because another design appears cleaner.

Prefer the smallest change that integrates with the current project.

If the existing architecture is unclear, investigate first and explicitly state what is known, inferred, and still unknown.

## Changes

- Do not touch unrelated files.
- Keep diffs small and focused.
- One task should normally correspond to one coherent change.
- Do not perform opportunistic refactors unless they are required for the task.
- Explain meaningful architecture changes.
- Never silently change game design or gameplay rules.
- Preserve existing behavior unless the task explicitly requires changing it.
- Run available tests and validation after modifications.
- Inspect the final diff before considering the task complete.

## Scenes

- Scenes own composition.
- Scripts own behavior.
- Resources own configuration.
- Avoid putting substantial gameplay logic directly into UI scenes.
- Before changing a `.tscn` file, inspect its attached scripts, referenced resources, and important signal connections.
- Be careful when editing:
  - node hierarchy
  - node names
  - NodePaths
  - signal connections
  - exported references
  - resource IDs
  - scene inheritance
- Do not rename or move nodes that other scripts depend on without updating and validating all references.

## Signals

- Prefer signals for communication when the sender should not need to know the receiver.
- Avoid signal chains that make gameplay flow impossible to trace.
- Keep signal ownership clear.
- Do not connect the same signal multiple times unintentionally.
- Consider lifecycle issues when nodes enter or leave the scene tree.

## Resources and configuration

Use `Resource` objects for data such as:

- animatronic configuration
- movement parameters
- routes
- difficulty values
- night configuration
- camera/location metadata
- tunable gameplay values

Do not move runtime state into Resources unless shared mutable Resource state is explicitly intended.

## Gameplay state

Each piece of gameplay state should have one clear owner.

Examples include:

- current animatronic location
- current camera
- door state
- power level
- night time
- game phase
- win/lose state

UI should reflect this state rather than maintain an independent copy.

When modifying stateful gameplay code, consider invalid transitions and simultaneous events.

## Animatronics, rooms, and cameras

Before changing these systems, determine how the existing project currently represents:

- rooms / locations
- room connectivity
- cameras
- camera-to-room relationships
- animatronic current position
- movement routes
- movement timing
- attack conditions

Do not introduce a new representation until the existing representation has been understood.

## Validation

After relevant changes, check when possible:

- GDScript parse errors
- scene loading errors
- invalid resources
- broken script attachments
- broken NodePaths
- broken signal connections
- missing exported references
- gameplay state regressions

For gameplay changes, consider edge cases such as:

- state changing while the camera is open
- animatronic movement during another transition
- rapid repeated player input
- timers firing after the owning state changed
- scene reloads
- win and lose conditions occurring close together

## Agent behavior

When working on an unfamiliar part of the project:

- investigate before editing;
- cite relevant files and symbols in explanations;
- distinguish verified behavior from assumptions;
- ask other specialized agents to inspect or review when appropriate.

Do not invent missing game design.

If requirements are ambiguous, preserve existing behavior and make the smallest reasonable assumption.

## Completion

A task is complete only when:

- the requested behavior is implemented;
- unrelated behavior was not intentionally changed;
- changed files have been reviewed;
- available validation has been run;
- remaining risks or unverified behavior are reported.

## Specialized agents

Use specialized subagents when their role matches the task.

- `recon`
  - Read-only investigation of unfamiliar existing code.
  - Use before modifying systems whose current implementation is unclear.
  - Especially useful for tracing scenes, Resources, signals, rooms,
    cameras, animatronics, and runtime flow.

- `architect`
  - Read-only architecture and implementation planning.
  - Use after relevant existing behavior has been understood.
  - Prefer minimal integration with existing systems over rewrites.

- `gameplay`
  - Implements focused gameplay changes.
  - Use for animatronics, rooms, cameras, doors, power, night state,
    game-state logic, and related systems.

- `scene_ui`
  - Handles focused scene and UI changes.
  - Use for `.tscn` composition, HUD, camera monitor UI, menus,
    visual interaction wiring, and presentation.

- `tester`
  - Validates gameplay and scene behavior.
  - Use after implementation or when reproducing suspected bugs.

- `reviewer`
  - Read-only final review.
  - Use for non-trivial gameplay changes before considering them complete.

### Delegation workflow

For unfamiliar existing systems:

`recon -> architect -> user/implementation decision`

For non-trivial implementation work:

`recon if needed -> architect -> gameplay/scene_ui -> tester -> reviewer`

Do not start implementation while important behavior of the affected
existing system is still unknown.

Do not automatically fix reviewer findings unless explicitly requested.
