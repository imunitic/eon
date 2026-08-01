#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGES="$ROOT/docs/design/images"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$IMAGES"

# ─── Package registry ─────────────────────────────────────────────────────────
# Sections 3-6 (test coverage, LOC, interface ratio, code statistics) are
# fully generic over this list — add a package here and they pick it up
# automatically. Sections 1-2 (the dependency and functor graphs) are
# hand-curated illustrations, not mechanically derived, and are intentionally
# left hardcoded — see the note at the top of each digraph.
PACKAGES=(eon_ecs eon_engine eon_edn)
PACKAGE_BG=("#e3f2fd" "#e8f5e9" "#f3e5f5")      # cluster background per package
PACKAGE_BORDER=("#1565c0" "#2e7d32" "#7b1fa2")  # cluster border / bar color per package
PACKAGE_CMAP=(Blues Greens Purples)             # matplotlib colormap per package

# Coverage overrides: "package:module:test_file_basename" — only needed when a
# module's tests don't follow the default test_<module>.ml convention (e.g.
# several modules sharing one composite test file).
TEST_OVERRIDES="
eon_ecs:single_bus:bus
eon_ecs:double_bus:bus
eon_engine:color:render_modules
eon_engine:component:api_structure
eon_engine:component_descriptor:api_structure
eon_engine:single_bus:api_structure
eon_engine:double_bus:api_structure
eon_engine:buses:api_structure
eon_engine:system:api_structure
eon_engine:progress:api_structure
eon_engine:loop:api_structure
eon_engine:loop_buses:api_structure
eon_engine:sparse_set_backend:api_structure
eon_engine:asset_lookup:api_structure
eon_engine:resource:resource_service
eon_engine:service:resource_service
eon_engine:namespace:resource_service
eon_engine:audio_command:audio
eon_engine:audio_command_buffer:audio
eon_engine:raw_input_frame:input
eon_engine:input_backend:input
eon_engine:animation:components
eon_engine:camera:components
eon_engine:children:components
eon_engine:collider:components
eon_engine:local_transform:components
eon_engine:parent:components
eon_engine:sprite:components
eon_engine:tag:components
eon_engine:velocity:components
eon_engine:world_transform:components
eon_engine:render_commands:render_modules
eon_engine:render_stream_collector:render_modules
eon_engine:render_system:render_modules
eon_engine:rendering_backend:render_modules
eon_engine:rendering_result:render_modules
eon_engine:prefab_edn:prefab
eon_engine:prefab_edn_defaults:prefab
eon_engine:edn_source:prefab
eon_engine:edn_document:prop_prefab
eon_edn:edn_effects:edn_parser
"

# Test-file basename for a package:module pair (default: the module's own name)
test_base_for() {
  local pkg="$1" mod="$2" hit
  hit=$(echo "$TEST_OVERRIDES" | grep "^${pkg}:${mod}:" || true)
  if [ -n "$hit" ]; then echo "${hit##*:}"; else echo "$mod"; fi
}

# ─── 1a. eon_ecs internal dependency graph ────────────────────────────────────

echo "→ dep_eon_ecs.png"
cat > "$TMP/dep_ecs.dot" << 'EOF'
digraph eon_ecs_dependencies {
  rankdir=RL
  node [fontname="Helvetica" fontsize=11 style=filled]
  edge [fontname="Helvetica" fontsize=9]

  subgraph cluster_ecs {
    label="eon_ecs"
    style=filled
    fillcolor="#e3f2fd"
    color="#1565c0"
    fontcolor="#1565c0"
    fontsize=13
    fontname="Helvetica-Bold"

    node [fillcolor="#90caf9" color="#1976d2"]

    ecs_loop         [label="Loop"]
    ecs_progress     [label="Progress"]
    ecs_pipeline     [label="Pipeline"]
    ecs_system       [label="System"]
    ecs_world        [label="World"]
    ecs_query        [label="Query"]
    ecs_entity_mgr   [label="Entity_manager"]
    ecs_entity_id    [label="Entity_id"]
    ecs_component    [label="Component"]
    ecs_comp_reg     [label="Component_registry"]
    ecs_sparse_set   [label="Sparse_set"]
    ecs_resource     [label="Resource_store"]
    ecs_buses        [label="Buses"]
    ecs_single_bus   [label="Single_bus"]
    ecs_double_bus   [label="Double_bus"]
    ecs_loop_buses   [label="Loop_default_buses"]
    ecs_clock        [label="Clock"]
    ecs_dep_graph    [label="Dependency_graph"]

    ecs_loop       -> ecs_progress
    ecs_loop       -> ecs_clock
    ecs_loop       -> ecs_loop_buses
    ecs_progress   -> ecs_pipeline
    ecs_pipeline   -> ecs_system
    ecs_pipeline   -> ecs_dep_graph
    ecs_system     -> ecs_world
    ecs_query      -> ecs_world
    ecs_query      -> ecs_sparse_set
    ecs_world      -> ecs_entity_mgr
    ecs_world      -> ecs_comp_reg
    ecs_world      -> ecs_resource
    ecs_world      -> ecs_sparse_set
    ecs_entity_mgr -> ecs_entity_id
    ecs_comp_reg   -> ecs_component
    ecs_component  -> ecs_entity_id
    ecs_buses      -> ecs_single_bus
    ecs_buses      -> ecs_double_bus
    ecs_loop_buses -> ecs_single_bus
    ecs_loop_buses -> ecs_double_bus
  }

  mtime [label="mtime\n(external)" shape=box fillcolor="#fff3e0" color="#e65100" fontcolor="#bf360c"]
  ecs_clock -> mtime [color="#e65100"]
}
EOF

