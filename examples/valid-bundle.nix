{
  schema ? import ../lib/default.nix,
}:

let
  candidate = {
    kind = schema.schema.bundle.kind;
    schemaRevision = schema.schema.bundle.revision;
    requestScope = {
      kind = "complete-artifact";
      identity = "fixture-scope";
    };
    sources.cpm = {
      identity = "fixture-cpm";
      digest = builtins.hashString "sha256" "fixture-cpm";
    };
    network.data.example.site.runtimeTargets.router = {
      role = "core";
      interfaces.lan = {
        kind = "tenant";
        runtimeIfName = "lan0";
      };
    };
    protectedReferences = [ ];
    provenance = {
      producer = "network-realization-model";
      producerRevision = "fixture";
      transformationRuleSet = "cpm-identity-v1";
      sourceArtifactDigest = builtins.hashString "sha256" "fixture-cpm";
    };
    # Upstream coverage is delivered as declared invariants plus a coverage
    # identity bound to the canonical artifact identity. The per-path accounting
    # is recomputed from `network.data` at validation time, so the expanded
    # `upstreamCoverage` array is no longer carried by the artifact.
    coverageInvariants = {
      classification = "realized";
      transformationRule = "cpm-identity-v1";
    };
  };
  withCoverage = candidate // {
    coverageIdentity = schema.computeCoverageIdentity candidate;
  };
in
withCoverage
// {
  bundleIdentity = schema.computeBundleIdentity withCoverage;
}
