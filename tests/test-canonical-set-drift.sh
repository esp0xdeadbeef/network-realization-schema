#!/usr/bin/env bash
# GAMP-SCOPE: contract test; the schema's closed canonical set vs what the producer publishes
#
# THE SCHEMA'S `canonicalCollections` LIST AND THE PRODUCER'S PUBLISHED COLLECTIONS
# MUST BE THE SAME SET.
#
# `schema/default.nix` declares `bundle.canonicalCollections` as a CLOSED set, and
# `lib/default.nix` (`validateCanonical`) fails the bundle on any collection not in
# it -- `NR_SCHEMA_SHAPE_INVALID: unknown canonical collections ...`. That makes the
# list load-bearing in both directions:
#
#   * a collection the producer publishes and the list omits is rejected, so the
#     renderer never sees a bundle;
#   * a name the list carries and the producer no longer publishes is dead weight
#     that keeps a stale contract alive, and it is how a rename becomes a
#     half-rename.
#
# Neither direction is visible from inside one repository, which is why this test
# evaluates both: the schema's list here, and the producer's output from the
# sibling checkout.
#
# Evidence boundary: construction. Evaluation plus one file read. No build, no lab.
set -euo pipefail

if [[ -n "${SMS_TEST_REPO_ROOT:-}" ]]; then
  repo_root="${SMS_TEST_REPO_ROOT}"
else
  repo_root="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "${repo_root}" ]] || repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
workspace_root="${NETWORK_WORKSPACE_ROOT:-$(cd "${repo_root}/.." && pwd)}"

echo "--- CANONICAL-SET-DRIFT: schema closed set vs producer output ---"
echo ""

# ---------------------------------------------------------------------------
# The schema's declared set. It is a plain attribute set, so no flake needed.
# ---------------------------------------------------------------------------
declared="$(nix eval --impure --json --expr '
  let self = builtins.getEnv "REPO_ROOT"; in
  (import (self + "/schema/default.nix")).bundle.canonicalCollections' \
  --apply 'builtins.sort builtins.lessThan' 2>/dev/null || true)"

if [[ -z "${declared}" ]]; then
  # `--apply` after `--expr` is not portable across nix versions; fall back.
  declared="$(REPO_ROOT="${repo_root}" nix eval --impure --json --expr '
    let self = builtins.getEnv "REPO_ROOT"; in
    builtins.sort builtins.lessThan
      (import (self + "/schema/default.nix")).bundle.canonicalCollections' 2>/dev/null || true)"
fi

if [[ -z "${declared}" ]]; then
  echo "FAIL CANONICAL-SET-DRIFT: could not evaluate schema/default.nix's canonicalCollections" >&2
  exit 1
fi

echo "  schema declares: $(python3 -c "import json;print(' '.join(json.loads('''${declared}''')))")"

# ---------------------------------------------------------------------------
# The producer's published set. The CPM is a sibling checkout; without it there is
# nothing to compare, and a PASS here would claim a comparison that did not happen.
# ---------------------------------------------------------------------------
producer_repo="${CANONICAL_PRODUCER_REPO:-${workspace_root}/network-control-plane-model}"
example="${CANONICAL_TEST_EXAMPLE:-${workspace_root}/network-labs/examples/wireguard-provider-overlay}"

# A sibling checkout is the developer layout, not the CI layout. When there is no
# sibling (CI checks this repository out alone before the sibling step, and a fresh
# clone has none), fall back to the PINNED flake inputs -- the same revision the
# flake.lock names, which is what CI materialises. Skipping here was the defect: a
# skipped case is not a verdict, so the workflow turned this file red with no
# comparison having happened.
if [[ ! -f "${producer_repo}/flake.nix" ]] || [[ ! -f "${example}/intent.nix" ]]; then
  nix_expr=(
    --impure --json --expr
    'let flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT"); in
     { producer = toString flake.producerAuditRoots.network-control-plane-model;
       example = toString flake.producerAuditRoots.canonicalExample; }'
  )
  pinned="$(REPO_ROOT="${repo_root}" nix eval "${nix_expr[@]}" 2>/dev/null || true)"
  if [[ -n "${pinned}" ]]; then
    pinned_producer="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["producer"])' "${pinned}" 2>/dev/null || true)"
    pinned_example="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["example"])' "${pinned}" 2>/dev/null || true)"
    if [[ -n "${pinned_producer}" && -f "${pinned_producer}/flake.nix" ]]; then producer_repo="${pinned_producer}"; fi
    if [[ -n "${pinned_example}" && -f "${pinned_example}/intent.nix" ]]; then example="${pinned_example}"; fi
  fi
fi

if [[ ! -f "${producer_repo}/flake.nix" ]] || [[ ! -f "${example}/intent.nix" ]]; then
  echo "FAIL CANONICAL-SET-DRIFT: no producer to compare against, so there is no verdict" >&2
  echo "  looked for a sibling at ${workspace_root}/network-control-plane-model and" >&2
  echo "  ${workspace_root}/network-labs/examples/wireguard-provider-overlay, and for the" >&2
  echo "  pinned flake inputs (network-control-plane-model, network-labs)." >&2
  echo "  A skip would claim this comparison happened when it did not." >&2
  exit 1
fi

