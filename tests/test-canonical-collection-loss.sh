#!/usr/bin/env bash
# GAMP-SCOPE: contract test; the realization model must refuse to drop a published collection
#
# FS-310-HDS-040-SDS-010-SMS-100 -- canonical-only consumption, no raw CPM.
#
# THE VIOLATION
# -------------
# `network-realization-model/src/default.nix` (`canonicalFor`) projects the
# producer's canonical collections into the bundle by filtering them through
# `schema.bundle.canonicalCollections`. That list is CLOSED, and the filter is
# where a collection the producer publishes -- and the schema does not list -- is
# dropped. It is dropped at construction, from a bundle that still validates, so
# every renderer downstream receives a bundle that looks complete and is missing
# published facts. Measured: the producer publishes `canonicalForwarding` and
# `canonicalOverlays`; the schema lists neither, and lists `canonicalWireGuard`
# and `canonicalNebula`, which the producer no longer publishes.
#
# WHAT THIS PROVES
# ----------------
#   CASE 1  seeded negative: a fixture whose CPM carries a collection the schema
#           does not list makes `model.realize` THROW, naming the collection, the
#           row, and the schema file that has to list it. A silent drop fails
#           here, which is the defect.
#   CASE 2  the check can pass: the same fixture without the unlisted collection
#           realizes, and the listed collection it does carry is in the bundle.
#           Without this, CASE 1 could pass by throwing on everything.
#   CASE 3  the live producer: every collection the real CPM publishes is either
#           in the bundle or named by the throw -- nothing is dropped in silence.
#
# Evidence boundary: construction. Evaluation of the sibling model checkout plus
# the producer, when the producer is checked out beside this repository.
set -euo pipefail

if [[ -n "${SMS_TEST_REPO_ROOT:-}" ]]; then
  repo_root="${SMS_TEST_REPO_ROOT}"
else
  repo_root="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "${repo_root}" ]] || repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
workspace_root="${NETWORK_WORKSPACE_ROOT:-$(cd "${repo_root}/.." && pwd)}"
model_repo="${REALIZATION_MODEL_REPO:-${workspace_root}/network-realization-model}"

echo "--- CANONICAL-COLLECTION-LOSS: a dropped published collection must throw ---"
echo ""

row="FS-310-HDS-040-SDS-010-SMS-100"

if [[ ! -f "${model_repo}/src/default.nix" ]]; then
  echo "FAIL CANONICAL-COLLECTION-LOSS: no realization-model checkout at ${model_repo}" >&2
  echo "  the check lives there; without it this test compares nothing and must not pass" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# CASE 1 -- seeded negative. One collection the schema does not list, carried by
# the producer, is enough to make the projection lossy. `realize` must throw.
# ---------------------------------------------------------------------------
seeded_out="$(
  SCHEMA_REPO="${repo_root}" MODEL_REPO="${model_repo}" \
  nix eval --impure --json --expr '
    let
      schemaRepo = builtins.getEnv "SCHEMA_REPO";
      modelRepo = builtins.getEnv "MODEL_REPO";
      schema = import (schemaRepo + "/lib/default.nix");
      model = import (modelRepo + "/src/default.nix") { inherit schema; };
      fixture = import (modelRepo + "/examples/cpm-result.nix");
      # The seed is a collection the schema does NOT list, chosen at evaluation
      # time from the schema itself.
      #
      # It used to be `canonicalOverlays`, hardcoded -- and when the schema started
      # listing `canonicalOverlays` (the correct fix for the drift this test was
      # written for) the seed became a LISTED collection, so the gate correctly
      # stopped firing and CASE 1 failed with "the throw does not name ...". A
      # negative fixture that hardcodes a name the contract is allowed to adopt
      # stops being a negative the moment the contract is repaired.
      seedName = "canonicalByteIndependenceProbe";
      _seedUnlisted = assert !(builtins.elem seedName schema.schema.bundle.canonicalCollections);
      true;
      seeded = fixture // {
        control_plane_model = fixture.control_plane_model // {
          ${seedName} = [ ];
        };
      };
    in
    model.realize {
      input = seeded;
      requestScope = {
        kind = "complete-artifact";
        identity = "canonical-collection-loss-seed";
      };
      rootLockIdentity = "canonical-collection-loss-root-lock";
      producerRevision = "seeded-producer";
    }' 2>&1 || true
)"