# ─── 1b. eon_engine internal dependency graph ─────────────────────────────────

echo "→ dep_eon_engine.png"
cat > "$TMP/dep_engine.dot" << 'EOF'
digraph eon_engine_dependencies {
  rankdir=RL
  node [fontname="Helvetica" fontsize=11 style=filled]
  edge [fontname="Helvetica" fontsize=9]

  subgraph cluster_engine {
    label="eon_engine"
    style=filled
    fillcolor="#e8f5e9"
    color="#2e7d32"
    fontcolor="#2e7d32"
    fontsize=13
    fontname="Helvetica-Bold"

    node [fillcolor="#a5d6a7" color="#388e3c"]

    // Core pipeline
    eng_loop          [label="Loop"]
    eng_progress      [label="Progress"]
    eng_pipeline      [label="Pipeline"]
    eng_system        [label="System"]
    eng_executor      [label="Executor"]
    eng_world         [label="World"]
    eng_query         [label="Query"]
    eng_view          [label="View"]
    eng_components    [label="Components"]
    eng_component     [label="Component"]
    eng_comp_desc     [label="Component_descriptor"]
    eng_buses         [label="Buses"]
    eng_single_bus    [label="Single_bus"]
    eng_double_bus    [label="Double_bus"]
    eng_loop_buses    [label="Loop_buses"]
    eng_platform      [label="Platform"]
    eng_asset_lookup  [label="Asset_lookup"]
    eng_sparse_set_be [label="Sparse_set_backend"]
    eng_query_backend [label="Query_backend"]
    eng_math          [label="Math"]

    // Resource / Service / Namespace
    eng_resource      [label="Resource"]
    eng_service       [label="Service"]
    eng_namespace     [label="Namespace"]

    // Audio seam
    eng_audio_cmd     [label="Audio_command"]
    eng_audio_buf     [label="Audio_command_buffer"]
    eng_audio_be      [label="Audio_backend"]

    // Input seam
    eng_key           [label="Key"]
    eng_mouse_btn     [label="Mouse_button"]
    eng_gamepad_btn   [label="Gamepad_button"]
    eng_raw_input     [label="Raw_input_frame"]
    eng_input_be      [label="Input_backend"]

    // Time
    eng_time          [label="Time"]

    // Render
    eng_render_cmds   [label="Render_commands"]
    eng_render_stream [label="Render_stream"]
    eng_render_coll   [label="Render_stream_collector"]
    eng_render_sys    [label="Render_system"]
    eng_rendering_be  [label="Rendering_backend"]
    eng_rendering_res [label="Rendering_result"]

    // Transform & Lifecycle
    eng_hierarchy     [label="Transform_hierarchy"]
    eng_transform_sys [label="Transform_system"]
    eng_lifecycle_sys [label="Lifecycle_system"]

    // Prefab
    eng_prefab            [label="Prefab"]
    eng_prefab_edn        [label="Prefab_edn"]
    eng_prefab_edn_def    [label="Prefab_edn_defaults"]
    eng_edn_source        [label="Edn_source"]
    eng_edn_document      [label="Edn_document"]

    eng_loop       -> eng_progress
    eng_loop       -> eng_loop_buses
    eng_loop       -> eng_platform
    eng_loop       -> eng_raw_input
    eng_loop       -> eng_audio_buf
    eng_loop       -> eng_render_stream
    eng_platform   -> eng_input_be
    eng_platform   -> eng_rendering_be
    eng_platform   -> eng_audio_be
    eng_progress   -> eng_pipeline
    eng_pipeline   -> eng_system
    eng_pipeline   -> eng_executor
    eng_system     -> eng_world
    eng_query      -> eng_world
    eng_query      -> eng_query_backend
    eng_view       -> eng_world
    eng_view       -> eng_comp_desc
    eng_components -> eng_component
    eng_components -> eng_world
    eng_component  -> eng_comp_desc
    eng_buses      -> eng_single_bus
    eng_buses      -> eng_double_bus
    eng_loop_buses -> eng_single_bus
    eng_loop_buses -> eng_double_bus
    eng_world      -> eng_comp_desc
    eng_world      -> eng_sparse_set_be

    eng_resource   -> eng_world
    eng_service    -> eng_world
    eng_namespace  -> eng_world

    eng_audio_buf  -> eng_world
    eng_audio_buf  -> eng_audio_cmd
    eng_audio_be   -> eng_audio_cmd

    eng_raw_input  -> eng_world
    eng_raw_input  -> eng_key
    eng_raw_input  -> eng_mouse_btn
    eng_raw_input  -> eng_gamepad_btn
    eng_input_be   -> eng_raw_input

    eng_time          -> eng_world
    eng_progress      -> eng_time

    eng_render_stream -> eng_render_cmds
    eng_render_stream -> eng_world
    eng_render_coll   -> eng_render_stream
    eng_render_coll   -> eng_world
    eng_render_sys    -> eng_render_stream
    eng_render_sys    -> eng_render_coll
    eng_rendering_be  -> eng_render_stream
    eng_rendering_be  -> eng_rendering_res

    eng_hierarchy     -> eng_world
    eng_hierarchy     -> eng_components
    eng_transform_sys -> eng_system
    eng_transform_sys -> eng_world
    eng_transform_sys -> eng_query
    eng_transform_sys -> eng_view
    eng_transform_sys -> eng_components
    eng_transform_sys -> eng_hierarchy
    eng_lifecycle_sys -> eng_system
    eng_lifecycle_sys -> eng_world
    eng_lifecycle_sys -> eng_hierarchy

    eng_prefab         -> eng_world
    eng_prefab         -> eng_hierarchy
    eng_prefab_edn      -> eng_prefab
    eng_prefab_edn      -> eng_edn_source
    eng_prefab_edn      -> eng_edn_document
    eng_prefab_edn_def  -> eng_prefab_edn
    eng_prefab_edn_def  -> eng_components
    eng_edn_document    -> eng_prefab
  }
}
EOF

