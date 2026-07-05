#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGES="$ROOT/docs/design/images"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$IMAGES"

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
dot -Tpng -o "$IMAGES/dep_eon_ecs.png" "$TMP/dep_ecs.dot"

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

    // Render
    eng_render_cmds   [label="Render_commands"]
    eng_render_stream [label="Render_stream"]
    eng_render_res    [label="Render_stream_resource"]
    eng_render_coll   [label="Render_stream_collector"]
    eng_render_sys    [label="Render_system"]
    eng_rendering_be  [label="Rendering_backend"]
    eng_rendering_res [label="Rendering_result"]

    // Transform & Lifecycle
    eng_hierarchy     [label="Hierarchy"]
    eng_transform_sys [label="Transform_system"]
    eng_lifecycle_sys [label="Lifecycle_system"]

    eng_loop       -> eng_progress
    eng_loop       -> eng_loop_buses
    eng_loop       -> eng_platform
    eng_loop       -> eng_raw_input
    eng_loop       -> eng_audio_buf
    eng_loop       -> eng_render_res
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

    eng_render_stream -> eng_render_cmds
    eng_render_res    -> eng_world
    eng_render_res    -> eng_render_stream
    eng_render_coll   -> eng_render_stream
    eng_render_coll   -> eng_world
    eng_render_sys    -> eng_render_res
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
  }
}
EOF
dot -Tpng -o "$IMAGES/dep_eon_engine.png" "$TMP/dep_engine.dot"

# ─── 1c. Cross-package dependency graph ───────────────────────────────────────

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

  eng_loop     -> ecs_loop
  eng_progress -> ecs_progress
  eng_pipeline -> ecs_pipeline
  eng_system   -> ecs_system
  eng_query    -> ecs_query
  eng_world    -> ecs_world
}
EOF
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

    // functors
    node [shape=box fillcolor="#b9f6ca" color="#2e7d32"]
    eng_sys_make      [label="System.Make"]
    eng_sys_mf_make   [label="System.Make_factory"]
    eng_pip_make      [label="Pipeline.Make"]
    eng_res_make      [label="Resource.Make"]
    eng_svc_make      [label="Service.Make"]
    eng_render_make   [label="Render_system.Make_with_system"]

    // results
    node [shape=box fillcolor="#2e7d32" fontcolor=white color="#1b5e20" penwidth=2]
    eng_sys_def   [label="System.Default"]
    eng_def_fac   [label="Default_factory"]
    eng_pip_def   [label="Pipeline.Default"]
    eng_res_mod   [label="(Resource.S module)"]
    eng_svc_mod   [label="(Service.S module)"]
    eng_render_sys [label="(Render system)"]

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
  }

  // cross-package: eon_ecs defaults feed into eon_engine
  edge [color="#cc5500" penwidth=2.0 style=dashed]
  ecs_sys_def -> eng_ecs_sys
  ecs_pip_def -> eng_pip_def
}
EOF
dot -Tpng -o "$IMAGES/functor_instantiation_graph.png" "$TMP/functors.dot"

# ─── 3. Test coverage map ────────────────────────────────────────────────────

echo "→ test_coverage_map.png"

ECS_MODULES="entity_id entity_manager component component_registry sparse_set resource_store world query single_bus double_bus buses system pipeline progress loop clock dependency_graph loop_default_buses"

# eon_engine modules — grouped by area for the coverage check
# Format: "module:test_file_basename"  (test_file_basename without the test_ prefix)
# When multiple modules share one test file, each lists the composite file.
ENG_MODULES_CORE="world:world query:query view:view component:api_structure component_descriptor:api_structure components:components single_bus:api_structure double_bus:api_structure buses:api_structure system:api_structure pipeline:pipeline progress:api_structure loop:api_structure loop_buses:api_structure executor:executor sparse_set_backend:api_structure query_backend:query asset_lookup:api_structure math:math"
ENG_MODULES_RESOURCE="resource:resource_service service:resource_service namespace:resource_service"
ENG_MODULES_AUDIO="audio_command:audio audio_command_buffer:audio"
ENG_MODULES_INPUT="raw_input_frame:input"
ENG_MODULES_RENDER="render_commands:render_modules render_stream:render_stream render_stream_resource:render_modules render_stream_collector:render_modules render_system:render_modules rendering_backend:render_modules rendering_result:render_modules"
ENG_MODULES_TRANSFORM="hierarchy:hierarchy transform_system:transform_system lifecycle_system:lifecycle_system"