issues=0

if ! grep -qF "${row}" <<<"${seeded_out}"; then
  issues=$((issues + 1))
  {
    echo "FAIL CASE 1: the throw does not name ${row}"
    echo "  got: ${seeded_out}"
  } >&2
elif ! grep -qF "NR_CANONICAL_COLLECTION_DROPPED" <<<"${seeded_out}"; then
  issues=$((issues + 1))
  {
    echo "FAIL CASE 1: the throw does not carry NR_CANONICAL_COLLECTION_DROPPED"
    echo "  got: ${seeded_out}"
  } >&2
elif ! grep -qF "canonicalByteIndependenceProbe" <<<"${seeded_out}"; then
  issues=$((issues + 1))
  {
    echo "FAIL CASE 1: the throw does not name the dropped collection"
    echo "  got: ${seeded_out}"
  } >&2
elif ! grep -qF "network-realization-schema/schema/default.nix" <<<"${seeded_out}"; then
  issues=$((issues + 1))
  {
    echo "FAIL CASE 1: the throw does not name the schema file that must list the collection"
    echo "  got: ${seeded_out}"
  } >&2
elif grep -q '^{' <<<"${seeded_out}"; then
  # A successful evaluation is the silent drop: the bundle came out with the
  # collection filtered away and nothing said so.
  issues=$((issues + 1))
  {
    echo "FAIL CASE 1: the seeded loss realized successfully -- the collection was dropped in silence"
    echo "  got: ${seeded_out}"
  } >&2
else
  echo "PASS CASE 1: a producer collection the schema omits throws, naming the row, the collection and the schema file"
fi

# ---------------------------------------------------------------------------
# CASE 2 -- the same check must be able to pass. Without this, CASE 1 is
# satisfied by a check that throws unconditionally.
# ---------------------------------------------------------------------------
# Same rule as CASE 3: the value is stdout. A merged capture puts Nix's
# cold-store progress line in front of the JSON, json.loads then raises, and the
# case reports a realization defect that is really a cache miss.
unseeded_err="$(mktemp)"
trap 'rm -f "${unseeded_err}"' EXIT
unseeded_out="$(
  SCHEMA_REPO="${repo_root}" MODEL_REPO="${model_repo}" \
  nix eval --impure --json --expr '
    let
      schemaRepo = builtins.getEnv "SCHEMA_REPO";
      modelRepo = builtins.getEnv "MODEL_REPO";
      schema = import (schemaRepo + "/lib/default.nix");
      model = import (modelRepo + "/src/default.nix") { inherit schema; };
      fixture = import (modelRepo + "/examples/cpm-result.nix");
      bundle = model.realize {
        input = fixture;
        requestScope = {
          kind = "complete-artifact";
          identity = "canonical-collection-loss-control";
        };
        rootLockIdentity = "canonical-collection-loss-root-lock";
        producerRevision = "control-producer";
      };
    in
    {
      collections = builtins.attrNames (bundle.canonical or { });
      interfaces = builtins.length (bundle.canonical.canonicalInterfaces or [ ]);
    }' 2>"${unseeded_err}" || true
)"

if ! python3 - "${unseeded_out}" <<'PY'
import json
import sys
try:
    payload = json.loads(sys.argv[1])
except Exception:
    sys.exit(1)
# `canonicalInterfaces` is listed by the schema, so it must survive the projection.
sys.exit(0 if payload.get("interfaces", 0) >= 1
         and "canonicalInterfaces" in payload.get("collections", []) else 1)