# ─── 1c. eon_edn internal dependency graph ────────────────────────────────────

echo "→ dep_eon_edn.png"
cat > "$TMP/dep_edn.dot" << 'EOF'
digraph eon_edn_dependencies {
  rankdir=RL
  node [fontname="Helvetica" fontsize=11 style=filled]
  edge [fontname="Helvetica" fontsize=9]

  subgraph cluster_edn {
    label="eon_edn"
    style=filled
    fillcolor="#f3e5f5"
    color="#7b1fa2"
    fontcolor="#7b1fa2"
    fontsize=13
    fontname="Helvetica-Bold"

    node [fillcolor="#ce93d8" color="#8e24aa"]

    edn_effects    [label="Edn_effects"]
    edn_parser     [label="Edn_parser"]
    edn_middleware [label="Edn_middleware"]

    edn_parser     -> edn_effects
    edn_middleware -> edn_effects
    edn_middleware -> edn_parser
  }
}
EOF

# ─── 1d. Cross-package dependency graph ───────────────────────────────────────

echo "→ dep_cross_package.png"
cat > "$TMP/dep_cross.dot" << 'EOF'
digraph cross_package_dependencies {
  rankdir=LR
  node [fontname="Helvetica" fontsize=11 style=filled]
  edge [fontname="Helvetica" fontsize=9 color="#cc5500" penwidth=2.5]

  subgraph cluster_engine {
    label="eon_engine"
    style=filled
    fillcolor="#e8f5e9"
    color="#2e7d32"
    fontcolor="#2e7d32"
    fontsize=13
    fontname="Helvetica-Bold"
    node [fillcolor="#a5d6a7" color="#388e3c"]

    eng_loop     [label="Loop"]
    eng_progress [label="Progress"]
    eng_pipeline [label="Pipeline"]
    eng_system   [label="System"]
    eng_query    [label="Query"]
    eng_world    [label="World"]

    eng_edn_document       [label="Edn_document"]
    eng_edn_source         [label="Edn_source"]
    eng_prefab_edn_def     [label="Prefab_edn_defaults"]
  }

  subgraph cluster_ecs {
    label="eon_ecs"
    style=filled
    fillcolor="#e3f2fd"
    color="#1565c0"
    fontcolor="#1565c0"
    fontsize=13
    fontname="Helvetica-Bold"
    node [fillcolor="#90caf9" color="#1976d2"]

    ecs_loop     [label="Loop"]
    ecs_progress [label="Progress"]
    ecs_pipeline [label="Pipeline"]
    ecs_system   [label="System"]
    ecs_query    [label="Query"]
    ecs_world    [label="World"]
  }

  subgraph cluster_edn {
    label="eon_edn"
    style=filled
    fillcolor="#f3e5f5"
    color="#7b1fa2"
    fontcolor="#7b1fa2"
    fontsize=13
    fontname="Helvetica-Bold"
    node [fillcolor="#ce93d8" color="#8e24aa"]

    edn_effects    [label="Edn_effects"]
    edn_parser     [label="Edn_parser"]
    edn_middleware [label="Edn_middleware"]
  }

  eng_loop     -> ecs_loop
  eng_progress -> ecs_progress
  eng_pipeline -> ecs_pipeline
  eng_system   -> ecs_system
  eng_query    -> ecs_query
  eng_world    -> ecs_world

  edge [color="#7b1fa2" penwidth=2.5]
  eng_edn_document   -> edn_effects
  eng_edn_source     -> edn_effects
  eng_edn_source     -> edn_parser
  eng_edn_source     -> edn_middleware
  eng_prefab_edn_def -> edn_effects
}
EOF

