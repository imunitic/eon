# Eon Engine Rendering Layer Design Document

**Design Document Status**: This document contains architectural design decisions and implementation guidelines. Examples are illustrative and subject to iteration in later phases.

## 1. Overview

The rendering layer provides a **backend-agnostic rendering system** where the engine and ECS core have no say in how something is rendered. A rendering backend is the only component that decides the order and method of rendering a `RenderGraph`.

This design maintains the core Eon principles:
- **Minimalism**: Backend interface has minimal methods (ideally just `render`)
- **Extensibility**: Pluggable backends via compile-time functor application
- **Decoupling**: Engine doesn't know about rendering details
- **Flexibility**: Backend decides shader usage, rendering order, and techniques

## 2. Core Architecture

### 2.1 Rendering Layer Components

The rendering layer consists of three main components:

1. **RenderGraph** - Backend-agnostic representation of renderable entities
2. **RenderPipeline** - Collects entities into a render graph (similar to ECS Pipeline)
3. **RenderingBackend** - Backend interface that renders the graph

### 2.2 Frame Flow

```
Frame Order (from Loop.RENDERER):
1. Collect: Signals → Events → Commands
2. Tick: Progress.tick (systems run, including RenderSystem)
   - RenderSystem initializes RenderGraph
   - RenderSystem runs RenderPipeline (populates RenderGraph via collectors)
   - RenderSystem calls Backend.render(RenderGraph)
3. Drain: Signals → Commands → Events
4. Render: (already done in Tick via RenderSystem)
```

**Key Points**:
- RenderSystem is a standard ECS system that runs during the Tick phase
- RenderPipeline is independent from ECS Pipeline but called by RenderSystem
- RenderPipeline has phases/ordering like ECS Pipeline
- Backend receives RenderGraph and renders it (no backend knowledge in RenderPipeline)

### 2.3 Key Design Principle

**Backend Autonomy**: The rendering backend has complete control over:
- Rendering order (e.g., by layer, by shader, by distance)
- Shader usage (e.g., apply shaders to certain entities, skip for others)
- Rendering techniques (e.g., batching, instancing, culling)
- Output format (e.g., terminal, OpenGL, Vulkan, HTML5 Canvas)

The engine only provides the data; the backend decides how to use it.

## 3. Base Command Set

### 3.1 Purpose

Eon Engine provides a set of backend-agnostic rendering commands that all backends can use. These represent common rendering operations that are identical across all backends (e.g., drawing a sprite, setting a camera).

### 3.2 Base Commands

```ocaml
(* render_commands.mli *)

type command = [
  | `Draw_sprite of {
      texture_id : string;
      position : float * float;
      rotation : float option;
      scale : (float * float) option;
      layer : int;
    }
  | `Set_camera of {
      camera : Camera.t;
      target : (float * float) option;
    }
]
```

**Key Points**:
- Commands are backend-agnostic
- Represent common rendering operations
- All backends can use these commands
- Backends can extend with custom commands

### 3.3 Backend-Agnostic Collectors

Base collectors that add base commands to the render graph. Collectors use
polymorphic variant constraints to work with any command type that includes
the base commands:

```ocaml
(* render_collectors.mli *)

(** Collect sprites and add Draw_sprite commands to graph.
    
    The [> command] constraint means this works with any command type
    that includes at least the base commands (can have more).
*)
val collect_sprites : world -> [> command] Render_graph.t -> unit

(** Collect cameras and add Set_camera commands to graph. *)
val collect_cameras : world -> [> command] Render_graph.t -> unit
```

**Implementation Example**:
```ocaml
let collect_sprites world graph =
  Query.iter2 world "Position" "Sprite" (fun _entity pos sprite ->
    Render_graph.add graph (`Draw_sprite {
      texture_id = sprite.texture_id;
      position = (pos.x, pos.y);
      rotation = None;
      scale = None;
      layer = sprite.layer;
    }))