# Emit coverage nodes for eon_engine; checks test/test_<testfile>.ml
eng_coverage_nodes() {
  local pkg="eng"
  for entry in $ENG_MODULES_CORE $ENG_MODULES_RESOURCE $ENG_MODULES_AUDIO $ENG_MODULES_INPUT $ENG_MODULES_RENDER $ENG_MODULES_TRANSFORM; do
    mod="${entry%%:*}"
    testbase="${entry##*:}"
    test_file="$ROOT/eon_engine/test/test_${testbase}.ml"
    prop_file="$ROOT/eon_engine/test/test_prop_${testbase}.ml"
    if [ -f "$test_file" ] || [ -f "$prop_file" ]; then
      color="#a5d6a7"; border="#388e3c"
    else
      color="#ef9a9a"; border="#c62828"
    fi
    echo "    ${pkg}_${mod} [label=\"${mod}\" fillcolor=\"${color}\" color=\"${border}\"]"
  done
}

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
  echo '  subgraph cluster_ecs {'
  echo '    label="eon_ecs" style=filled fillcolor="#e3f2fd" color="#1565c0"'
  echo '    fontcolor="#1565c0" fontsize=13 fontname="Helvetica-Bold"'

  for mod in $ECS_MODULES; do
    test_file="$ROOT/eon_ecs/test/test_${mod}.ml"
    prop_file="$ROOT/eon_ecs/test/test_prop_${mod}.ml"
    if [ -f "$test_file" ] || [ -f "$prop_file" ]; then
      color="#a5d6a7"; border="#388e3c"
    else
      color="#ef9a9a"; border="#c62828"
    fi
    echo "    ecs_${mod} [label=\"${mod}\" fillcolor=\"${color}\" color=\"${border}\"]"
  done

  echo '  }'
  echo ''
  echo '  subgraph cluster_engine {'
  echo '    label="eon_engine" style=filled fillcolor="#e8f5e9" color="#2e7d32"'
  echo '    fontcolor="#2e7d32" fontsize=13 fontname="Helvetica-Bold"'

  eng_coverage_nodes

  echo '  }'
  echo '  // anchor edge to force side-by-side cluster layout'
  echo '  ecs_entity_id -> eng_world [style=invis constraint=true]'
  echo '}'
} > "$TMP/coverage.dot"

dot -Tpng -o "$IMAGES/test_coverage_map.png" "$TMP/coverage.dot"

# ─── 4. LOC per module (pie charts) ──────────────────────────────────────────

echo "→ loc_per_module.png"

# Collect LOC for source .ml files — scan all subdirs, skip test/, bench/, composition roots, tiny type files
{
  find "$ROOT/eon_ecs" -name "*.ml" \
    ! -path "*/test/*" ! -path "*/bench/*" \
    ! -name "eon_ecs.ml" | while read -r f; do
    base=$(basename "$f" .ml)
    lines=$(wc -l < "$f")
    echo "ecs $base $lines"
  done

  find "$ROOT/eon_engine" -name "*.ml" \
    ! -path "*/test/*" ! -path "*/bench/*" \
    ! -name "eon_engine.ml" | while read -r f; do
    base=$(basename "$f" .ml)
    lines=$(wc -l < "$f")
    echo "eng $base $lines"
  done
} | sort -k1,1 -k3,3rn > "$TMP/loc_raw.txt"

awk '$1=="ecs"{print $2, $3}' "$TMP/loc_raw.txt" | sort -k2,2rn > "$TMP/loc_ecs.dat"
awk '$1=="eng"{print $2, $3}' "$TMP/loc_raw.txt" | sort -k2,2rn > "$TMP/loc_eng.dat"

