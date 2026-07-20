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
    upstreamCoverage = [
      {
        sourcePath = "/control_plane_model/data/example/site/runtimeTargets/router/role";
        destinationPath = "/network/data/example/site/runtimeTargets/router/role";
        classification = "realized";
        transformationRule = "cpm-identity-v1";
      }
    ];
  };
in
candidate
// {
  bundleIdentity = schema.computeBundleIdentity candidate;
}
