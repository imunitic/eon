# 🧩 Eon RenderGraph & RenderPipeline Design

## 1. Overview

Eon’s rendering architecture follows the same philosophy as its ECS Core:
**minimal, composable, and data-oriented**.

The rendering stack is divided into three conceptual layers:

| Layer | Responsibility | Analogy in ECS |
|--------|----------------|----------------|
| **RenderGraph** | Declarative DAG of *Phases* with attached *Collectors*. Describes what phases exist and in what order. | ECS Phases |
| **RenderPipeline** | Orchestrates the execution of the RenderGraph, runs each collector, and produces the final render command list. | ECS Pipeline |
| **RenderBackend** | Executes render commands on the GPU using a specific graphics API (GL, WebGL, Metal, etc.). | Engine Subsystem |

---

## 2. RenderGraph — Declarative Structure

> A RenderGraph is a **directed acyclic graph (DAG)** of *Phases*.
> Each phase can have one or more *Collectors* attached.

### Concepts

- **Phase** – a logical step of the rendering process  
  (e.g. `Geometry`, `Lighting`, `PostProcess`, `UI`).

- **Collector** – a small function or system that gathers drawables,
  lights, or other renderable data from the ECS `World`.

- **Dependency Edges** – define ordering between phases.
  Example:  
  `Geometry → Lighting → PostProcess → UI`

### Responsibilities

- Describe *what* rendering stages exist.
- Specify *in which order* they should execute.
- Contain no GPU or shader logic — the RenderPipeline handles execution.

### Example

```ocaml
(* phase.mli *)
type id = [ `Geometry | `Lighting | `PostProcess | `UI ]

type collector = {
  run : World.t -> RenderCommand.t list;
}

type phase = {
  id : id;
  before : id list;          (* phases that must run before this one *)
  collectors : collector list;
}

type t = phase list
```

---

## 3. RenderPipeline — Procedural Orchestrator

> The RenderPipeline walks the RenderGraph in topological order,
> runs each collector, and produces a final list of `RenderCommand`s.

### Responsibilities

- Topologically sort the RenderGraph phases.
- Invoke each collector’s `run` function.
- Merge and flatten all produced render commands.
- Hand off the resulting list to the `RenderBackend` for drawing.

### Example Skeleton

```ocaml
(* render_pipeline.mli *)

module RenderPipeline : sig
  (** Execute all phases in the provided RenderGraph, returning a flat list
      of render commands ready for the RenderBackend. *)
  val run :
    RenderGraph.t ->
    World.t ->
    RenderCommand.t list

  (** Utility: validate that the graph is acyclic and all dependencies exist. *)
  val validate : RenderGraph.t -> (unit, string) result
end
```

---

## 4. RenderBackend — Execution Layer

> The RenderBackend consumes a list of render commands and executes them
> on the target graphics API.

### Responsibilities

- Interpret and execute render commands:
  - `Draw`, `Clear`, `SetCamera`, etc.
- Manage GPU state, shaders, and resources.
- Remain replaceable — different backends can exist for GL, WebGL, etc.

### Example

```ocaml
(* render_backend.mli *)

type render_command =
  | Clear of Color.t
  | SetCamera of Camera.t
  | Draw of Drawable.t * Material.t * Transform.t

val execute : render_command list -> unit
```

---

## 5. Putting It All Together

1. **RenderGraph** defines the structure:
   ```
   Geometry → Lighting → PostProcess → UI
   ```

2. **RenderPipeline** executes the graph:
   - Runs each collector in dependency order.
   - Produces a list of commands:
     ```ocaml
     [ SetCamera cam;
       Draw (mesh1, mat1, tr1);
       Draw (mesh2, mat2, tr2);
       ... ]
     ```

3. **RenderBackend** executes the commands:
   - Binds shaders, uploads uniforms, issues draw calls.

---

## 6. Example Execution Flow

```
RenderGraph
 ├─ GeometryPhase
 │   └─ GeometryCollector
 ├─ LightingPhase
 │   └─ LightCollector
 ├─ PostProcessPhase
 │   └─ ScreenCollector
 └─ UIPhase
     └─ UICollector

RenderPipeline
 └─ Traverses the graph in order:
      Geometry → Lighting → PostProcess → UI
      Collects all commands from collectors.
      Produces a flat command list.

RenderBackend
 └─ Executes the commands on the GPU.
```

---

## 7. Why This Design

| Principle | Manifestation |
|------------|----------------|
| **Minimal** | Simple DAG and execution loop — no GPU resources inside the graph. |
| **Composable** | Phases and collectors are small modules. |
| **Data-Oriented** | RenderGraph is pure data; RenderPipeline performs orchestration. |
| **Extensible** | New passes or collectors can be added without modifying core logic. |
| **Backend-Agnostic** | Final command list decouples logic from graphics API. |
| **Eon Spirit** | The rendering pipeline mirrors the ECS pipeline — declarative + procedural separation. |

---

## 8. Implementation Notes

- Each **Collector** can be a functor, allowing dependency injection
  of systems or resources (e.g. camera service, drawable store).
- The **RenderPipeline** should cache the sorted order of phases
  to avoid re-sorting each frame.
- Future extension: support conditional phases (enabled/disabled by settings).

---

## 9. Summary

> **RenderGraph** — describes the *structure*.  
> **RenderPipeline** — drives *execution*.  
> **RenderBackend** — performs the *drawing*.

Together, they form Eon’s lightweight, data-driven rendering model:
a clean balance between raw flexibility and the ECS core’s minimalism.
