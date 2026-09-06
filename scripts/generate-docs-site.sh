#!/usr/bin/env bash
# Turns the plain `dune build @doc` output into a full docs site:
#
#  1. Renders README.md into index.html as the site's landing page, with
#     the package table's links pointed at each package's odoc docs instead
#     of the in-repo READMEs, and other repo-relative links (docs/design/*)
#     pointed at GitHub, since neither exists on the published site.
#  2. Injects the same left sidebar (Home / eon-ecs / eon-engine / eon-edn /
#     GitHub) into every page odoc generated, plus index.html itself, so
#     navigation persists across the whole site the way odoc's own nav/TOC
#     does within a single package.
#
# Run after `just docs` (see the `docs-site` Justfile recipe). Requires
# pandoc.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="${1:-$repo_root/_build/default/_doc/_html}"

command -v pandoc >/dev/null || { echo "pandoc is required" >&2; exit 1; }
[ -d "$out_dir" ] || { echo "not found: $out_dir (run \`just docs\` first)" >&2; exit 1; }

# dune writes its @doc output read-only; drop the stale file so pandoc can
# write the replacement rather than failing to open it for writing.
rm -f "$out_dir/index.html"

sed \
  -e 's|eon_engine/README\.md#platform|eon-engine/index.html|g' \
  -e 's|eon_engine/README\.md|eon-engine/index.html|g' \
  -e 's|eon_ecs/README\.md|eon-ecs/index.html|g' \
  -e 's|eon_edn/README\.md|eon-edn/index.html|g' \
  -e 's|docs/design/codebase_map\.md|https://github.com/imunitic/eon/blob/main/docs/design/codebase_map.md|g' \
  -e 's|docs/design/index\.md|https://github.com/imunitic/eon/blob/main/docs/design/index.md|g' \
  "$repo_root/README.md" \
  | pandoc --from=gfm --to=html5 --standalone \
      --metadata title="Eon" \
      -c odoc.support/odoc.css \
      -o "$out_dir/index.html"

cp "$repo_root/scripts/docs-index.css" "$out_dir/docs-index.css"

n=0
while IFS= read -r -d '' file; do
  rel_dir="$(dirname "${file#"$out_dir"/}")"
  if [ "$rel_dir" = "." ]; then
    prefix=""
  else
    depth=$(awk -F'/' '{print NF}' <<< "$rel_dir")
    prefix=$(printf '../%.0s' $(seq 1 "$depth"))
  fi

  perl -0777 -i -pe '
    s{</head>}{<link rel="stylesheet" href="'"$prefix"'docs-index.css"/></head>};
    s{(<body[^>]*>)}{$1<nav id="global-sidebar"><div class="sidebar-title">Eon</div><ul><li><a href="'"$prefix"'index.html">Home</a></li><li><a href="'"$prefix"'eon-ecs/index.html">eon-ecs</a></li><li><a href="'"$prefix"'eon-engine/index.html">eon-engine</a></li><li><a href="'"$prefix"'eon-edn/index.html">eon-edn</a></li><li><a href="https://github.com/imunitic/eon">GitHub &#8599;</a></li></ul></nav>};
  ' "$file"
  n=$((n + 1))
done < <(find "$out_dir" -name '*.html' -print0)

echo "docs site: injected sidebar into $n pages" >&2