# The four heredocs above are the hand-curated fallback -- always written
# first, so a failure below leaves them exactly as they were. If
# gen_dependency_graphs.py succeeds, it overwrites dep_ecs.dot/dep_engine.dot/
# dep_edn.dot/dep_cross.dot in place with mechanically-derived content from
# real tree-sitter tags data (see designs/ecs -- Mechanically-derived
# dependency graphs.md in the second-brain vault). Optional, fail-soft:
# missing synapse-tags.sh/tree-sitter, or any other failure, just means the
# hand-curated versions above are what gets rendered, same as before this
# existed.
if python3 "$ROOT/scripts/gen_dependency_graphs.py" "$TMP" "$ROOT" 2>/dev/null; then
  echo "  (dependency graphs: mechanically generated from tree-sitter tags)"
else
  echo "  (dependency graphs: tree-sitter unavailable, using hand-curated fallback)"
fi

dot -Tpng -o "$IMAGES/dep_eon_ecs.png" "$TMP/dep_ecs.dot"
dot -Tpng -o "$IMAGES/dep_eon_engine.png" "$TMP/dep_engine.dot"
dot -Tpng -o "$IMAGES/dep_eon_edn.png" "$TMP/dep_edn.dot"
dot -Tpng -o "$IMAGES/dep_cross_package.png" "$TMP/dep_cross.dot"

# ─── 2. Functor instantiation graph ──────────────────────────────────────────

