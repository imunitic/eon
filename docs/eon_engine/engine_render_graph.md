# Eon RenderGraph & RenderPipeline Design

> This is a summary of the authoritative design. See `docs/design/rendering_layer_design.md` for the full specification.

## Overview

The rendering layer is backend-agnostic: the engine and ECS core have no say in how something is rendered. The backend is the only component that decides the order and method of rendering.

Three main components:

| Component | Responsibility |
|-----------|---------------|
| **RenderGraph** | Backend-agnostic collection of rendering commands (polymorphic variants). No entity references — pure rendering instructions. |
| **RenderPipeline** | Phase-based collector pipeline that populates the RenderGraph. Mirrors ECS Pipeline (phases, before/after ordering, topo sort). |
| **RenderingBackend** | Receives the populated RenderGraph and renders it. Has complete control over order, shaders, batching, output format. |

## Frame Flow

```
1. Collect: Signals → Events → Commands
2. Tick:    Systems run, including RenderSystem:
             - Clears RenderGraph resource in world data plane
             - Runs RenderPipeline (collectors populate graph)
             - Stores populated graph back into world data plane
3. Drain:   Signals → Commands → Events
4. Render:  Loop.RENDERER reads RenderGraph from data plane,
            calls Backend.render(graph)
```

RenderSystem **never calls the backend** — it only builds and stores the graph. `Loop.RENDERER` is the only caller of `Backend.render`.

## Commands

Base commands are polymorphic variants defined in `eon_engine`:

```ocaml
type command = [
  | `Draw_sprite of { texture_id : string; position : float * float;
                      rotation : float option; scale : (float * float) option;
                      layer : int; }
  | `Set_camera of { camera : Camera.t; target : (float * float) option; }
]
```

Backends extend using polymorphic variant inclusion:

```ocaml
type command = [
  | Render_commands.command   (* base commands *)
  | `Apply_shader of shader
  | `Draw_particles of particle_system
]
```

## RenderGraph

Generic over command type. No rendering logic — just storage and iteration.

```ocaml
type 'command t

val create : unit -> 'command t
val add    : 'command t -> 'command -> unit
val clear  : 'command t -> unit
val iter   : 'command t -> ('command -> unit) -> unit
```

## RenderPipeline

Mirrors ECS Pipeline. Collectors are `world -> 'command Render_graph.t -> unit` — side-effecting, not returning a list.

```ocaml
val create        : world -> 'command t
val add_phase     : phase -> 'command t -> 'command t
val before        : earlier:phase -> later:phase -> 'command t -> 'command t
val after         : later:phase -> earlier:phase -> 'command t -> 'command t
val add_collector : phase -> 'command collector -> 'command t -> 'command t
val collect       : 'command t -> 'command Render_graph.t -> unit
```

## RenderingBackend

```ocaml
module type S = sig
  type command
  val collectors : (Eon_ecs.World.t -> command Render_graph.t -> unit) list
  val render : command Render_graph.t -> Rendering_result.t
end
```

Backend-specific collectors must be registered in the RenderPipeline manually — the engine cannot discover them automatically.

## Backend Autonomy

The backend decides:
- Rendering order (by layer, shader, distance, etc.)
- Shader usage and techniques
- Output format (terminal, OpenGL, Vulkan, HTML5 Canvas, etc.)

The engine only provides the data.

## Implementation Roadmap

| Phase | Task ID | Description |
|-------|---------|-------------|
| 1 | ecs-021 | `Render_commands.mli` + base collectors |
| 2 | ecs-022 | `Render_graph` (generic over command type) |
| 3 | ecs-023 | `Render_pipeline` (phases, ordering, topo sort) |
| 4 | ecs-024 | `Render_system` (ECS system, world data plane handoff) |
| 5 | ecs-025 | `Rendering_backend.S` + reference backend |
| 6 | ecs-026 | Terminal backend + OpenGL backend |