PY
then
  issues=$((issues + 1))
  {
    echo "FAIL CASE 2: the control fixture did not realize with its listed collection in the bundle"
    echo "  got: ${unseeded_out}"
    if [[ -s "${unseeded_err}" ]]; then
      echo "  last lines of nix's stderr:"
      tail -3 "${unseeded_err}" | sed 's/^/    /'
    fi
  } >&2
else
  echo "PASS CASE 2: the control fixture realizes and keeps the listed collection (the check can pass)"
fi

# ---------------------------------------------------------------------------
# CASE 3 -- the live producer. The schema's list and the producer's published set
# are compared through the MODEL, not by reading the list: what the model hands a
# renderer is the bundle, and a published collection that is neither in the
# bundle nor named by the throw is a silent drop.
# ---------------------------------------------------------------------------
producer_repo="${CANONICAL_PRODUCER_REPO:-${workspace_root}/network-control-plane-model}"
example="${CANONICAL_TEST_EXAMPLE:-${workspace_root}/network-labs/examples/wireguard-provider-overlay}"

# No sibling checkout is the CI layout. Fall back to the PINNED producer inputs
# (flake.lock) rather than letting CASE 3 evaporate: the pinned revisions are what
# this repository actually claims to be compatible with.
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

live_out=""
# stdout carries the document, stderr carries diagnostics. A merged capture
# (`2>&1`) folds Nix's progress line -- "copying path '/nix/store/...-source'
# from 'https://cache.nixos.org'..." -- into the value, so on a cold store the
# first character is `c` instead of `{` and this case reported "the live producer
# did not evaluate" for a commit whose evaluation had succeeded. Measured on a CI
# runner; a developer machine has the store path already and never saw it.
live_err="$(mktemp)"
trap 'rm -f "${live_err}"' EXIT
if [[ -f "${producer_repo}/flake.nix" ]] && [[ -f "${example}/intent.nix" ]]; then
  live_out="$(
    SCHEMA_REPO="${repo_root}" MODEL_REPO="${model_repo}" \
    PRODUCER="${producer_repo}" EXAMPLE="${example}" \
    nix eval --impure --json --expr '
      let
        schemaRepo = builtins.getEnv "SCHEMA_REPO";
        modelRepo = builtins.getEnv "MODEL_REPO";
        producer = builtins.getEnv "PRODUCER";
        example = builtins.getEnv "EXAMPLE";
        schema = import (schemaRepo + "/lib/default.nix");
        model = import (modelRepo + "/src/default.nix") { inherit schema; };
        flake = builtins.getFlake ("path:" + producer);
        cpm = flake.lib."x86_64-linux".compileAndBuildFromPaths {
          inputPath = example + "/intent.nix";
          inventoryPath = example + "/inventory-nixos.nix";
        };
        input = {
          kind = "network-control-plane-artifact";
          artifactIdentity = "published-collection-audit";
          artifactDigest = builtins.hashString "sha256" (builtins.toJSON cpm.control_plane_model);
          inherit (cpm) control_plane_model;
        };
      in
      {
        # The published CANONICAL collections the producer emits.
        #
        # The namespace is the contract, not the opinion of this test: canonicalFor
        # projects only names under `canonical*` and only claims about those
        # (`publishedCanonical = filter (hasPrefix "canonical") ...`). An earlier
        # version of this filter took every list-or-attr of the envelope, so it
        # counted `data`, `secretReadiness`, `secretDeliveryRecords`,
        # `secretAuthorization`, `secretPolicyBoundary`, `secretPlaintextGuard` as
        # "published collections the schema must list" -- they are the CPM
        # envelope-own non-canonical sections, they never enter `bundle.canonical`
        # by design, and CASE 3 then failed with six phantom drops on a correct
        # model. A comparison must use the same predicate as the thing it audits
        # (no apostrophes in this block: it is a single-quoted nix expression).
        published = builtins.filter
          (name: (builtins.isList (cpm.control_plane_model.${name} or null)
                 || builtins.isAttrs (cpm.control_plane_model.${name} or null))
                 && builtins.match "canonical.*" name != null)
          (builtins.attrNames cpm.control_plane_model);
        outcome = builtins.tryEval (builtins.deepSeq (model.realize {
          inherit input;
          requestScope = {
            kind = "complete-artifact";
            identity = "published-collection-audit";
          };
          rootLockIdentity = "published-collection-audit-root-lock";
          producerRevision = "network-control-plane-model";
        }) true);
        # The throw text is not reachable from Nix once thrown, so the model is
        # asked the same question directly: which published collections does the
        # schema list?
        listed = schema.schema.bundle.canonicalCollections;
      }' 2>"${live_err}" || true
  )"