let collect_cameras world graph =
  Query.iter2 world "Position" "Camera" (fun _entity pos camera ->
    let target =
      match World.get_component world _entity "Camera_target" with
      | Some target ->
          (match World.get_component world target.target_entity_id "Position" with
           | Some target_pos -> Some (target_pos.x, target_pos.y)
           | None -> None)
      | None -> None
    in
    Render_graph.add graph (`Set_camera { camera; target }))
```

## 4. RenderGraph

### 4.1 Purpose

The `RenderGraph` is a collection of rendering commands. It contains no entity references - just pure rendering instructions that backends can process.

### 4.2 Design

The RenderGraph is a collection of rendering commands. It contains no entity references - just pure rendering instructions. The graph is generic over the command type, allowing backends to use base commands and extend with custom ones.

```ocaml
(* render_graph.mli *)

module type S = sig
  (** The type of the render graph, parameterized by command type. *)
  type 'command t

  (** Create an empty render graph. *)
  val create : unit -> 'command t

  (** Add a command to the graph. *)
  val add : 'command t -> 'command -> unit

  (** Clear all commands from the graph. *)
  val clear : 'command t -> unit

  (** Iterate over all commands in the graph.
      
      Preferred over [commands] to avoid unnecessary allocation.
  *)
  val iter : 'command t -> ('command -> unit) -> unit
end
```

**Key Points**:
- Graph is generic over command type
- Backends can use base commands or extend with custom ones
- No rendering logic in the graph
- Commands are processed by backends in their own way
- No [commands] function to avoid O(n) allocation on hot path

### 4.3 Backend Extension Example

Backends extend base commands using polymorphic variant inclusion:

```ocaml
(* Backend defines its command type *)
module OpenGL_backend = struct
  (* Include base commands from eon_engine *)
  type command = [
    | Render_commands.command  (* base commands *)
    | `Apply_shader of shader
    | `Set_blend_mode of blend_mode
    | `Draw_particles of particle_system
  ]

  (* Backend can use base collectors or define custom ones *)
  let collect_custom world graph =
    (* Add custom commands to graph *)
    Render_graph.add graph (`Draw_particles particle_system)
end
```

## 5. RenderPipeline

### 5.1 Purpose

The `RenderPipeline` manages phase ordering and executes collectors that populate the render graph with commands. It mirrors the ECS Pipeline architecture.

### 5.2 Design

```ocaml
(* render_pipeline.mli *)

module type S = sig
  (** The type of the render pipeline, parameterized by command type. *)
  type 'command t

  (** Phase type for ordering render collectors. *)
  type phase

  (** The world type (typically Eon_ecs.World.t). *)
  type world

  (** Collector function that adds commands to the render graph.
      
      Collectors take (world, graph) and populate the graph with commands.
      They don't return anything - they have side effects on the graph.
  *)
  type 'command collector = world -> 'command Render_graph.t -> unit

  (** Create an empty render pipeline for a given world. *)
  val create : world -> 'command t

  (** Add a phase if not already present. *)
  val add_phase : phase -> 'command t -> 'command t

  (** Declare [earlier] must run before [later]. *)
  val before : earlier:phase -> later:phase -> 'command t -> 'command t

  (** Declare [later] must run after [earlier]. *)
  val after : later:phase -> earlier:phase -> 'command t -> 'command t

  (** Attach a collector to a phase.
      
      @raise Invalid_argument if the phase is not registered. *)
  val add_collector : phase -> 'command collector -> 'command t -> 'command t

  (** Collect all renderable entities into the graph.
      
      Runs collectors in topological phase order.
  *)
  val collect : 'command t -> 'command Render_graph.t -> unit

  (** Return phases in resolved topological order. *)
  val phases : 'command t -> phase list
end

(** Functor to create a render pipeline. *)
module Make : S
```

**Key Points**:
- Pipeline is generic over command type
- Collectors take `(world, graph)` and populate the graph
- Collectors don't return anything (side effects on graph)
- Pipeline manages phase ordering and collector execution

**Implementation Note**: The pipeline is implemented as a regular module (not a functor) that works with any command type. The signature is polymorphic, and the implementation uses OCaml's module system to handle the generic command type.

### 5.3 Implementation Strategy

The render pipeline manages phases and collectors. **Collectors are backend-specific** because:
- Each backend defines its own command types (extending base commands)
- Collectors add backend-specific commands to the graph
- Backend knows which commands it can process

**Pipeline Implementation**:
```ocaml
module Make = struct
  type world = Eon_ecs.World.t
  type graph = Render_graph.t
  type phase = string  (* or a polymorphic variant *)
  type collector = world -> graph -> unit

  type t = {
    world : world;
    phases : phase list;
    before_edges : (phase * phase) list;
    collectors : (phase * collector) list;
  }

  let create world = 
    { world; phases = []; before_edges = []; collectors = [] }

  let add_phase phase t =
    if List.mem phase t.phases then t
    else { t with phases = phase :: t.phases }

  let before ~earlier ~later t =
    { t with before_edges = (earlier, later) :: t.before_edges }

  let after ~later ~earlier t =
    before ~earlier ~later t

  let add_collector phase collector t =
    { t with collectors = (phase, collector) :: t.collectors }

  let collect t graph =
    (* Resolve topological order of phases *)
    let ordered_phases = resolve_phases t.phases t.before_edges in
    
    (* Execute collectors in phase order *)
    List.iter (fun phase ->
      List.iter (fun (p, collector) ->
        if p = phase then collector t.world graph
      ) t.collectors
    ) ordered_phases

  let phases t = resolve_phases t.phases t.before_edges
end
```

**Collector Implementation Example** (provided by backend):
```ocaml
(* Backend defines collectors that know about its specific commands *)

module OpenGL_backend = struct
  (* Define backend-specific command type *)
  type command = [
    | `Draw_sprite of { texture_id : string; position : float * float; 
                        rotation : float option; scale : (float * float) option }
    | `Set_camera of { camera : Camera.t; target : (float * float) option }
    | `Apply_shader of shader  (* backend-specific extension *)
  ]

  (* Backend defines collectors that add its specific commands *)
  let collect_opaque world graph =
    Query.iter2 world "Position" "Sprite" (fun _entity pos sprite ->
      Render_graph.add graph (`Draw_sprite {
        texture_id = sprite.texture_id;
        position = (pos.x, pos.y);
        rotation = None;
        scale = None;
      }))

  let collect_cameras world graph =
    Query.iter2 world "Position" "Camera" (fun _entity pos camera ->
      let target =
        match World.get_component world _entity "Camera_target" with
        | Some target ->
            (match World.get_component world target.target_entity_id "Position" with
             | Some target_pos -> Some (target_pos.x, target_pos.y)
             | None -> None)
        | None -> None
      in
      Render_graph.add graph (`Set_camera { camera; target }))
end
```

**Key Points**:
- Collectors are backend-specific (not in eon_engine)
- Backend knows which commands it can process
- eon_engine doesn't need to know about backend-specific commands
- Clean decoupling: eon_engine provides infrastructure, backend provides content
- RenderPipeline only manages phase ordering and collector execution
- RenderPipeline is backend-agnostic (no knowledge of rendering techniques)

## 6. RenderingBackend

### 6.1 Purpose

The `RenderingBackend` is the only component that knows how to render. It receives a `RenderGraph` (already populated by the RenderPipeline) and produces a render result. The backend has complete autonomy over rendering decisions.

### 6.2 Design

```ocaml
(* rendering_result.mli *)

(** Error type using polymorphic variants for extensibility. *)
type error = [
  | `Texture_not_found of string
  | `Shader_compile_error of string * string  (* shader name, error message *)
  | `Invalid_render_graph of string
  | `Backend_error of string
  | `Custom_error of string * string  (* custom error with context *)
]

(** Result type that all backends must return. *)
type t = {
  errors : error list;
  metadata : (string * string) list;  (* key-value pairs for metadata *)
}

val empty : t
val with_error : t -> error -> t
val with_metadata : t -> string -> string -> t
val has_errors : t -> bool
val error_to_string : error -> string
```

```ocaml
(* rendering_backend.mli *)

module type S = sig
  (** The world type (typically Eon_ecs.World.t). *)
  type world

  (** The command type this backend processes. *)
  type command

  (** Render the populated render graph.
      
      This is called by the RenderSystem after the RenderPipeline
      has populated the graph with renderable entities.
      
      @param world The current ECS world
      @param dt Delta time since last frame
      @param graph The populated render graph
      @return Result containing errors and metadata about the rendering process
  *)
  val render : world -> dt:float -> graph:command Render_graph.t -> Rendering_result.t
end
```

**Key Points**:
- Backend receives an already-populated `RenderGraph`
- Backend does not create the pipeline or graph
- Backend has complete control over how to render the graph
- Backend can implement any rendering technique (shaders, batching, culling, etc.)
- **Error Handling**: All errors are returned in the result (no exceptions)
- **Metadata**: Simple key-value string pairs for rendering statistics
- **Polymorphic Variants**: Allow backends to extend error types without changing base interface

### 6.3 Backend Implementation Examples

#### Simple Terminal Backend

```ocaml
module Terminal_backend = struct
  type world = Eon_ecs.World.t
  
  (* Backend uses base commands *)
  type command = Render_commands.command

  let render world ~dt ~graph =
    (* Graph is already populated by RenderPipeline *)
    let result = Rendering_result.empty in
    
    try
      (* Process commands from the graph *)
      let sprite_count = ref 0 in
      let camera_count = ref 0 in
      
      Render_graph.iter graph (function
        | `Draw_sprite { texture_id; position; rotation; scale } ->
            (* Render sprite to ASCII art *)
            draw_ascii_sprite texture_id position rotation scale;
            incr sprite_count
        | `Set_camera { camera; target } ->
            (* Set camera viewport *)
            set_ascii_camera camera target;
            incr camera_count
      );
      
      (* Add metadata *)
      let result =
        result
        |> Rendering_result.with_metadata "backend" "terminal"
        |> Rendering_result.with_metadata "output_format" "ascii"
        |> Rendering_result.with_metadata "sprites_rendered" (string_of_int !sprite_count)
        |> Rendering_result.with_metadata "cameras_active" (string_of_int !camera_count)
      in
      
      result
    with
    | Texture_not_found path ->
        result
        |> Rendering_result.with_error (`Texture_not_found path)
    | exn ->
        result
        |> Rendering_result.with_error (`Backend_error (Printexc.to_string exn))
end
```

#### OpenGL Backend

```ocaml
module OpenGL_backend = struct
  type world = Eon_ecs.World.t
  
  (* Backend uses base commands *)
  type command = Render_commands.command

  let render world ~dt ~graph =
    (* Graph is already populated by RenderPipeline *)
    let result = Rendering_result.empty in
    
    try
      (* Process commands from the graph *)
      let sprite_count = ref 0 in
      let camera_count = ref 0 in
      
      Render_graph.iter graph (function
        | `Draw_sprite { texture_id; position; rotation; scale } ->
            (* Render sprite using OpenGL *)
            draw_sprite_gl texture_id position rotation scale;
            incr sprite_count
        | `Set_camera { camera; target } ->
            (* Set OpenGL camera/projection *)
            set_camera_gl camera target;
            incr camera_count
      );
      
      (* Add metadata about what was rendered *)
      let result =
        result
        |> Rendering_result.with_metadata "backend" "opengl"
        |> Rendering_result.with_metadata "sprites_rendered" (string_of_int !sprite_count)
        |> Rendering_result.with_metadata "cameras_active" (string_of_int !camera_count)
      in
      
      result
    with
    | Shader_compile_error (shader, msg) ->
        result
        |> Rendering_result.with_error (`Shader_compile_error (shader, msg))
    | exn ->
        result
        |> Rendering_result.with_error (`Backend_error (Printexc.to_string exn))
end
```

#### Custom Backend with Extended Commands

```ocaml
module Custom_backend = struct
  type world = Eon_ecs.World.t

  (* Backend defines its command type by extending base commands *)
  type command = [
    | Render_commands.command  (* base commands *)
    | `Draw_particles of particle_system
    | `Apply_shader of shader
  ]

  let render world ~dt ~graph =
    let result = Rendering_result.empty in
    
    try
      (* Process base commands and backend-specific ones *)
      Render_graph.iter graph (function
        | `Draw_sprite data -> (* handle sprite *)
        | `Set_camera data -> (* handle camera *)
        | `Draw_particles system -> (* handle particles *)
        | `Apply_shader shader -> (* apply shader *)
      );
      
      result
    with
    | exn ->
        result
        |> Rendering_result.with_error (`Backend_error (Printexc.to_string exn))
end
```

**Key Points**:
- All backends return `Rendering_result.t`
- Backends process commands using pattern matching (they choose their own strategy)
- Backends can extend the command set using polymorphic variant extension
- Errors are caught and returned in the result (no unhandled exceptions)
- Metadata provides rendering statistics and debugging information

## 7. RenderSystem

### 7.1 Purpose

The `RenderSystem` is a standard ECS system that:
1. Initializes the RenderGraph (empty container for rendering instructions)
2. Runs the RenderPipeline (collectors extract rendering data from entities)
3. Calls the backend's render method with the populated graph
4. Backend receives pure rendering data with no entity references

### 7.2 Design

```ocaml
(* render_system.mli *)

(** Functor that creates a render system for a specific backend.
    
    The functor ensures type safety by binding the backend's command type
    to the render pipeline. This prevents mismatched command types between
    the pipeline and backend.
    
    @param B The backend module (must implement Rendering_backend.S)
    @return Module with make function
*)
module Make (B : Rendering_backend.S) : sig
  (** Create a render system for the given backend.
      
      The system:
      1. Creates a new RenderGraph each frame
      2. Runs the RenderPipeline (backend-defined collectors add commands)
      3. Calls Backend.render with the populated graph
      4. Handles the result (logs errors, stores metadata, etc.)
      5. Returns unit (system has side effects)
      
      @param render_pipeline Pipeline configured with backend's collectors
      @return ECS system that performs rendering
  *)
  val make : render_pipeline:B.command Render_pipeline.t -> Eon_ecs.System.t
end
```

**Type-Safety Design**:
- Functor ensures pipeline's command type matches backend's command type
- Backend module specifies its command type via `type command`
- Pipeline is parameterized by that same command type
- Prevents wiring errors where pipeline and backend have mismatched types

**Key Architecture**:
- **eon_engine**: Provides infrastructure (pipeline, system, graph)
- **Backend**: Provides content (collectors, commands, rendering logic)
- **Clean separation**: eon_engine doesn't know about backend-specific commands
- **Backend autonomy**: Backend defines what commands it can process and how

**Result Handling Strategy**:
- RenderSystem collects the `Rendering_result.t` from the backend
- Errors are logged to console/stderr
- Metadata can be stored in ECS services or logged for debugging
- System returns `unit` (rendering is a side effect)

### 7.3 Integration with ECS Pipeline

The RenderSystem is added to the ECS Pipeline just like any other system:

```ocaml
(* Define render pipeline with phases and collectors *)
let render_pipeline =
  Render_pipeline.create world
  |> Render_pipeline.add_phase `Background
  |> Render_pipeline.add_phase `Opaque
  |> Render_pipeline.add_phase `Transparent
  |> Render_pipeline.add_phase `UI
  |> Render_pipeline.before ~earlier:`Background ~later:`Opaque
  |> Render_pipeline.before ~earlier:`Opaque ~later:`Transparent
  |> Render_pipeline.before ~earlier:`Transparent ~later:`UI
  |> Render_pipeline.add_collector `Background collect_background
  |> Render_pipeline.add_collector `Opaque collect_opaque
  |> Render_pipeline.add_collector `Transparent collect_transparent
  |> Render_pipeline.add_collector `UI collect_ui

(* Create render system with backend using functor *)
module Render_system = Render_system.Make(My_backend)
let render_system =
  Render_system.make ~render_pipeline

(* Add to ECS pipeline *)
let ecs_pipeline =
  Pipeline.create ()
  |> Pipeline.add_phase `Render
  |> Pipeline.add_system `Render render_system
```

### 7.4 System Execution Flow

When the RenderSystem runs (during ECS Pipeline Tick phase):

```
RenderSystem.update world dt:
1. graph = Render_graph.create ()
2. Render_pipeline.collect render_pipeline graph
   - Backend-defined collectors add commands to graph
   - Collectors know about backend-specific commands
   - Commands are polymorphic variants (extensible)
3. result = Backend.render world ~dt ~graph
   - Backend processes commands using pattern matching
   - Backend chooses its own processing strategy
4. Handle result:
   - Log any errors to console/stderr
   - Store metadata for debugging/monitoring
   - Graph goes out of scope (freed automatically)
5. Return unit (rendering is a side effect)
```

**Result Handling Example**:
```ocaml
let update world dt =
  let graph = Render_graph.create () in
  Render_pipeline.collect render_pipeline graph;
  
  let result = Backend.render world ~dt ~graph in
  
  (* Log errors *)
  List.iter (fun error ->
    prerr_endline ("Rendering error: " ^ Rendering_result.error_to_string error)
  ) result.errors;
  
  (* Store metadata in ECS service for debugging *)
  let render_stats = World.get_service world `RenderStats in
  render_stats.metadata <- result.metadata;
  
  (* Graph is freed after this frame; new graph created next frame *)
  (* No need to clear - we just let it go out of scope *)
```

**Note**: A fresh graph is created each frame. This avoids the need to clear and ensures clean state. For performance, a graph could be reused by storing it in an ECS service and clearing between frames.

**Decoupling Architecture**:
- **eon_engine**: Provides infrastructure (RenderPipeline, RenderSystem, RenderGraph)
- **Backend**: Provides content (collectors that know about its commands, rendering logic)
- **Clean separation**: eon_engine doesn't know about backend-specific commands
- **Backend autonomy**: Backend defines what commands it can process and how
```

### 7.5 Loop Integration

The RenderSystem works with the standard ECS Loop. The Loop's Tick phase runs systems including the RenderSystem:

```ocaml
module Loop = Eon_ecs.Loop.Make
  (Eon_ecs.Clock.Mtime)
  (Eon_ecs.Loop.Progress_adapter)
  (Eon_ecs.Loop.Noop_renderer)  (* RenderSystem handles rendering *)
  (Eon_ecs.Loop.Default_buses)
```

**Note**: The Loop uses `Noop_renderer` because rendering is handled by the RenderSystem during the Tick phase, not after the Drain phase.

**Result Processing**:
- RenderSystem handles backend result internally (logs errors, stores metadata)
- Loop doesn't receive or process the rendering result directly
- This keeps the Loop generic and avoids eon_ecs depending on eon_engine

## 8. Component Integration

### 8.1 Rendering Components

The rendering layer integrates with existing rendering components:

**Sprite Component** (`components/sprite.mli`):
```ocaml
type t = {
  texture_id : string;
  layer      : int;
  flip_x     : bool;
  flip_y     : bool;
}
```

**Animation Component** (`components/animation.mli`):
```ocaml
type t = {
  clip    : string;
  frame   : int;
  speed   : float;
  playing : bool;
}
```

**Camera Component** (`components/camera.mli`):
```ocaml
type t = {
  zoom       : float;
  viewport_w : float;
  viewport_h : float;
  near       : float;
  far        : float;
}
```

**Camera_target Component** (`components/camera_target.mli`):
```ocaml
type t = {
  priority : int;
  offset_x : float;
  offset_y : float;
  target_entity_id : Eon_ecs.Entity_id.t;  (* Entity to follow *)
}
```

### 8.2 Query Patterns

Collectors (attached to RenderPipeline phases) use the query system to find renderable entities and add rendering commands:

```ocaml
(* Sprites with positions *)
let collect_sprites world graph =
  Query.iter2 world "Position" "Sprite" (fun _entity pos sprite ->
    Render_graph.add graph (`Draw_sprite {
      texture_id = sprite.texture_id;
      position = (pos.x, pos.y);
      rotation = None;
      scale = None;
    }))

(* Animated sprites (rotation can be extracted from Animation component) *)
let collect_animated_sprites world graph =
  Query.iter3 world "Position" "Sprite" "Animation" 
    (fun _entity pos sprite anim ->
      let rotation = Some (anim.current_angle) in
      Render_graph.add graph (`Draw_sprite {
        texture_id = sprite.texture_id;
        position = (pos.x, pos.y);
        rotation;
        scale = None;
      }))

(* Cameras *)
let collect_cameras world graph =
  Query.iter1 world "Camera" (fun _entity camera ->
    Render_graph.add graph (`Set_camera { camera; target = None }))

(* Cameras with targets (extract target position, not entity reference) *)
let collect_cameras_with_targets world graph =
  Query.iter2 world "Position" "Camera" (fun _entity pos camera ->
    let target =
      match World.get_component world _entity "Camera_target" with
      | Some target ->
          (match World.get_component world target.target_entity_id "Position" with
           | Some target_pos -> Some (target_pos.x, target_pos.y)
           | None -> None)
      | None -> None
    in
    Render_graph.add graph (`Set_camera { camera; target }))
```

## 9. Design Goals

### 9.1 Backend Autonomy

- Backend decides rendering order (by layer, shader, distance, etc.)
- Backend decides shader usage and techniques
- Backend decides output format (terminal, OpenGL, Vulkan, etc.)
- Engine provides data; backend decides how to use it

### 9.2 Minimal Interface

- `Rendering_backend.S` has minimal methods
- Ideally just `render` function
- Backend can extend with additional methods as needed
- No forced rendering techniques

### 9.3 Pluggable Backends

- Backends selected at compile time via functor application
- Easy to swap backends for different platforms
- Users can create custom backends for specific needs

### 9.4 Decoupled Design

- Engine doesn't know about rendering details
- Rendering components are just data
- No rendering logic in engine core
- Backend is the only component with rendering knowledge

## 10. Future Extensions

### 10.1 Render Graph Extensions

- **Particles**: Particle system entities
- **Text**: Text rendering entities
- **UI Elements**: UI component entities
- **Post-processing**: Full-screen effects

### 10.2 Backend Features

- **Shader System**: Backend-managed shaders
- **Batching**: Automatic draw call batching
- **Culling**: Frustum or occlusion culling
- **Instancing**: Hardware instancing support

### 10.3 Pipeline Features

- **Layer System**: Automatic layer sorting
- **Render Groups**: Group entities by shader/technique
- **Render States**: State change optimization

## 11. Implementation Roadmap

**Note**: The implementation roadmap below provides a suggested sequence of phases. The exact details and API may be refined during implementation. This is a guideline, not a fixed specification.

### Phase 1: Base Commands and Collectors (ecs-021)
- [ ] Define `Render_commands.mli` with base command type
- [ ] Define base collectors (collect_sprites, collect_cameras, etc.)
- [ ] Implement base collectors that add base commands
- [ ] Unit tests for base commands and collectors

### Phase 2: Render Graph (ecs-022)
- [ ] Define `Render_graph.S` signature (generic over command type)
- [ ] Implement generic render graph structure
- [ ] Support for adding and iterating commands
- [ ] Unit tests for graph operations

### Phase 3: Render Pipeline (ecs-023)
- [ ] Define `Render_pipeline.S` signature (mirrors ECS Pipeline, generic over command type)
- [ ] Implement pipeline with phases and ordering (before/after)
- [ ] Support for collectors attached to phases
- [ ] Topological phase ordering
- [ ] Integration tests

### Phase 4: Render System (ecs-024)
- [ ] Define `Render_system.S` signature
- [ ] Implement system that:
  - Initializes RenderGraph each frame
  - Runs RenderPipeline to populate graph
  - Calls backend.render with graph
- [ ] Integration with ECS Pipeline

### Phase 5: Rendering Backend (ecs-025)
- [ ] Define `Rendering_backend.S` signature
- [ ] Implement simple reference backend
- [ ] Show how backends extend base commands
- [ ] Documentation for backend creation

### Phase 6: Backend Implementations (ecs-026)
- [ ] Implement terminal backend (ASCII art)
- [ ] Implement simple OpenGL backend
- [ ] Document backend creation patterns
- [ ] Example projects using different backends

## 12. Example Usage

**Important Note**: The examples below are illustrative guidelines, not final implementations. They represent ideas that will be iterated over in later phases. The exact API and implementation details may change as the rendering layer evolves.

### 12.1 Basic Usage

```ocaml
(* Create world and register components *)
let world = Eon_ecs.World.create ()
let () = Eon_engine.Components.Engine_components.register_all world

(* Create entities with rendering components *)
let player = Eon_ecs.World.create_entity world
let () = Eon_ecs.World.add_component world player ~name:"Position" (0.0, 0.0)
let () = Eon_ecs.World.add_component world player ~name:"Sprite" {
  texture_id = "player.png";
  layer = 10;
  flip_x = false;
  flip_y = false;
}

(* Backend extends base commands with custom commands *)
module My_backend = struct
  (* Include base commands from eon_engine *)
  type command = [
    | Render_commands.command  (* base commands *)
    | `Apply_shader of shader  (* backend-specific *)
  ]

  (* Backend can use base collectors or define custom ones *)
  (* Here we use base collectors directly *)

  (* Backend implements rendering *)
  let render world ~dt ~graph =
    let result = Rendering_result.empty in
    (* ... process commands (base + custom) ... *)
    result
end

(* Define render pipeline using base collectors *)
let render_pipeline =
  Render_pipeline.create world
  |> Render_pipeline.add_phase `Opaque
  |> Render_pipeline.add_phase `Cameras
  |> Render_pipeline.add_collector `Opaque Render_collectors.collect_sprites
  |> Render_pipeline.add_collector `Cameras Render_collectors.collect_cameras

(* Create render system with backend using functor *)
module Render_system = Render_system.Make(My_backend)
let render_system =
  Render_system.make ~render_pipeline

(* Add render system to ECS pipeline *)
let ecs_pipeline =
  Pipeline.create ()
  |> Pipeline.add_phase `Render
  |> Pipeline.add_system `Render render_system

(* Run loop with ECS pipeline *)
module Loop = Eon_ecs.Loop.Make
  (Eon_ecs.Clock.Mtime)
  (Eon_ecs.Loop.Progress_adapter)
  (Eon_ecs.Loop.Noop_renderer)  (* RenderSystem handles rendering *)
  (Eon_ecs.Loop.Default_buses)

let () =
  let progress = Eon_ecs.Progress.create_fixed 60.0 in
  Loop.run ~render_initial:true ~progress ~world
    ~should_continue:(fun _ _ -> true) ()
```

### 12.2 Custom Backend

```ocaml
module Custom_backend = struct
  type world = Eon_ecs.World.t
  
  (* Backend uses base commands *)
  type command = Render_commands.command

  (* Backend receives the populated RenderGraph with rendering commands *)
  let render world ~dt ~graph =
    let result = Rendering_result.empty in
    
    try
      (* Process commands from the graph *)
      let sprite_count = ref 0 in
      
      Render_graph.iter graph (function
        | `Draw_sprite { texture_id; position; rotation; scale } ->
            (* Your rendering code here *)
            draw_sprite ?rotation ?scale position texture_id;
            incr sprite_count
        | `Set_camera { camera; target } ->
            (* Set camera *)
            set_camera camera target
      );
      
      (* Add metadata *)
      let result =
        result
        |> Rendering_result.with_metadata "sprites_rendered"
            (string_of_int !sprite_count)
      in
      
      result
    with
    | exn ->
        result
        |> Rendering_result.with_error (`Backend_error (Printexc.to_string exn))
end
```

**Key Points**:
- RenderGraph contains rendering commands (polymorphic variants)
- No entity references in the graph
- Collectors add commands to the graph, not entity data
- Backend processes commands using pattern matching (chooses its own strategy)
- Backends can extend the command set using polymorphic variant extension

## 13. Conclusion

The rendering layer provides a clean separation of concerns:
- **Engine**: Provides infrastructure and base commands
- **RenderPipeline**: Phase-based collection pipeline (mirrors ECS Pipeline)
- **RenderSystem**: ECS system that runs the pipeline and forwards to backend
- **RenderingBackend**: Has complete control over how to render the graph

**Key Architecture**:
1. **RenderSystem runs during Tick phase** (after other systems have run)
2. RenderSystem creates a RenderGraph and runs RenderPipeline
3. Collectors query world state and add rendering commands
4. RenderSystem calls Backend.render with the populated graph
5. Backend processes commands using pattern matching

**Important**: RenderSystem should run **after** all other systems in the ECS Pipeline Tick phase to ensure the world state is fully updated before collecting rendering data. This maintains the frame contract where:
- Collect: Signals → Events → Commands
- Tick: All systems run (including RenderSystem at the end)
- Drain: Signals → Commands → Events
- Render: Already done during Tick

**Command-Based Design**:
- **Base commands**: Backend-agnostic commands in eon_engine (sprites, cameras, etc.)
- **Base collectors**: Functions that add base commands to the graph
- **Backend extension**: Backends extend base commands using polymorphic variant inclusion
- **Clean separation**: eon_engine provides infrastructure, backend provides content
- **Backend autonomy**: Backend defines custom commands and collectors

**Decoupling Architecture**:
- eon_engine provides: RenderGraph, RenderPipeline, RenderSystem, base commands, base collectors
- Backend provides: Extended command type, custom collectors (optional), rendering logic
- Collectors are functions that take (world, graph) and populate the graph (no return value)
- Backend can use base collectors or define custom ones

This design maintains the core Eon principles while providing maximum flexibility for rendering techniques. Backends can be simple or complex, and the engine remains unaware of rendering details.

**Note**: This design document provides architectural guidelines and implementation ideas. The exact API and implementation details will be refined during implementation phases.
