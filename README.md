# network-realization-schema

`network-realization-schema` defines the pinned, versioned contract for the
canonical realization bundle shared by `network-realization-model` and every
`network-renderer-*` repository.

It is a **contract dependency**, not a transformation stage. It does not
consume CPM output, produce network meaning, or sit as an executable hop
between the realization model and a renderer.

The published contract is Nix-native. Its validation checks assert the exact
diagnostic, non-zero exit behavior, and successful recovery of every seeded
negative fixture; a generic boolean failure is not accepted as evidence.

## Position in the architecture

```text
network-control-plane-model
            |
            v
network-realization-model ---- uses ----> network-realization-schema
            |
            v
validated canonical realization bundle
            |
            v
network-renderer-* ------------ uses ----> network-realization-schema
```

All renderers, including `network-renderer-openconfig` as a peer renderer, use
the same schema contract. A renderer must not replace the canonical bundle with
CPM input, raw intent or inventory, a peer-renderer artifact, or a local model.

## Responsibilities

This repository owns:

- the canonical bundle's object shapes, types, constraints, and revisions;
- the pinned schema-set identity and digest;
- validation support for produced bundles and focused fixture bundles;
- compatibility and negative tests for the published contract.

It does not own:

- CPM-to-realization transformation;
- interpretation or repair of upstream network meaning;
- production of platform-binding instances or renderer-specific output;
- orchestration of the compiler, NFM, CPM, realization, or renderer stages.

## Planned repository layout

```text
schema/       versioned canonical schema modules and schema-set metadata
tests/        contract, compatibility, and invalid-instance checks
examples/     small documented valid and invalid bundle examples
flake.nix     pinned validation and development entry points
```

The initial implementation publishes:

- `network-realization/v1` for canonical realization bundles;
- `network-platform-binding/v1` for one normalized target binding bundle
  whose permitted categories are interface identity, deployment,
  secret-delivery, lifecycle, and backend mechanics;
- deterministic SHA-256 identities over canonical Nix JSON serialization;
- JSON-pointer path enumeration;
- fail-closed Nix validators and seeded-negative contract checks.

New network semantics require an explicit schema change; they must not be
introduced privately by a producer or renderer.

## Versioning

This project primarily supports my own infrastructure. Consumers should pin an
exact revision. Backward compatibility is not guaranteed unless a compatibility
boundary is explicitly specified and tested.