fi

if [[ -z "${live_out}" || "${live_out}" != \{* ]]; then
  # A missing producer is a missing producer, and the previous version said so in a
  # note while the case reported nothing -- so a red run never mentioned the third
  # of the evidence it did not collect. The producer input is pinned in flake.lock
  # and materialised in CI, so "no producer" is a defect here, not an environment
  # fact. Say it, and fail.
  issues=$((issues + 1))
  {
    echo "FAIL CASE 3: the live producer did not evaluate, so nothing was compared"
    if [[ -n "${live_out}" ]]; then
      echo "  first line of the evaluation result:"
      head -1 <<<"${live_out}" | sed 's/^/    /'
      tail -1 <<<"${live_out}" | sed 's/^/    /'
    fi
    if [[ -s "${live_err}" ]]; then
      echo "  last lines of nix's stderr:"
      tail -3 "${live_err}" | sed 's/^/    /'
    fi
    echo "  The producer and its example are pinned inputs (flake.lock), so this is"
    echo "  either the pinned revision failing to compile the example, or the"
    echo "  example's intent/inventory disagreeing -- which is itself the finding."
  } >&2
else
  if ! python3 - "${live_out}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
published = set(payload["published"])
listed = set(payload["listed"])
realized = payload["outcome"]["success"]

unlisted = published - listed

# The outcome and the sets have to agree, in both directions:
#   * unlisted non-empty  -> realize must have FAILED (the throw is the enforcement)
#   * unlisted empty      -> realize must have SUCCEEDED (the check is not vacuous)
if unlisted:
    ok = not realized
else:
    ok = realized

if not ok:
    print("  published: " + " ".join(sorted(published)), file=sys.stderr)
    print("  schema:    " + " ".join(sorted(listed)), file=sys.stderr)
    print("  dropped:   " + " ".join(sorted(unlisted)), file=sys.stderr)
    print("  realized:  " + str(realized), file=sys.stderr)
sys.exit(0 if ok else 1)
PY
  then
    issues=$((issues + 1))
    {
      echo "FAIL CASE 3: the bundle-vs-producer comparison does not match the model's behaviour"
      echo "  a published collection outside the schema's closed set must make realize throw;"
      echo "  with an empty difference, realize must succeed."
    } >&2
  else
    echo "PASS CASE 3: with the live producer, the bundle carries every published collection or realize refuses to produce one"
  fi
fi

echo ""
if ((issues > 0)); then
  echo "FAIL CANONICAL-COLLECTION-LOSS: ${issues} issue(s)." >&2
  echo "  The loss is in network-realization-model/src/default.nix (canonicalFor) and the" >&2
  echo "  fix is network-realization-schema/schema/default.nix -> bundle.canonicalCollections." >&2
  echo "  This test is the enforcement, not the fix. Do not widen the filter." >&2
  exit 1
fi

echo "PASS CANONICAL-COLLECTION-LOSS: a published collection the schema omits crashes the realization"
exit 0