python3 << PYEOF
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches

def read_dat(path):
    rows = []
    with open(path) as f:
        for line in f:
            parts = line.split()
            if len(parts) >= 2:
                rows.append((parts[0], int(parts[1])))
    return rows

ecs = read_dat("$TMP/loc_ecs.dat")
eng = read_dat("$TMP/loc_eng.dat")

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 8))
fig.suptitle("Source lines per module (implementation only)", fontsize=14, fontweight="bold", y=0.98)

blues  = plt.cm.Blues( [0.4 + 0.5 * i / max(len(ecs)-1,1) for i in range(len(ecs))] )
greens = plt.cm.Greens([0.4 + 0.5 * i / max(len(eng)-1,1) for i in range(len(eng))] )

def pie(ax, data, colors, title):
    labels, values = zip(*data)
    total = sum(values)
    def fmt(v):
        pct = v / total * 100
        return f"{v}\n({pct:.0f}%)" if pct >= 4 else ""
    wedges, texts, autotexts = ax.pie(
        values, labels=None, colors=colors,
        autopct=lambda p: f"{p:.0f}%" if p >= 4 else "",
        pctdistance=0.75, startangle=140,
        wedgeprops=dict(linewidth=0.5, edgecolor="white")
    )
    for t in autotexts:
        t.set_fontsize(8)
    ax.set_title(title, fontsize=12, fontweight="bold", pad=14)
    ax.legend(wedges, [f"{n}  ({v})" for n,v in zip(labels,values)],
              loc="center left", bbox_to_anchor=(1.02, 0.5),
              fontsize=8, frameon=False)

pie(ax1, ecs, blues,  "eon_ecs")
pie(ax2, eng, greens, "eon_engine")

plt.tight_layout(rect=[0, 0, 1, 0.96])
plt.savefig("$IMAGES/loc_per_module.png", dpi=130, bbox_inches="tight")
plt.close()
PYEOF

# ─── 5. Interface / implementation ratio ─────────────────────────────────────

echo "→ interface_ratio.png"

{
  find "$ROOT/eon_ecs" -name "*.ml" \
    ! -path "*/test/*" ! -path "*/bench/*" \
    ! -name "eon_ecs.ml" | while read -r ml; do
    base=$(basename "$ml" .ml)
    dir=$(dirname "$ml")
    mli="$dir/${base}.mli"
    [ -f "$mli" ] || continue
    impl=$(wc -l < "$ml")
    iface=$(wc -l < "$mli")
    [ "$impl" -gt 0 ] || continue
    ratio=$(awk "BEGIN {printf \"%.2f\", $iface / $impl}")
    echo "ecs $base $ratio $iface $impl"
  done

  find "$ROOT/eon_engine" -name "*.ml" \
    ! -path "*/test/*" ! -path "*/bench/*" \
    ! -name "eon_engine.ml" | while read -r ml; do
    base=$(basename "$ml" .ml)
    dir=$(dirname "$ml")
    mli="$dir/${base}.mli"
    [ -f "$mli" ] || continue
    impl=$(wc -l < "$ml")
    iface=$(wc -l < "$mli")
    [ "$impl" -gt 0 ] || continue
    ratio=$(awk "BEGIN {printf \"%.2f\", $iface / $impl}")
    echo "eng $base $ratio $iface $impl"
  done
} | sort -k1,1 -k3,3rn > "$TMP/ratio_raw.txt"

awk '$1=="ecs"{print $2, $3}' "$TMP/ratio_raw.txt" | sort -k2,2rn > "$TMP/ratio_ecs.dat"
awk '$1=="eng"{print $2, $3}' "$TMP/ratio_raw.txt" | sort -k2,2rn > "$TMP/ratio_eng.dat"

python3 << PYEOF
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

def read_ratio(path):
    rows = []
    with open(path) as f:
        for line in f:
            parts = line.split()
            if len(parts) >= 2:
                rows.append((parts[0], float(parts[1])))
    return rows

