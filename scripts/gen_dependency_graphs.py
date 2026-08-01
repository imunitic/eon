#!/usr/bin/env python3
"""
Generates the dependency .dot digraphs (dep_eon_ecs, dep_eon_engine,
dep_eon_edn, dep_cross_package) from real tree-sitter tags data, replacing
the hand-maintained digraphs gen_visualizations.sh used to carry directly
as heredocs. See designs/ecs -- Mechanically-derived dependency graphs.md
(second-brain vault) for the full rationale and audit that motivated this.

Mechanical, name-based signal only -- same heuristic-not-type-resolved
caveat as the rest of Synapse's tree-sitter layer (sb-002). Two distinct
edge sources:
  - plain `module | ref` tags entries, resolved within the SAME package
    only (OCaml needs no package qualifier for same-package references,
    so a bare name always means "this package's own module of that name").
  - `Eon_ecs.Xxx` / `Eon_edn.Xxx` qualified references, recovered via
    regex over the tags' own quoted source-line text -- this is what
    actually reveals *which* cross-package module is used, since a plain
    module-kind tag for a qualified access only ever shows the package
    prefix itself ("Eon_ecs"), never the specific submodule.

Fails soft: prints nothing and exits 1 if `synapse-tags.sh` isn't on disk,
or if every file's tags call comes back empty (tree-sitter/grammar not
actually working) -- callers must fall back to whatever hand-drawn
content they already have, never treat this as a hard dependency.

Usage: gen_dependency_graphs.py <output-dir> [eon-repo-root]
Writes dep_ecs.dot, dep_engine.dot, dep_edn.dot, dep_cross.dot into
<output-dir> on success. Exits 1, writes nothing, on failure.
"""
import os
import re
import subprocess
import sys

PACKAGES = ["eon_ecs", "eon_engine", "eon_edn"]
PACKAGE_BG = {"eon_ecs": "#e3f2fd", "eon_engine": "#e8f5e9", "eon_edn": "#f3e5f5"}
PACKAGE_BORDER = {"eon_ecs": "#1565c0", "eon_engine": "#2e7d32", "eon_edn": "#7b1fa2"}
PACKAGE_NODE_FILL = {"eon_ecs": "#90caf9", "eon_engine": "#a5d6a7", "eon_edn": "#ce93d8"}
PACKAGE_NODE_BORDER = {"eon_ecs": "#1976d2", "eon_engine": "#388e3c", "eon_edn": "#8e24aa"}
PACKAGE_PREFIX = {"eon_ecs": "ecs", "eon_engine": "eng", "eon_edn": "edn"}
PACKAGE_DOT_FILE = {"eon_ecs": "dep_ecs.dot", "eon_engine": "dep_engine.dot", "eon_edn": "dep_edn.dot"}

TAGS_BIN = os.path.expanduser("~/.claude/bin/synapse-tags.sh")

MODULE_REF_RE = re.compile(r"^([^\t]+)\t\s*\|\s*module\s*\tref\b")
QUALIFIED_RE = {
    "eon_ecs": re.compile(r"\bEon_ecs\.([A-Z][A-Za-z0-9_]*)"),
    "eon_edn": re.compile(r"\bEon_edn\.([A-Z][A-Za-z0-9_]*)"),
}


def capitalize(name):
    return name[:1].upper() + name[1:] if name else name


def find_source_files(root, pkg):
    """Same file set gen_visualizations.sh's sections 3-6 already use
    (test/bench/composition-root excluded), minus examples/ -- the hand
    graphs this replaces never drew example files as their own nodes."""
    pkg_root = os.path.join(root, pkg)
    out = []
    for dirpath, _dirnames, filenames in os.walk(pkg_root):
        segs = set(dirpath.split(os.sep))
        if segs & {"test", "bench", "examples"}:
            continue
        for fn in filenames:
            if fn.endswith(".ml") and fn != f"{pkg}.ml":
                out.append(os.path.join(dirpath, fn))
    return sorted(out)


