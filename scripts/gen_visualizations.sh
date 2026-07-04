#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGES="$ROOT/docs/design/images"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$IMAGES"

# ─── 1. Module dependency graph ───────────────────────────────────────────────

echo "→ module_dependency_graph.png"
cat > "$TMP/deps.dot" << 'EOF'
digraph module_dependencies {
  rankdir=RL
  node [fontname="Helvetica" fontsize=11 style=filled]
  edge [fontname="Helvetica" fontsize=9]

  // ── eon_engine ──────────────────────────────────────────────────────────
  subgraph cluster_engine {
    label="eon_engine"
    style=filled
    fillcolor="#e8f5e9"
    color="#2e7d32"
    fontcolor="#2e7d32"
    fontsize=13
    fontname="Helvetica-Bold"

    node [fillcolor="#a5d6a7" color="#388e3c"]

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

    eng_loop       -> eng_progress
    eng_loop       -> eng_loop_buses
    eng_loop       -> eng_platform
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
  }

  // ── eon_ecs ──────────────────────────────────────────────────────────────
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

  // ── External ─────────────────────────────────────────────────────────────
  mtime [label="mtime\n(external)" shape=box fillcolor="#fff3e0" color="#e65100" fontcolor="#bf360c"]

  ecs_clock -> mtime [color="#e65100"]

  // ── Cross-package edges ───────────────────────────────────────────────────
  edge [color="#cc5500" penwidth=2.0 constraint=false]

  eng_loop     -> ecs_loop
  eng_progress -> ecs_progress
  eng_pipeline -> ecs_pipeline
  eng_system   -> ecs_system
  eng_query    -> ecs_query
  eng_world    -> ecs_world
}
EOF
dot -Tpng -o "$IMAGES/module_dependency_graph.png" "$TMP/deps.dot"

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
    ecs_prog_adp  [label="Progress_adapter"]
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

    ecs_prog_def -> ecs_prog_adp
    ecs_clock    -> ecs_loop_make
    ecs_prog_adp -> ecs_loop_make
    ecs_lbuses   -> ecs_loop_make
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

    // functors
    node [shape=box fillcolor="#b9f6ca" color="#2e7d32"]
    eng_sys_make      [label="System.Make"]
    eng_sys_mf_make   [label="System.Make_factory"]
    eng_pip_make      [label="Pipeline.Make"]

    // results
    node [shape=box fillcolor="#2e7d32" fontcolor=white color="#1b5e20" penwidth=2]
    eng_sys_def   [label="System.Default"]
    eng_def_fac   [label="Default_factory"]
    eng_pip_def   [label="Pipeline.Default"]

    eng_ecs_sys  -> eng_sys_make
    eng_sys_make -> eng_sys_def

    eng_sys_def     -> eng_sys_mf_make
    eng_sys_mf_make -> eng_def_fac

    eng_sys_def -> eng_pip_make
    eng_exec    -> eng_pip_make
    eng_bdefs   -> eng_pip_make
    eng_pip_make -> eng_pip_def
  }

  // cross-package: eon_ecs defaults feed into eon_engine
  edge [color="#cc5500" penwidth=2.0 constraint=false style=dashed]
  ecs_sys_def  -> eng_ecs_sys
  ecs_pip_def  -> eng_pip_def [constraint=false]
}
EOF
dot -Tpng -o "$IMAGES/functor_instantiation_graph.png" "$TMP/functors.dot"

# ─── 3. Test coverage map ────────────────────────────────────────────────────

echo "→ test_coverage_map.png"

# Source modules to check (basename without extension)
ECS_MODULES="entity_id entity_manager component component_registry sparse_set resource_store world query single_bus double_bus buses system pipeline progress loop clock dependency_graph loop_default_buses"
ENG_MODULES="world query component_descriptor component components view single_bus double_bus buses system pipeline progress loop loop_buses executor platform asset_lookup sparse_set_backend query_backend"