ecs = read_ratio("$TMP/ratio_ecs.dat")
eng = read_ratio("$TMP/ratio_eng.dat")

all_data = [("eon_ecs", ecs, "#1976d2"), ("eon_engine", eng, "#388e3c")]
n_total = len(ecs) + len(eng) + 1

fig, axes = plt.subplots(1, 2, figsize=(14, max(6, n_total * 0.32)), sharey=False)
fig.suptitle("Interface / implementation ratio  (.mli lines ÷ .ml lines)",
             fontsize=13, fontweight="bold", y=0.99)

for ax, (pkg, data, color) in zip(axes, all_data):
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
plt.savefig("$IMAGES/interface_ratio.png", dpi=130, bbox_inches="tight")
plt.close()
PYEOF

echo ""

# ─── 6. Code statistics ───────────────────────────────────────────────────────

echo "→ code statistics (codebase_map.md)"

MAP_FILE="$ROOT/docs/design/codebase_map.md"
TODAY=$(date '+%Y-%m-%d')

# Line counts — implementation only (no test, bench, composition roots)
ecs_src=$(find "$ROOT/eon_ecs"    -name "*.ml" ! -path "*/test/*" ! -path "*/bench/*" ! -name "eon_ecs.ml"    | xargs cat 2>/dev/null | wc -l | tr -d ' ')
eng_src=$(find "$ROOT/eon_engine" -name "*.ml" ! -path "*/test/*" ! -path "*/bench/*" ! -name "eon_engine.ml" | xargs cat 2>/dev/null | wc -l | tr -d ' ')

ecs_mli=$(find "$ROOT/eon_ecs"    -name "*.mli" ! -path "*/test/*" ! -path "*/bench/*" | xargs cat 2>/dev/null | wc -l | tr -d ' ')
eng_mli=$(find "$ROOT/eon_engine" -name "*.mli" ! -path "*/test/*" ! -path "*/bench/*" | xargs cat 2>/dev/null | wc -l | tr -d ' ')

ecs_test=$(find "$ROOT/eon_ecs/test"    -name "*.ml" 2>/dev/null | xargs cat 2>/dev/null | wc -l | tr -d ' ')
eng_test=$(find "$ROOT/eon_engine/test" -name "*.ml" 2>/dev/null | xargs cat 2>/dev/null | wc -l | tr -d ' ')

ecs_bench=$(find "$ROOT/eon_ecs/bench"    -name "*.ml" 2>/dev/null | xargs cat 2>/dev/null | wc -l | tr -d ' ')
eng_bench=$(find "$ROOT/eon_engine/bench" -name "*.ml" 2>/dev/null | xargs cat 2>/dev/null | wc -l | tr -d ' ')

# Module counts
ecs_mods=$(find "$ROOT/eon_ecs"    -name "*.mli" ! -path "*/test/*" ! -path "*/bench/*" | wc -l | tr -d ' ')
eng_mods=$(find "$ROOT/eon_engine" -name "*.mli" ! -path "*/test/*" ! -path "*/bench/*" | wc -l | tr -d ' ')

ecs_test_files=$(find "$ROOT/eon_ecs/test"    -name "test_*.ml" 2>/dev/null | grep -v test_main | wc -l | tr -d ' ')
eng_test_files=$(find "$ROOT/eon_engine/test" -name "test_*.ml" 2>/dev/null | grep -v test_main | wc -l | tr -d ' ')

ecs_cases=$(grep -r '`Quick\|`Slow' "$ROOT/eon_ecs/test/"    2>/dev/null | wc -l | tr -d ' ')
eng_cases=$(grep -r '`Quick\|`Slow' "$ROOT/eon_engine/test/" 2>/dev/null | wc -l | tr -d ' ')

# Totals
total_src=$((ecs_src + eng_src))
total_mli=$((ecs_mli + eng_mli))
total_test=$((ecs_test + eng_test))
total_bench=$((ecs_bench + eng_bench))
total_mods=$((ecs_mods + eng_mods))
total_test_files=$((ecs_test_files + eng_test_files))
total_cases=$((ecs_cases + eng_cases))