producer_err="$(mktemp)"
published="$(PRODUCER="${producer_repo}" EXAMPLE="${example}" \
  nix eval --impure --json --expr '
    let
      producer = builtins.getEnv "PRODUCER";
      example = builtins.getEnv "EXAMPLE";
      flake = builtins.getFlake ("path:" + producer);
      lib = flake.inputs.nixpkgs.lib;
      system = "x86_64-linux";
      cpm = flake.lib.${system}.compileAndBuildFromPaths {
        inputPath = example + "/intent.nix";
        inventoryPath = example + "/inventory-nixos.nix";
      };
    in
    builtins.sort builtins.lessThan
      (builtins.filter (lib.hasPrefix "canonical") (builtins.attrNames cpm.control_plane_model))' \
  2>"${producer_err}" || true)"

if [[ -z "${published}" ]]; then
  echo "FAIL CANONICAL-SET-DRIFT: the producer evaluated to nothing (cannot compare)" >&2
  # DO NOT swallow this. A bare `2>/dev/null` here once reported "evaluated to
  # nothing" while the real cause was a model error in the example's inventory, so
  # the failure pointed at the schema instead of the producer. Whatever nix said is
  # the finding.
  if [[ -s "${producer_err}" ]]; then
    echo "  the producer's own error follows; it is the finding, not this test:" >&2
    sed 's/^/    /' "${producer_err}" | tail -20 >&2
  fi
  rm -f "${producer_err}"
  exit 1
fi
rm -f "${producer_err}"

echo "  producer publishes: $(python3 -c "import json;print(' '.join(json.loads('''${published}''')))")"
echo ""

issues=0

diff_sets() {
  python3 - "$1" "$2" <<'PY'
import json, sys
a = set(json.loads(sys.argv[1]))
b = set(json.loads(sys.argv[2]))
print("only-schema " + (" ".join(sorted(a - b)) or "-"))
print("only-producer " + (" ".join(sorted(b - a)) or "-"))
PY
}

compare() {
  local declared_json="$1" published_json="$2"
  local only_schema only_producer
  read -r _ only_schema < <(diff_sets "${declared_json}" "${published_json}" | sed -n '1p')
  read -r _ only_producer < <(diff_sets "${declared_json}" "${published_json}" | sed -n '2p')

  if [[ "${only_schema}" != "-" ]]; then
    issues=$((issues + 1))
    {
      echo "ISSUE DRIFT-SCHEMA-ONLY: the schema declares collection(s) the producer does not publish: ${only_schema}"
      echo "  why:  the entry is a contract nothing satisfies. It is also how a rename becomes"
      echo "        a half-rename: the old name stays in the closed set, so a bundle that"
      echo "        carries it keeps validating while nothing produces it."
      echo "  read: schema/default.nix -> bundle.canonicalCollections, and"
      echo "        lib/default.nix -> validateCanonical ('unknown canonical collections')."
    } >&2
  fi

  if [[ "${only_producer}" != "-" ]]; then
    issues=$((issues + 1))
    {
      echo "ISSUE DRIFT-PRODUCER-ONLY: the producer publishes collection(s) the schema does not declare: ${only_producer}"
      echo "  why:  validateCanonical fails on any collection outside the closed set, so a"
      echo "        bundle carrying these is rejected -- the renderer never sees it. The"
      echo "        failure surfaces as NR_SCHEMA_SHAPE_INVALID far from the rename that"
      echo "        caused it."
      echo "  read: lib/default.nix -> validateCanonical, and schema/default.nix ->"
      echo "        bundle.canonicalCollections."
    } >&2
  fi

  if [[ "${only_schema}" == "-" && "${only_producer}" == "-" ]]; then
    echo "PASS DRIFT: the schema's closed set and the producer's output are the same set"
  fi
}

compare "${declared}" "${published}"

# ---------------------------------------------------------------------------
# Seeded negatives -- each direction of the comparison must be able to fire.
# ---------------------------------------------------------------------------
seeded_schema="$(python3 - <<'PY'
import json
# a set that names a collection the producer does not publish
print(json.dumps(["canonicalInterfaces", "canonicalRoutes", "canonicalWireGuard"]))
PY
)"
seeded_producer="$(python3 - <<'PY'
import json
# and the reverse: a collection the schema does not declare
print(json.dumps(["canonicalInterfaces", "canonicalRoutes", "canonicalOverlays"]))
PY
)"

seeded_out="$(diff_sets "${seeded_schema}" "${seeded_producer}")"
seeded_hits="$(grep -cE 'only-(schema|producer) .*canonical' <<<"${seeded_out}" || true)"

if [[ "${seeded_hits}" -lt 2 ]]; then
  issues=$((issues + 1))
  {
    echo "ISSUE SEED: the comparison did not report both directions on the seeded input"
    echo "  got: ${seeded_out}"
    echo "  every PASS above is therefore not evidence"
  } >&2
else
  echo "PASS SEED: both directions of the comparison fire on the seeded input"
fi

echo ""
if ((issues > 0)); then
  echo "FAIL CANONICAL-SET-DRIFT: ${issues} issue(s)." >&2
  echo "  The closed set and the producer's output are one decision. Change them in the" >&2
  echo "  same change, and do not add a name here to silence the unknown-collection error." >&2
  exit 1
fi

echo "PASS CANONICAL-SET-DRIFT: schema and producer agree on the canonical collection set"
exit 0