echo "→ functor_instantiation_graph.png"
cat > "$TMP/functors.dot" << 'EOF'
digraph functor_instantiation {
  rankdir=TB
  splines=polyline
  node [fontname="Helvetica" fontsize=11 style=filled margin="0.2,0.1"]
  edge [fontname="Helvetica" fontsize=9]

  // ── eon_ecs ───────────────────────────────────────────────────────────────
  subgraph cluster_ecs {
    label="eon_ecs"
    style=filled fillcolor="#e3f2fd" color="#1565c0"
    fontcolor="#1565c0" fontsize=13 fontname="Helvetica-Bold"

    // inputs
    node [shape=ellipse fillcolor="#ddeeff" color="#5588cc"]
    ecs_signals   [label="Signals\n(Single_bus)"]
    ecs_events    [label="Events\n(Double_bus)"]
    ecs_commands  [label="Commands\n(Single_bus)"]
    ecs_bdefs     [label="Buses.Default"]
    ecs_clock     [label="Clock.Mtime"]
    ecs_lbuses    [label="Loop_default_buses"]

    // functors
    node [shape=box fillcolor="#bbddff" color="#1565c0"]
    ecs_sys_make      [label="System.Make"]
    ecs_pip_make      [label="Pipeline.Make"]
    ecs_prog_make     [label="Progress.Make"]
    ecs_loop_make     [label="Loop.Make"]

    // results
    node [shape=box fillcolor="#3366cc" fontcolor=white color="#1a3a88" penwidth=2]
    ecs_sys_def   [label="System.Default"]
    ecs_pip_def   [label="Pipeline.Default"]
    ecs_prog_def  [label="Progress.Default"]
    ecs_prog_adp  [label="Progress_adapter"]
    ecs_loop_def  [label="Loop.Default"]

    ecs_signals  -> ecs_sys_make
    ecs_events   -> ecs_sys_make
    ecs_commands -> ecs_sys_make
    ecs_sys_make -> ecs_sys_def

    ecs_sys_def -> ecs_pip_make
    ecs_bdefs   -> ecs_pip_make
    ecs_pip_make -> ecs_pip_def

    ecs_pip_def   -> ecs_prog_make
    ecs_prog_make -> ecs_prog_def

    ecs_prog_def  -> ecs_prog_adp
    ecs_clock     -> ecs_loop_make
    ecs_prog_adp  -> ecs_loop_make
    ecs_lbuses    -> ecs_loop_make
    ecs_loop_make -> ecs_loop_def
  }

  // ── eon_engine ────────────────────────────────────────────────────────────
  subgraph cluster_engine {
    label="eon_engine"
    style=filled fillcolor="#e8f5e9" color="#2e7d32"
    fontcolor="#2e7d32" fontsize=13 fontname="Helvetica-Bold"

    // inputs
    node [shape=ellipse fillcolor="#ddf5dd" color="#4caf50"]
    eng_ecs_sys   [label="Eon_ecs.System\n(Signals+Events+Commands)"]
    eng_exec      [label="Executor.Sequential"]
    eng_bdefs     [label="Buses.Default"]
    eng_res_t     [label="(type t, key : Obj.t)"]
    eng_svc_t     [label="(type t, key : Obj.t)"]
    eng_render_b  [label="Rendering_backend B"]
    eng_time_s    [label="Time\n(Time.S)"]
    eng_prefab_source [label="Source\n(functor arg)"]
    eng_prefab_doc    [label="Document_shape\n(functor arg)"]
    eng_prefab_root   [label="Root\n(path)"]

    // functors
    node [shape=box fillcolor="#b9f6ca" color="#2e7d32"]
    eng_sys_make      [label="System.Make"]
    eng_sys_mf_make   [label="System.Make_factory"]
    eng_pip_make      [label="Pipeline.Make"]
    eng_res_make      [label="Resource.Make"]
    eng_svc_make      [label="Service.Make"]
    eng_render_make   [label="Render_system.Make_with_system"]
    eng_prog_wt_make  [label="Progress.Make_with_time"]
    eng_prefab_make     [label="Prefab.Make"]
    eng_prefab_edn_make [label="Prefab_edn.Make"]

    // results
    node [shape=box fillcolor="#2e7d32" fontcolor=white color="#1b5e20" penwidth=2]
    eng_sys_def   [label="System.Default"]
    eng_def_fac   [label="Default_factory"]
    eng_pip_def   [label="Pipeline.Default"]
    eng_res_mod   [label="(Resource.S module)"]
    eng_svc_mod   [label="(Service.S module)"]
    eng_render_sys [label="(Render system)"]
    eng_prog_wt   [label="(Progress + Time)"]
    eng_prefab_result     [label="(load / register_component)"]
    eng_prefab_edn_result [label="Prefab_edn (instance)"]

    eng_ecs_sys  -> eng_sys_make
    eng_sys_make -> eng_sys_def

    eng_sys_def     -> eng_sys_mf_make
    eng_sys_mf_make -> eng_def_fac

    eng_sys_def -> eng_pip_make
    eng_exec    -> eng_pip_make
    eng_bdefs   -> eng_pip_make
    eng_pip_make -> eng_pip_def

    eng_res_t    -> eng_res_make
    eng_res_make -> eng_res_mod

    eng_svc_t    -> eng_svc_make
    eng_svc_make -> eng_svc_mod

    eng_render_b  -> eng_render_make
    eng_render_make -> eng_render_sys

    eng_pip_def    -> eng_prog_wt_make
    eng_time_s     -> eng_prog_wt_make
    eng_prog_wt_make -> eng_prog_wt

    eng_prefab_source -> eng_prefab_make
    eng_prefab_doc    -> eng_prefab_make
    eng_prefab_make   -> eng_prefab_result

    eng_prefab_root     -> eng_prefab_edn_make
    eng_prefab_make     -> eng_prefab_edn_make
    eng_prefab_edn_make -> eng_prefab_edn_result
  }

  // eon_edn feeds Prefab_edn.Make (parser + reader used internally by Edn_source/Edn_document)
  eon_edn [label="eon_edn\n(Edn_parser / Edn_middleware)" shape=box fillcolor="#f3e5f5" color="#7b1fa2" fontcolor="#7b1fa2"]
  eon_edn -> eng_prefab_edn_make [color="#7b1fa2" penwidth=2.0 style=dashed]

  // cross-package: eon_ecs defaults feed into eon_engine
  edge [color="#cc5500" penwidth=2.0 style=dashed]
  ecs_sys_def -> eng_ecs_sys
  ecs_pip_def -> eng_pip_def
}
EOF
dot -Tpng -o "$IMAGES/functor_instantiation_graph.png" "$TMP/functors.dot"

# ─── 3. Test coverage map ────────────────────────────────────────────────────

echo "→ test_coverage_map.png"