def collapse_target(root, pkg, path):
    """A file under pkg/src/<subdir>/ collapses into the sibling
    pkg/src/<subdir>.ml aggregate module's name, if one exists (matches
    the one real case in this codebase: eon_engine/src/components/*.ml
    folding into the `components.ml` aggregate). Everything else maps to
    its own basename -- no other subdir here has such a sibling today."""
    rel = os.path.relpath(path, os.path.join(root, pkg))
    parts = rel.split(os.sep)
    if len(parts) >= 3 and parts[0] == "src":
        subdir = parts[1]
        sibling = os.path.join(root, pkg, "src", subdir + ".ml")
        if os.path.exists(sibling):
            return capitalize(subdir)
    base = os.path.splitext(parts[-1])[0]
    return capitalize(base)


def run_tags(path):
    if not os.path.exists(TAGS_BIN):
        return ""
    try:
        r = subprocess.run([TAGS_BIN, path], capture_output=True, text=True, timeout=30)
    except Exception:
        return ""
    return r.stdout if r.returncode == 0 else ""


def module_refs(tags_text):
    refs = set()
    for line in tags_text.splitlines():
        m = MODULE_REF_RE.match(line)
        if m:
            refs.add(m.group(1).strip())
    return refs


def qualified_refs(tags_text):
    out = set()
    for pkg, rx in QUALIFIED_RE.items():
        for m in rx.finditer(tags_text):
            out.add((pkg, m.group(1)))
    return out


def build(root):
    registry = {}
    for pkg in PACKAGES:
        registry[pkg] = {}
        for path in find_source_files(root, pkg):
            base = os.path.splitext(os.path.basename(path))[0]
            mod = capitalize(base)
            registry[pkg][mod] = (collapse_target(root, pkg, path), path)

    intra_edges = {pkg: set() for pkg in PACKAGES}
    cross_edges = set()  # (src_pkg, src_collapsed, dst_pkg, dst_collapsed)
    any_tags = False

    for pkg in PACKAGES:
        for mod, (collapsed_src, path) in registry[pkg].items():
            text = run_tags(path)
            mli = path[:-3] + ".mli"
            if os.path.exists(mli):
                text += "\n" + run_tags(mli)
            if not text.strip():
                continue
            any_tags = True

            # tree-sitter tags each segment of a qualified path separately --
            # for `Eon_ecs.Query.iter_entities`, that's a `module | ref` for
            # BOTH "Eon_ecs" and "Query". The plain module_refs() below has
            # no way to tell "Query" apart from a genuine bare, same-package
            # reference, and would wrongly resolve it against this package's
            # own same-named module if one exists. The qualified-path regex
            # already identifies exactly which names are middle segments of
            # a cross-package access, not bare references -- exclude them.
            qualified = qualified_refs(text)
            qualified_names = {qmod for _qpkg, qmod in qualified}

            for ref in module_refs(text):
                if ref == mod or ref in qualified_names:
                    continue
                target = registry[pkg].get(ref)
                if not target:
                    continue  # not an internal module of this package -> stdlib/external
                collapsed_dst, _ = target
                if collapsed_dst == collapsed_src:
                    continue  # collapsed into the same visual node -> not a drawn edge
                intra_edges[pkg].add((collapsed_src, collapsed_dst))

            for qpkg, qmod in qualified:
                target = registry.get(qpkg, {}).get(qmod)
                if not target:
                    continue
                collapsed_dst, _ = target
                cross_edges.add((pkg, collapsed_src, qpkg, collapsed_dst))

    if not any_tags:
        return None  # tree-sitter/grammar not actually working -> fail soft
    return registry, intra_edges, cross_edges


def dot_header(digraph_name):
    return [
        f"digraph {digraph_name} {{",
        "  rankdir=RL",
        '  node [fontname="Helvetica" fontsize=11 style=filled]',
        '  edge [fontname="Helvetica" fontsize=9]',
        "",
    ]


def node_id(pkg, label):
    return f"{PACKAGE_PREFIX[pkg]}_{label.lower()}"