# Git / GitHub stats
total_commits=$(git -C "$ROOT" rev-list --count HEAD)
last_commit=$(git -C "$ROOT" log -1 --format="%ci" | cut -d' ' -f1)
open_issues=$(gh api repos/imunitic/eon --jq '.open_issues_count' 2>/dev/null || echo "n/a")
repo_created=$(gh api repos/imunitic/eon --jq '.created_at[:10]' 2>/dev/null || echo "n/a")

# Inject stats block between sentinels
TODAY="$TODAY" \
ECS_SRC="$ecs_src" ENG_SRC="$eng_src" TOTAL_SRC="$total_src" \
ECS_MLI="$ecs_mli" ENG_MLI="$eng_mli" TOTAL_MLI="$total_mli" \
ECS_TEST="$ecs_test" ENG_TEST="$eng_test" TOTAL_TEST="$total_test" \
ECS_BENCH="$ecs_bench" ENG_BENCH="$eng_bench" TOTAL_BENCH="$total_bench" \
ECS_MODS="$ecs_mods" ENG_MODS="$eng_mods" TOTAL_MODS="$total_mods" \
ECS_TEST_FILES="$ecs_test_files" ENG_TEST_FILES="$eng_test_files" TOTAL_TEST_FILES="$total_test_files" \
ECS_CASES="$ecs_cases" ENG_CASES="$eng_cases" TOTAL_CASES="$total_cases" \
TOTAL_COMMITS="$total_commits" LAST_COMMIT="$last_commit" \
OPEN_ISSUES="$open_issues" REPO_CREATED="$repo_created" \
MAP_FILE="$MAP_FILE" \
python3 << 'PYEOF'
import os

e = os.environ
today         = e['TODAY']
ecs_src       = e['ECS_SRC'];       eng_src       = e['ENG_SRC'];       total_src       = e['TOTAL_SRC']
ecs_mli       = e['ECS_MLI'];       eng_mli       = e['ENG_MLI'];       total_mli       = e['TOTAL_MLI']
ecs_test      = e['ECS_TEST'];      eng_test      = e['ENG_TEST'];       total_test      = e['TOTAL_TEST']
ecs_bench     = e['ECS_BENCH'];     eng_bench     = e['ENG_BENCH'];      total_bench     = e['TOTAL_BENCH']
ecs_mods      = e['ECS_MODS'];      eng_mods      = e['ENG_MODS'];       total_mods      = e['TOTAL_MODS']
ecs_tf        = e['ECS_TEST_FILES']; eng_tf       = e['ENG_TEST_FILES']; total_tf        = e['TOTAL_TEST_FILES']
ecs_cases     = e['ECS_CASES'];     eng_cases     = e['ENG_CASES'];      total_cases     = e['TOTAL_CASES']
commits       = e['TOTAL_COMMITS']
last_commit   = e['LAST_COMMIT']
open_issues   = e['OPEN_ISSUES']
created       = e['REPO_CREATED']
map_file      = e['MAP_FILE']

block = f"""<!-- STATS_START -->

## Code statistics

_Generated by `just visualizations` on {today}._

### Line counts

| Category | eon\\_ecs | eon\\_engine | Total |
|---|---:|---:|---:|
| Source implementation (`.ml`) | {ecs_src} | {eng_src} | {total_src} |
| Public interfaces (`.mli`) | {ecs_mli} | {eng_mli} | {total_mli} |
| Tests | {ecs_test} | {eng_test} | {total_test} |
| Benchmarks | {ecs_bench} | {eng_bench} | {total_bench} |

### Module counts

| | eon\\_ecs | eon\\_engine | Total |
|---|---:|---:|---:|
| Public modules (with `.mli`) | {ecs_mods} | {eng_mods} | {total_mods} |
| Test suites | {ecs_tf} | {eng_tf} | {total_tf} |
| Test cases | {ecs_cases} | {eng_cases} | {total_cases} |

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