{
  echo 'digraph test_coverage {'
  echo '  rankdir=TB'
  echo '  node [fontname="Helvetica" fontsize=11 style=filled shape=box margin="0.15,0.08"]'
  echo '  edge [style=invis]'
  echo ''
  echo '  // legend'
  echo '  legend [shape=none label=<<table border="0" cellpadding="4">'
  echo '    <tr><td bgcolor="#a5d6a7">  </td><td align="left">has tests</td></tr>'
  echo '    <tr><td bgcolor="#ef9a9a">  </td><td align="left">no tests</td></tr>'
  echo '  </table>>]'
  echo ''

  prev_anchor=""
  for i in "${!PACKAGES[@]}"; do
    pkg="${PACKAGES[$i]}"
    bg="${PACKAGE_BG[$i]}"
    border="${PACKAGE_BORDER[$i]}"

    echo "  subgraph cluster_${pkg} {"
    echo "    label=\"${pkg}\" style=filled fillcolor=\"${bg}\" color=\"${border}\""
    echo "    fontcolor=\"${border}\" fontsize=13 fontname=\"Helvetica-Bold\""

    first_node=""
    while read -r mli; do
      [ -z "$mli" ] && continue
      mod=$(basename "$mli" .mli)
      testbase=$(test_base_for "$pkg" "$mod")
      test_file="$ROOT/$pkg/test/test_${testbase}.ml"
      prop_file="$ROOT/$pkg/test/test_prop_${testbase}.ml"
      if [ -f "$test_file" ] || [ -f "$prop_file" ]; then
        color="#a5d6a7"; nb="#388e3c"
      else
        color="#ef9a9a"; nb="#c62828"
      fi
      node_id="${pkg}_${mod}"
      [ -z "$first_node" ] && first_node="$node_id"
      echo "    ${node_id} [label=\"${mod}\" fillcolor=\"${color}\" color=\"${nb}\"]"
    done < <(find "$ROOT/$pkg" -name "*.mli" ! -path "*/test/*" ! -path "*/bench/*" ! -name "${pkg}.mli" | sort)

    echo '  }'
    echo ''

    if [ -n "$prev_anchor" ] && [ -n "$first_node" ]; then
      echo "  ${prev_anchor} -> ${first_node} [style=invis constraint=true]"
    fi
    [ -n "$first_node" ] && prev_anchor="$first_node"
  done

  echo '}'
} > "$TMP/coverage.dot"

dot -Tpng -o "$IMAGES/test_coverage_map.png" "$TMP/coverage.dot"

# ─── 4. LOC per module (pie charts) ──────────────────────────────────────────

echo "→ loc_per_module.png"

# Collect LOC for source .ml files per package, skipping test/, bench/, composition roots
for i in "${!PACKAGES[@]}"; do
  pkg="${PACKAGES[$i]}"
  find "$ROOT/$pkg" -name "*.ml" \
    ! -path "*/test/*" ! -path "*/bench/*" \
    ! -name "${pkg}.ml" | while read -r f; do
    base=$(basename "$f" .ml)
    lines=$(wc -l < "$f")
    echo "$base $lines"
  done | sort -k2,2rn > "$TMP/loc_${i}.dat"
done

TMP="$TMP" IMAGES="$IMAGES" \
PKG_LIST="${PACKAGES[*]}" CMAP_LIST="${PACKAGE_CMAP[*]}" \
python3 << 'PYEOF'
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

tmp = os.environ["TMP"]
images = os.environ["IMAGES"]
packages = os.environ["PKG_LIST"].split()
cmaps = os.environ["CMAP_LIST"].split()

def read_dat(path):
    rows = []
    with open(path) as f:
        for line in f:
            parts = line.split()
            if len(parts) >= 2:
                rows.append((parts[0], int(parts[1])))
    return rows

datasets = [read_dat(f"{tmp}/loc_{i}.dat") for i in range(len(packages))]

n = len(packages)
fig, axes = plt.subplots(1, n, figsize=(19 * n / 3, 10))
if n == 1:
    axes = [axes]
fig.suptitle("Source lines per module (implementation only)", fontsize=14, fontweight="bold", y=0.98)

LEGEND_CAP = 18

def pie(ax, data, cmap_name, title):
    if not data:
        ax.set_visible(False)
        return
    labels, values = zip(*data)
    colors = plt.get_cmap(cmap_name)(
        [0.4 + 0.5 * i / max(len(data) - 1, 1) for i in range(len(data))]
    )
    wedges, _, autotexts = ax.pie(
        values, labels=None, colors=colors,
        autopct=lambda p: f"{p:.0f}%" if p >= 4 else "",
        pctdistance=0.75, startangle=140,
        wedgeprops=dict(linewidth=0.5, edgecolor="white")
    )
    for t in autotexts:
        t.set_fontsize(8)
    ax.set_title(title, fontsize=12, fontweight="bold", pad=14)

    # cap the legend so a large module count can't overrun the figure —
    # data is pre-sorted largest-first, so the tail is the smallest modules
    if len(labels) > LEGEND_CAP:
        shown_wedges = list(wedges[:LEGEND_CAP])
        entries = [f"{n}  ({v})" for n, v in zip(labels[:LEGEND_CAP], values[:LEGEND_CAP])]
        rest_n = len(labels) - LEGEND_CAP
        rest_sum = sum(values[LEGEND_CAP:])
        entries.append(f"+ {rest_n} more  ({rest_sum})")
        shown_wedges.append(wedges[-1])
    else:
        shown_wedges = list(wedges)
        entries = [f"{n}  ({v})" for n, v in zip(labels, values)]

    ax.legend(shown_wedges, entries,
              loc="upper center", bbox_to_anchor=(0.5, -0.02),
              fontsize=7.5, frameon=False, ncol=2)