def emit_package_dot(pkg, edges):
    lines = dot_header(f"{pkg}_dependencies")
    lines.append(f"  subgraph cluster_{PACKAGE_PREFIX[pkg]} {{")
    lines.append(f'    label="{pkg}"')
    lines.append("    style=filled")
    lines.append(f'    fillcolor="{PACKAGE_BG[pkg]}"')
    lines.append(f'    color="{PACKAGE_BORDER[pkg]}"')
    lines.append(f'    fontcolor="{PACKAGE_BORDER[pkg]}"')
    lines.append("    fontsize=13")
    lines.append('    fontname="Helvetica-Bold"')
    lines.append("")
    lines.append(f'    node [fillcolor="{PACKAGE_NODE_FILL[pkg]}" color="{PACKAGE_NODE_BORDER[pkg]}"]')
    lines.append("")

    nodes = sorted({n for edge in edges for n in edge})
    for n in nodes:
        lines.append(f'    {node_id(pkg, n)} [label="{n}"]')
    lines.append("")
    for src, dst in sorted(edges):
        lines.append(f"    {node_id(pkg, src)} -> {node_id(pkg, dst)}")
    lines.append("  }")
    lines.append("}")
    return "\n".join(lines) + "\n"


def emit_cross_dot(cross_edges):
    lines = [
        "digraph cross_package_dependencies {",
        "  rankdir=LR",
        '  node [fontname="Helvetica" fontsize=11 style=filled]',
        '  edge [fontname="Helvetica" fontsize=9 color="#cc5500" penwidth=2.5]',
        "",
    ]

    by_pkg = {pkg: set() for pkg in PACKAGES}
    for src_pkg, src_n, dst_pkg, dst_n in cross_edges:
        by_pkg[src_pkg].add(src_n)
        by_pkg[dst_pkg].add(dst_n)

    for pkg in PACKAGES:
        if not by_pkg[pkg]:
            continue
        lines.append(f"  subgraph cluster_{PACKAGE_PREFIX[pkg]} {{")
        lines.append(f'    label="{pkg}"')
        lines.append("    style=filled")
        lines.append(f'    fillcolor="{PACKAGE_BG[pkg]}"')
        lines.append(f'    color="{PACKAGE_BORDER[pkg]}"')
        lines.append(f'    fontcolor="{PACKAGE_BORDER[pkg]}"')
        lines.append("    fontsize=13")
        lines.append('    fontname="Helvetica-Bold"')
        lines.append(f'    node [fillcolor="{PACKAGE_NODE_FILL[pkg]}" color="{PACKAGE_NODE_BORDER[pkg]}"]')
        for n in sorted(by_pkg[pkg]):
            lines.append(f'    {node_id(pkg, n)} [label="{n}"]')
        lines.append("  }")
        lines.append("")

    for src_pkg, src_n, dst_pkg, dst_n in sorted(cross_edges):
        lines.append(f"  {node_id(src_pkg, src_n)} -> {node_id(dst_pkg, dst_n)}")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main():
    if len(sys.argv) < 2:
        print("usage: gen_dependency_graphs.py <output-dir> [eon-repo-root]", file=sys.stderr)
        sys.exit(1)
    out_dir = sys.argv[1]
    root = sys.argv[2] if len(sys.argv) > 2 else os.getcwd()

    result = build(root)
    if result is None:
        sys.exit(1)
    registry, intra_edges, cross_edges = result

    os.makedirs(out_dir, exist_ok=True)
    for pkg in PACKAGES:
        if pkg == "eon_edn" and not intra_edges[pkg]:
            # eon_edn's real graph is tiny (3 modules) -- an empty result
            # here would be suspicious, but don't hard-fail the whole run
            # over one package; just skip writing an empty/misleading file.
            continue
        with open(os.path.join(out_dir, PACKAGE_DOT_FILE[pkg]), "w") as f:
            f.write(emit_package_dot(pkg, intra_edges[pkg]))
    with open(os.path.join(out_dir, "dep_cross.dot"), "w") as f:
        f.write(emit_cross_dot(cross_edges))


if __name__ == "__main__":
    main()
