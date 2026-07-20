{
  schema ? import ../lib/default.nix,
  bundle ? import ./valid-bundle.nix { inherit schema; },
}:

let
  candidate = {
    kind = schema.schema.platformBinding.kind;
    schemaRevision = schema.schema.platformBinding.revision;
    bundleIdentity = bundle.bundleIdentity;
    target = "nixos";
    requestScope = bundle.requestScope;
    categories = {
      interfaceIdentity.router-lan = {
        canonicalPath = "/network/data/example/site/runtimeTargets/router/interfaces/lan";
        deviceName = "lan0";
      };
      deployment.hosts.router = "fixture-host";
      secretDelivery = { };
      lifecycle.autoStart = true;
      backend.package = "fixture";
    };
    provenance = {
      producer = "network-labs";
      producerRevision = "fixture";
      sourceIdentity = "fixture-binding";
    };
  };
in
candidate
// {
  bindingIdentity = schema.computeBindingIdentity candidate;
}
