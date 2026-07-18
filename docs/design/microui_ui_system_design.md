# Eon Engine — UI System Design (microui)

## Status

**Exploratory.** Depends on the rendering layer (`rendering_layer_design.md`) being implemented first — `Render_stream`, `Render_stream_collector`, `Render_system`, and `Rendering_backend` must exist before any of this applies.

## 1. Overview

UI rendering is not a platform seam. It belongs in the Render_stream command
language — surfaced during the input system design (ecs-027) when the PLATFORM
boundary was being defined.

The design has four layers:

```
Game code  →  Microui API  (pure OCaml widget logic — no drawing, no C FFI)
                ↓ produces typed command list
             Render_stream UI commands  (`Ui_rect | `Ui_text | `Ui_clip | ...)
                ↓ emitted by UI collector into Render_stream (UI phase)
             Renderer backend  (Raylib: DrawRectangle / DrawText / BeginScissorMode
                                SDL:    SDL_RenderFillRect / TTF_RenderText / ...)
```

This approach has three key properties:

- **Pure OCaml microui is fully testable** — no backend, no window; just verify
  the command list it produces.
- **Any backend gets full UI by implementing ~6 primitive commands.**
- **Z-ordering is free** — UI commands go into `Render_stream.add_screen`; they
  are always drawn after all world-space commands, outside the camera transform.

## 2. UI Primitive Command Vocabulary

The Render_stream command language is extended with a fixed, minimal set of UI
drawing primitives, borrowing the core insight from microui: a tiny vocabulary
is sufficient to build any UI. `rect`, `text`, `texture`, and `clip` cover
everything (buttons, panels, scroll areas, inventory grids, health bars,
tooltips).

```ocaml
(* These extend the base command set in render_commands.mli *)
type command = [
  | (* ... existing base commands ... *)
  | `Ui_rect      of { rect: Rect.t; color: Color.t }
  | `Ui_text      of { pos: Vec2.t; text: string; font: Font_id.t; color: Color.t }
  | `Ui_texture   of { rect: Rect.t; texture: Texture_id.t; color: Color.t }
  | `Ui_ninepatch of { rect: Rect.t; texture: Texture_id.t; border: int }
  | `Ui_clip      of Rect.t
  | `Ui_end_clip
]
```

These are backend-agnostic. Every renderer backend implements them using its
native drawing calls:

```
Raylib backend:  `Ui_rect → DrawRectangle
                 `Ui_text → DrawText
                 `Ui_clip → BeginScissorMode / EndScissorMode

SDL backend:     `Ui_rect → SDL_RenderFillRect
                 `Ui_text → TTF_RenderText
                 `Ui_clip → SDL_RenderSetClipRect
```

The backend IS the UI renderer. Not a separate library, not a separate
dependency — just part of the renderer backend's command dispatch alongside
sprite and mesh commands. Porting to a new platform means implementing these
~6 commands and UI works for free.

## 3. Pure OCaml microui Collector

The widget layer is a pure OCaml microui implementation — the C microui
architecture translated directly. C microui already separates widget logic from
rendering via a command buffer; the OCaml version makes that command buffer
typed open variants for the Render_stream instead of a C union. No C FFI in the
widget layer.

The UI collector is a regular `World.ro` ECS system. It reads
`Raw_input_frame` from the world (mouse position, clicks — already there from
the input system), feeds it to the microui context, runs the widget logic, and
emits the resulting command list into the Render_stream:

```ocaml
(* UI collector — World.ro, parallel, registered in Render_stream_collector *)
let update world _dt =
  let ctx   = World.get_data world Ui_context in
  let input = World.get_data world `Raw_input_frame in
  Microui.set_mouse ctx input.mouse_screen input.mouse_buttons_down;
  Microui.begin_frame ctx;
  (* game UI code *)
  if Microui.button ctx "Attack" then Signals.emit world `Attack_pressed;
  Microui.end_frame ctx;
  (* flush into Render_stream *)
  Microui.iter_commands ctx (fun cmd ->
    Render_stream.add_screen graph (microui_to_render_cmd cmd))
```

Input flows naturally: the UI collector reads `Raw_input_frame` already in the
world data plane from the engine loop's input collection step. No special input
path is needed.

## 4. Trade-off with Immediate Mode Toolkits (raygui)

raygui is incompatible with the Render_stream primitive model. It is an immediate
mode widget library that calls raylib drawing functions directly —
`GuiButton(rect, "label")` draws immediately and returns whether it was clicked.
It does not emit a command buffer; it bypasses the Render_stream entirely.

Choosing the Render_stream primitive vocabulary means giving up raygui's widget
set at the game UI layer. For shipping game UI this is the right call — custom
health bars, skill icons, and inventory panels all reduce naturally to
`rect + text + texture + clip`.

For rapid prototyping and debug tooling where raygui shines, an escape hatch is
available:

```ocaml
`Platform_native of (unit -> unit)   (* raw callback — bypasses Render_stream *)
```

Debug UI and dev tools call raygui (or any platform-native toolkit) directly
through this callback. Game UI uses the proper primitive vocabulary. The escape
hatch is explicitly non-portable and must never appear in shipping game code.

## 5. Implementation Roadmap

This work is deferred until after the core rendering layer is complete. The
dependency order is:

1. `rendering_layer_design.md` (Render_stream, Render_stream_collector, Render_system, Rendering_backend) — prerequisite
2. Define UI primitive commands as an extension of the base command set
3. Implement pure OCaml microui context and widget logic
4. Implement UI collector (reads `Raw_input_frame`, emits UI commands)
5. Implement UI primitive dispatch in at least one backend (raylib)
6. Integration tests — verify command output without a backend

No task ID assigned yet — scope after the rendering layer task is closed.
