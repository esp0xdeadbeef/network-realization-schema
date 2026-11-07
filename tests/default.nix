{
  schema ? import ../lib/default.nix,
}:

let
  validBundle = import ../examples/valid-bundle.nix { inherit schema; };
  validBinding = import ../examples/valid-platform-binding.nix {
    inherit schema;
    bundle = validBundle;
  };

  succeeds = value: (builtins.tryEval (builtins.deepSeq value true)).success;

  fails = value: !(succeeds value);

  withBundleIdentity =
    bundle:
    (builtins.removeAttrs bundle [ "bundleIdentity" ])
    // {
      bundleIdentity = schema.computeBundleIdentity (builtins.removeAttrs bundle [ "bundleIdentity" ]);
    };

  withCoverageAndIdentity =
    bundle:
    let
      withoutIdentities = builtins.removeAttrs bundle [ "bundleIdentity" "coverageIdentity" ];
      withCoverage = withoutIdentities // {
        coverageIdentity = schema.computeCoverageIdentity withoutIdentities;
      };
    in
    withCoverage // { bundleIdentity = schema.computeBundleIdentity withCoverage; };

  withBindingIdentity =
    binding:
    (builtins.removeAttrs binding [ "bindingIdentity" ])
    // {
      bindingIdentity = schema.computeBindingIdentity (
        builtins.removeAttrs binding [ "bindingIdentity" ]
      );
    };

  unknownRevision = withBundleIdentity (
    validBundle
    // {
      schemaRevision = "network-realization/unknown";
    }
  );

  invalidShape = withBundleIdentity (builtins.removeAttrs validBundle [ "requestScope" ]);

  # A producer that adds a non-site value next to the enterprise map is
  # inventing network content; the bundle shape must reject it (FS-310 canonical
  # bundle, no renderer-invented defaults).
  inventedNetworkData = withBundleIdentity (
    validBundle
    // {
      network = validBundle.network // {
        data = validBundle.network.data // {
          invented = true;
        };
      };
    }
  );

  # Producers may hand over the control-plane build result, which wraps the CPM
  # envelope as `{ control_plane_model = <envelope>; ... }`. The schema validates
  # the enterprise map inside that envelope, and still rejects invented content
  # there.
  wrappedNetworkData = withCoverageAndIdentity (
    validBundle
    // {
      network = validBundle.network // {
        data = {
          control_plane_model = {
            data = validBundle.network.data;
            version = 1;
          };
          endpointInventory = { };
        };
      };
    }
  );

  inventedWrappedNetworkData = withCoverageAndIdentity (
    validBundle
    // {
      network = validBundle.network // {
        data = {
          control_plane_model = {
            data = validBundle.network.data // { invented = true; };
            version = 1;
          };
        };
      };
    }
  );

  scopeEscape = withBundleIdentity (
    validBundle
    // {
      requestScope = validBundle.requestScope // {
        identity = "";
      };
    }
  );

  scopeMismatch = withBundleIdentity (
    validBundle
    // {
      requestScope = validBundle.requestScope // {
        kind = "site";
        identity = "nonexistent";
      };
    }
  );

  invalidProvenance = withBundleIdentity (
    validBundle
    // {
      provenance = builtins.removeAttrs validBundle.provenance [ "transformationRuleSet" ];
    }
  );

  # The expanded array is optional now, but when a bundle carries one it must
  # agree with the accounting recomputed from network content. A duplicated row
  # is exactly such a disagreement, so this stays a coverage failure.
  duplicateCoverage = withBundleIdentity (
    validBundle
    // {
      upstreamCoverage = schema.canonicalCoverageRows validBundle
        ++ schema.canonicalCoverageRows validBundle;
    }
  );

  # A coverage identity that no longer describes the bundle's network content.
  staleCoverageIdentity = withBundleIdentity (
    validBundle
    // {
      coverageIdentity = builtins.hashString "sha256" "not-the-real-accounting";
    }
  );

  # An artifact that ships the expanded enumeration instead of deriving it.
  expandedCoverageOnly = withBundleIdentity (
    (builtins.removeAttrs validBundle [ "coverageIdentity" ])
    // {
      upstreamCoverage = schema.canonicalCoverageRows validBundle;
    }
  );

  protectedMaterial = withBundleIdentity (
    validBundle
    // {
      protectedReferences = [
        {
          reference = "/run/secrets/example";
          classification = "protected";
          value = "must-not-appear";
        }
      ];
    }
  );

  bindingAuthority = withBindingIdentity (
    validBinding
    // {
      categories = validBinding.categories // {
        deployment = validBinding.categories.deployment // {
          networkAuthority.routes = [ "default" ];
        };
      };
    }
  );

  stackedSidecar = validBinding // {
    extraPlatformBinding = { };
  };

  digestMismatch = validBundle // {
    network = validBundle.network // {
      data = validBundle.network.data // {
        changed = true;
      };
    };
  };

  unknownCategory = withBindingIdentity (
    validBinding
    // {
      categories = validBinding.categories // {
        arbitrarySidecar = { };
      };
    }
  );

  bindingProtectedMaterial = withBindingIdentity (
    validBinding
    // {
      categories = validBinding.categories // {
        secretDelivery = {
          privateKey = {
            value = "must-not-appear";
          };
        };
      };
    }
  );

  # SMS-030 negatives

  bindingSchemaInvalid =
    (builtins.removeAttrs validBinding [ "kind" ])
    // {
      bindingIdentity = schema.computeBindingIdentity (builtins.removeAttrs validBinding [ "kind" ]);
    };

  bindingTargetMismatch = (
    builtins.removeAttrs validBinding [ "bindingIdentity" ]
    // {
      target = "openconfig";
    }
  );

  bindingReferenceMissing = validBinding;

  bindingBundleIdentityMismatch = validBinding;

  canonicalBundleForRefs = validBundle;

  staleBundleForIdentity = {
    bundleIdentity = "sha256:deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef";
  };

  checks = [
    (succeeds (schema.validateBundle validBundle))
    (succeeds (schema.validatePlatformBinding validBinding))
    (fails (schema.validateBundle unknownRevision))
    (fails (schema.validateBundle invalidShape))
    (fails (schema.validateBundle inventedNetworkData))
    (succeeds (schema.validateBundle wrappedNetworkData))
    (fails (schema.validateBundle inventedWrappedNetworkData))
    (fails (schema.validateBundle scopeEscape))
    (fails (schema.validateBundle scopeMismatch))
    (fails (schema.validateBundle invalidProvenance))
    (fails (schema.validateBundle duplicateCoverage))
    (fails (schema.validateBundle staleCoverageIdentity))
    (fails (schema.validateBundle expandedCoverageOnly))
    (fails (schema.validateBundle protectedMaterial))
    (fails (schema.validatePlatformBinding bindingAuthority))
    (fails (schema.validatePlatformBinding stackedSidecar))
    (fails (schema.validateBundle digestMismatch))
    (fails (schema.validatePlatformBinding unknownCategory))
    (fails (schema.validatePlatformBinding bindingProtectedMaterial))
    (fails (schema.validatePlatformBinding bindingSchemaInvalid))
    (fails (schema.validatePlatformBindingCanonical bindingTargetMismatch { bundleIdentity = validBundle.bundleIdentity; expectedTarget = "nixos"; }))
    (fails (schema.validatePlatformBindingCanonical bindingReferenceMissing { bundleIdentity = validBundle.bundleIdentity; network.data = { }; }))
    (fails (schema.validatePlatformBindingCanonical bindingBundleIdentityMismatch staleBundleForIdentity))
    (succeeds (schema.validatePlatformBindingCanonical validBinding (validBundle // { expectedTarget = "nixos"; })))
    (
      builtins.length (
        schema.paths.pathsFor {
          value = validBundle.network;
          rootPath = "/network";
        }
      ) > 0
    )
  ];
in
assert builtins.all (value: value) checks;
true
