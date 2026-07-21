{
  schema ? import ../lib/default.nix,
}:

let
  validBundle = import ../examples/valid-bundle.nix { inherit schema; };
  validBinding = import ../examples/valid-platform-binding.nix {
    inherit schema;
    bundle = validBundle;
  };

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
in
{
  unknownRevision = {
    expected = "NR_SCHEMA_UNKNOWN: /schemaRevision: expected";
    value = schema.validateBundle (
      withBundleIdentity (
        validBundle
        // {
          schemaRevision = "network-realization/unknown";
        }
      )
    );
  };

  invalidShape = {
    expected = "NR_SCHEMA_SHAPE_INVALID: /requestScope: expected attribute set";
    value = schema.validateBundle (
      withBundleIdentity (builtins.removeAttrs validBundle [ "requestScope" ])
    );
  };

  scopeEscape = {
    expected = "NR_SCHEMA_SHAPE_INVALID: /requestScope/identity: expected non-empty string";
    value = schema.validateBundle (
      withBundleIdentity (
        validBundle
        // {
          requestScope = validBundle.requestScope // {
            identity = "";
          };
        }
      )
    );
  };

  scopeMismatch = {
    expected = ''NR_SCOPE_MISMATCH: /network/data: site scope "nonexistent" does not match network data sites'';
    value = schema.validateBundle (
      withBundleIdentity (
        validBundle
        // {
          requestScope = validBundle.requestScope // {
            kind = "site";
            identity = "nonexistent";
          };
        }
      )
    );
  };

  provenanceIncomplete = {
    expected = "NR_PROVENANCE_INVALID: /provenance/transformationRuleSet: expected non-empty string";
    value = schema.validateBundle (
      withBundleIdentity (
        validBundle
        // {
          provenance = builtins.removeAttrs validBundle.provenance [ "transformationRuleSet" ];
        }
      )
    );
  };

  duplicateCoverage = {
    expected = "NR_COVERAGE_INVALID: /upstreamCoverage: duplicate source path";
    value = schema.validateBundle (
      withBundleIdentity (
        validBundle
        // {
          upstreamCoverage = validBundle.upstreamCoverage ++ validBundle.upstreamCoverage;
        }
      )
    );
  };

  protectedMaterial = {
    expected = "NR_PROTECTED_VALUE_EXPOSED: /protectedReferences/0: protected material field is forbidden";
    value = schema.validateBundle (
      withBundleIdentity (
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
      )
    );
  };

  bindingAuthority = {
    expected = "NR_PLATFORM_BINDING_AUTHORITY: /categories: network authority field is forbidden";
    value = schema.validatePlatformBinding (
      withBindingIdentity (
        validBinding
        // {
          categories = validBinding.categories // {
            deployment = validBinding.categories.deployment // {
              networkAuthority.routes = [ "default" ];
            };
          };
        }
      )
    );
  };

  stackedSidecar = {
    expected = "NR_PLATFORM_SIDECAR_STACKED: /: one normalized platform-binding bundle is allowed";
    value = schema.validatePlatformBinding (
      validBinding
      // {
        extraPlatformBinding = { };
      }
    );
  };

  digestMismatch = {
    expected = "NR_ARTIFACT_DIGEST_MISMATCH: /bundleIdentity: expected";
    value = schema.validateBundle (
      validBundle
      // {
        network = validBundle.network // {
          data = validBundle.network.data // {
            changed = true;
          };
        };
      }
    );
  };

  unknownCategory = {
    expected = "NR_PLATFORM_BINDING_CATEGORY_UNKNOWN: /categories:";
    value = schema.validatePlatformBinding (
      withBindingIdentity (
        validBinding
        // {
          categories = validBinding.categories // {
            arbitrarySidecar = { };
          };
        }
      )
    );
  };

  bindingProtectedMaterial = {
    expected = "NR_PROTECTED_VALUE_EXPOSED: /categories/secretDelivery: protected material field is forbidden";
    value = schema.validatePlatformBinding (
      withBindingIdentity (
        validBinding
        // {
          categories = validBinding.categories // {
            secretDelivery.privateKey.value = "must-not-appear";
          };
        }
      )
    );
  };
}
