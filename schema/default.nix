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
      "upstreamCoverage"
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