{
  echo 'digraph test_coverage {'
  echo '  rankdir=LR'
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
      color="#a5d6a7"
      border="#388e3c"
    else
      color="#ef9a9a"
      border="#c62828"
    fi
    label=$(echo "$mod" | sed 's/_/\\n/g; s/\(.\)/\u\1/')
    echo "    ecs_${mod} [label=\"${mod}\" fillcolor=\"${color}\" color=\"${border}\"]"
  done

  echo '  }'
  echo ''
  echo '  subgraph cluster_engine {'
  echo '    label="eon_engine" style=filled fillcolor="#e8f5e9" color="#2e7d32"'
  echo '    fontcolor="#2e7d32" fontsize=13 fontname="Helvetica-Bold"'

  for mod in $ENG_MODULES; do
    test_file="$ROOT/eon_engine/test/test_${mod}.ml"
    if [ -f "$test_file" ]; then
      color="#a5d6a7"
      border="#388e3c"
    else
      color="#ef9a9a"
      border="#c62828"
    fi
    echo "    eng_${mod} [label=\"${mod}\" fillcolor=\"${color}\" color=\"${border}\"]"
  done

  echo '  }'
  echo '  // anchor edge to force side-by-side cluster layout'
  echo '  ecs_entity_id -> eng_world [style=invis constraint=true]'
  echo '}'
} > "$TMP/coverage.dot"

dot -Tpng -o "$IMAGES/test_coverage_map.png" "$TMP/coverage.dot"

# ─── 4. LOC per module (gnuplot horizontal bar chart) ────────────────────────

echo "→ loc_per_module.png"

# Collect LOC for source .ml files only (no test, bench, examples, composition root)
{
  for f in "$ROOT"/eon_ecs/*.ml; do
    base=$(basename "$f" .ml)
    case "$base" in eon_ecs|*_test*) continue ;; esac
    lines=$(wc -l < "$f")
    echo "ecs $base $lines"
  done
  for f in "$ROOT"/eon_engine/*.ml; do
    base=$(basename "$f" .ml)
    case "$base" in eon_engine|*_test*) continue ;; esac
    lines=$(wc -l < "$f")
    echo "eng $base $lines"
  done
} | sort -k1,1 -k3,3rn > "$TMP/loc_raw.txt"

# Build gnuplot data: two sections separated by blank line
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
    # legend on the side
    ax.legend(wedges, [f"{n}  ({v})" for n,v in zip(labels,values)],
              loc="center left", bbox_to_anchor=(1.02, 0.5),
              fontsize=8, frameon=False)

pie(ax1, ecs, blues,  "eon_ecs")
pie(ax2, eng, greens, "eon_engine")

plt.tight_layout(rect=[0, 0, 1, 0.96])
plt.savefig("$IMAGES/loc_per_module.png", dpi=130, bbox_inches="tight")
plt.close()
PYEOF

# ─── 5. Interface / implementation ratio (gnuplot) ───────────────────────────

echo "→ interface_ratio.png"

{
  for ml in "$ROOT"/eon_ecs/*.ml; do
    base=$(basename "$ml" .ml)
    mli="$ROOT/eon_ecs/${base}.mli"
    case "$base" in eon_ecs|*_test*) continue ;; esac
    [ -f "$mli" ] || continue
    impl=$(wc -l < "$ml")
    iface=$(wc -l < "$mli")
    [ "$impl" -gt 0 ] || continue
    ratio=$(awk "BEGIN {printf \"%.2f\", $iface / $impl}")
    echo "ecs $base $ratio $iface $impl"
  done
  for ml in "$ROOT"/eon_engine/*.ml; do
    base=$(basename "$ml" .ml)
    mli="$ROOT/eon_engine/${base}.mli"
    case "$base" in eon_engine|*_test*) continue ;; esac
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
echo "Done. Generated:"
ls -lh "$IMAGES/"*.png | awk '{print "  " $5, $9}'