for ax, pkg, data, cmap in zip(axes, packages, datasets, cmaps):
    pie(ax, data, cmap, pkg)

plt.tight_layout(rect=[0, 0.12, 1, 0.94])
plt.savefig(f"{images}/loc_per_module.png", dpi=130, bbox_inches="tight")
plt.close()
PYEOF

# ─── 5. Interface / implementation ratio ─────────────────────────────────────

echo "→ interface_ratio.png"

for i in "${!PACKAGES[@]}"; do
  pkg="${PACKAGES[$i]}"
  find "$ROOT/$pkg" -name "*.ml" \
    ! -path "*/test/*" ! -path "*/bench/*" \
    ! -name "${pkg}.ml" | while read -r ml; do
    base=$(basename "$ml" .ml)
    dir=$(dirname "$ml")
    mli="$dir/${base}.mli"
    [ -f "$mli" ] || continue
    impl=$(wc -l < "$ml")
    iface=$(wc -l < "$mli")
    [ "$impl" -gt 0 ] || continue
    ratio=$(awk "BEGIN {printf \"%.2f\", $iface / $impl}")
    echo "$base $ratio"
  done | sort -k2,2rn > "$TMP/ratio_${i}.dat"
done

TMP="$TMP" IMAGES="$IMAGES" \
PKG_LIST="${PACKAGES[*]}" BORDER_LIST="${PACKAGE_BORDER[*]}" \
python3 << 'PYEOF'
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

tmp = os.environ["TMP"]
images = os.environ["IMAGES"]
packages = os.environ["PKG_LIST"].split()
colors = os.environ["BORDER_LIST"].split()

def read_ratio(path):
    rows = []
    with open(path) as f:
        for line in f:
            parts = line.split()
            if len(parts) >= 2:
                rows.append((parts[0], float(parts[1])))
    return rows

datasets = [read_ratio(f"{tmp}/ratio_{i}.dat") for i in range(len(packages))]
n = len(packages)
n_total = sum(len(d) for d in datasets) + 1

fig, axes = plt.subplots(1, n, figsize=(19 * n / 3, max(6, n_total * 0.32)), sharey=False)
if n == 1:
    axes = [axes]
fig.suptitle("Interface / implementation ratio  (.mli lines ÷ .ml lines)",
             fontsize=13, fontweight="bold", y=0.99)

for ax, pkg, data, color in zip(axes, packages, datasets, colors):
    if not data:
        ax.set_visible(False)
        continue
    names, ratios = zip(*data)
    y = np.arange(len(names))
    bars = ax.barh(y, ratios, height=0.6, color=color, alpha=0.85, edgecolor="#333333", linewidth=0.4)
    ax.axvline(1.0, color="#cc5500", linewidth=1.5, linestyle="--", alpha=0.8)
    ax.text(1.02, len(names) - 0.5, "1:1", color="#cc5500", fontsize=9, va="top")
    ax.set_yticks(y)
    ax.set_yticklabels(names, fontsize=9)
    ax.set_xlabel(".mli / .ml lines", fontsize=10)
    ax.set_title(pkg, fontsize=11, fontweight="bold")
    ax.set_xlim(0, max(max(ratios) * 1.15, 1.3))
    ax.grid(axis="x", color="#cccccc", linewidth=0.6)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    for bar, ratio in zip(bars, ratios):
        ax.text(ratio + 0.02, bar.get_y() + bar.get_height()/2,
                f"{ratio:.2f}", va="center", fontsize=8, color="#333333")

plt.tight_layout(rect=[0, 0, 1, 0.97])
plt.savefig(f"{images}/interface_ratio.png", dpi=130, bbox_inches="tight")
plt.close()
PYEOF

echo ""

# ─── 6. Code statistics ───────────────────────────────────────────────────────

echo "→ code statistics (codebase_map.md)"

MAP_FILE="$ROOT/docs/design/codebase_map.md"
TODAY=$(date '+%Y-%m-%d')

