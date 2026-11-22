{
  bundle = {
    kind = "network-realization-bundle";
    revision = "network-realization/v1";
    required = [
      "kind"
      "schemaRevision"
      "bundleIdentity"
      "requestScope"
      "sources"
      "network"
      "protectedReferences"
      "provenance"
      "coverageIdentity"
    ];
    # Upstream coverage is delivered as a coverage identity bound to the
    # canonical artifact identity, plus the declared invariants that reproduce
    # it. The expanded per-path enumeration (`upstreamCoverage`) remains
    # accepted for fixtures and diagnostics but is no longer required: the
    # artifact's own `network` content determines it.
    optional = [
      "coverageInvariants"
      "upstreamCoverage"
      "upstreamCoverageIdentity"
      "canonical"
    ];
    # `canonical` is the bundle's platform-neutral network content: the
    # producer's canonical collections, published where a renderer can consume
    # them without reaching into `network.data` (which is the control-plane
    # artifact with a validation wrapper around it, i.e. the plain CPM).
    #
    # WHY THIS IS A SCHEMA FIELD
    # -------------------------
    # RR_RAW_CPM_INPUT forbids a renderer taking network semantics from the
    # plain control-plane model. Until this field existed, "consume the
    # validated bundle" and "consume the CPM" were the same operation, so every
    # renderer that worked did so by reading `controlPlaneEnvelope` -- and the
    # ones that refused to (network-renderer-openconfig) rendered nothing.
    #
    # The collections are a closed set, named exactly as the producer publishes
    # them, and every entry must be a list or an attribute set. A renderer maps
    # these; it may not synthesize a member, and it may not read the model to
    # fill a gap.
    canonicalCollections = [
      "canonicalInterfaces"
      "canonicalRoutes"
      "canonicalSites"
      "canonicalRuntimeTargets"
      "canonicalWireGuard"
      "canonicalNebula"
    ];
  };

  platformBinding = {
    kind = "network-platform-binding-bundle";
    revision = "network-platform-binding/v1";
    allowedCategories = [
      "interfaceIdentity"
      "deployment"
      "secretDelivery"
      "lifecycle"
      "backend"
    ];
    required = [
      "kind"
      "schemaRevision"
      "bindingIdentity"
      "bundleIdentity"
      "target"
      "requestScope"
      "categories"
      "provenance"
    ];
    allowedTopLevel = [
      "kind"
      "schemaRevision"
      "bindingIdentity"
      "bundleIdentity"
      "target"
      "requestScope"
      "categories"
      "provenance"
      "validation"
    ];
  };
}
