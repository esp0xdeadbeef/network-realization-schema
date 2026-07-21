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

  duplicateCoverage = withBundleIdentity (
    validBundle
    // {
      upstreamCoverage = validBundle.upstreamCoverage ++ validBundle.upstreamCoverage;
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

  checks = [
    (succeeds (schema.validateBundle validBundle))
    (succeeds (schema.validatePlatformBinding validBinding))
    (fails (schema.validateBundle unknownRevision))
    (fails (schema.validateBundle invalidShape))
    (fails (schema.validateBundle scopeEscape))
    (fails (schema.validateBundle scopeMismatch))
    (fails (schema.validateBundle invalidProvenance))
    (fails (schema.validateBundle duplicateCoverage))
    (fails (schema.validateBundle protectedMaterial))
    (fails (schema.validatePlatformBinding bindingAuthority))
    (fails (schema.validatePlatformBinding stackedSidecar))
    (fails (schema.validateBundle digestMismatch))
    (fails (schema.validatePlatformBinding unknownCategory))
    (fails (schema.validatePlatformBinding bindingProtectedMaterial))
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