declare -a SRC MLI TEST BENCH MODS TFILES CASES
for i in "${!PACKAGES[@]}"; do
  pkg="${PACKAGES[$i]}"
  SRC[$i]=$(find "$ROOT/$pkg" -name "*.ml" ! -path "*/test/*" ! -path "*/bench/*" ! -name "${pkg}.ml" | xargs cat 2>/dev/null | wc -l | tr -d ' ')
  MLI[$i]=$(find "$ROOT/$pkg" -name "*.mli" ! -path "*/test/*" ! -path "*/bench/*" | xargs cat 2>/dev/null | wc -l | tr -d ' ')
  TEST[$i]=$(find "$ROOT/$pkg/test" -name "*.ml" 2>/dev/null | xargs cat 2>/dev/null | wc -l | tr -d ' ')
  BENCH[$i]=$(find "$ROOT/$pkg/bench" -name "*.ml" 2>/dev/null | xargs cat 2>/dev/null | wc -l | tr -d ' ')
  MODS[$i]=$(find "$ROOT/$pkg" -name "*.mli" ! -path "*/test/*" ! -path "*/bench/*" | wc -l | tr -d ' ')
  TFILES[$i]=$(find "$ROOT/$pkg/test" -name "test_*.ml" 2>/dev/null | grep -v test_main | wc -l | tr -d ' ')
  CASES[$i]=$(grep -r '`Quick\|`Slow' "$ROOT/$pkg/test/" 2>/dev/null | wc -l | tr -d ' ')
done

# Git / GitHub stats (repo-level, not per-package)
total_commits=$(git -C "$ROOT" rev-list --count HEAD)
last_commit=$(git -C "$ROOT" log -1 --format="%ci" | cut -d' ' -f1)
open_issues=$(gh api repos/imunitic/eon --jq '.open_issues_count' 2>/dev/null || echo "n/a")
repo_created=$(gh api repos/imunitic/eon --jq '.created_at[:10]' 2>/dev/null || echo "n/a")

TODAY="$TODAY" MAP_FILE="$MAP_FILE" \
PKG_LIST="${PACKAGES[*]}" \
SRC_LIST="${SRC[*]}" MLI_LIST="${MLI[*]}" TEST_LIST="${TEST[*]}" BENCH_LIST="${BENCH[*]}" \
MODS_LIST="${MODS[*]}" TFILES_LIST="${TFILES[*]}" CASES_LIST="${CASES[*]}" \
TOTAL_COMMITS="$total_commits" LAST_COMMIT="$last_commit" \
OPEN_ISSUES="$open_issues" REPO_CREATED="$repo_created" \
python3 << 'PYEOF'
import os

e = os.environ
packages = e['PKG_LIST'].split()
src    = [int(x) for x in e['SRC_LIST'].split()]
mli    = [int(x) for x in e['MLI_LIST'].split()]
test   = [int(x) for x in e['TEST_LIST'].split()]
bench  = [int(x) for x in e['BENCH_LIST'].split()]
mods   = [int(x) for x in e['MODS_LIST'].split()]
tfiles = [int(x) for x in e['TFILES_LIST'].split()]
cases  = [int(x) for x in e['CASES_LIST'].split()]

today       = e['TODAY']
commits     = e['TOTAL_COMMITS']
last_commit = e['LAST_COMMIT']
open_issues = e['OPEN_ISSUES']
created     = e['REPO_CREATED']
map_file    = e['MAP_FILE']

def esc(pkg):
    return pkg.replace("_", "\\_")

header = "| Category | " + " | ".join(esc(p) for p in packages) + " | Total |"
mod_header = "| | " + " | ".join(esc(p) for p in packages) + " | Total |"
sep = "|---|" + "---:|" * (len(packages) + 1)

def row(label, values):
    return "| " + label + " | " + " | ".join(str(v) for v in values) + " | " + str(sum(values)) + " |"

line_counts = "\n".join([
    header, sep,
    row("Source implementation (`.ml`)", src),
    row("Public interfaces (`.mli`)", mli),
    row("Tests", test),
    row("Benchmarks", bench),
])

module_counts = "\n".join([
    mod_header, sep,
    row("Public modules (with `.mli`)", mods),
    row("Test suites", tfiles),
    row("Test cases", cases),
])

block = f"""<!-- STATS_START -->

## Code statistics

_Generated by `just visualizations` on {today}._

### Line counts

{line_counts}

### Module counts

{module_counts}

### Repository

| | |
|---|---|
| Total commits | {commits} |
| Open issues | {open_issues} |
| Created | {created} |
| Last commit | {last_commit} |

<!-- STATS_END -->"""

content = open(map_file).read()
start = content.find("<!-- STATS_START -->")
end   = content.find("<!-- STATS_END -->") + len("<!-- STATS_END -->")
if start == -1 or end == -1:
    raise SystemExit("sentinel not found in codebase_map.md")
open(map_file, "w").write(content[:start] + block + content[end:])
print("  updated codebase_map.md")
PYEOF

echo "Done. Generated:"
ls -lh "$IMAGES/"*.png | awk '{print "  " $5, $9}'
