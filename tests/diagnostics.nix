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
  unknownBundleExtension = {
    expected = "NR_SCHEMA_SHAPE_INVALID: /: unknown bundle extension fields";
    value = schema.validateBundle (
      withBundleIdentity (
        validBundle
        // {
          # A producer must not smuggle unvalidated artifact content (for
          # example a second platform-binding sidecar) past the schema.
          platformBinding = {
            kind = "network-platform-binding-bundle";
            target = "openconfig";
          };
        }
      )
    );
  };

  # `canonical` is a closed set. A producer that publishes a collection the
  # schema does not name is widening the renderer contract on its own, which is
  # the same defect as an unknown top-level field one level down.
  unknownCanonicalCollection = {
    expected = "NR_SCHEMA_SHAPE_INVALID: /canonical: unknown canonical collections";
    value = schema.validateBundle (
      withBundleIdentity (
        validBundle
        // {
          canonical = {
            canonicalInterfaces = [ ];
            canonicalInventedByProducer = [ ];
          };
        }
      )
    );
  };

  # A canonical collection must be mappable. A scalar is not a collection, and
  # a renderer that received one would have to reconstruct the objects itself --
  # exactly the invention the boundary forbids.
  canonicalCollectionShape = {
    expected = "NR_SCHEMA_SHAPE_INVALID: /canonical/canonicalRoutes: expected a list or an attribute set";
    value = schema.validateBundle (
      withBundleIdentity (
        validBundle
        // {
          canonical = {
            canonicalRoutes = "not-a-collection";
          };
        }
      )
    );
  };

  # One canonical object is one attribute set. A bare string in the list cannot
  # carry identity, type or path, so it would force the renderer to invent them.
  # A collection must be a list or an attribute set. A scalar is neither, and a
  # renderer that received one would have to reconstruct the objects itself --
  # exactly the invention the boundary forbids.

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
          upstreamCoverage =
            schema.canonicalCoverageRows validBundle ++ schema.canonicalCoverageRows validBundle;
        }
      )
    );
  };

  staleCoverageIdentity = {
    expected = "NR_COVERAGE_IDENTITY_MISMATCH: /coverageIdentity: recomputed accounting disagrees with the delivered coverage identity";
    value = schema.validateBundle (
      withBundleIdentity (
        validBundle
        // {
          coverageIdentity = builtins.hashString "sha256" "not-the-real-accounting";
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

  # FS-161-HDS-010-SDS-010-SMS-030 seeded negatives (NR-BIND-N1, N4, N5, N6)

  bindingSchemaInvalid = {
    expected = "NR_PLATFORM_BINDING_SCHEMA_INVALID: /kind: expected";
    value = schema.validatePlatformBinding (
      (builtins.removeAttrs validBinding [ "kind" ])
      // {
        bindingIdentity = schema.computeBindingIdentity (builtins.removeAttrs validBinding [ "kind" ]);
      }
    );
  };

  bindingTargetMismatch = {
    expected = "NR_PLATFORM_BINDING_TARGET_MISMATCH: /target: expected";
    value = schema.validatePlatformBindingCanonical
      (builtins.removeAttrs validBinding [ "bindingIdentity" ]
        // {
          target = "openconfig";
          bindingIdentity = schema.computeBindingIdentity (
            builtins.removeAttrs validBinding [ "bindingIdentity" ] // {
              target = "openconfig";
            }
          );
        })
      { bundleIdentity = validBundle.bundleIdentity; expectedTarget = "nixos"; };
  };

  bindingReferenceMissing = {
    expected = "NR_PLATFORM_BINDING_REFERENCE_MISSING:";
    value = schema.validatePlatformBindingCanonical
      validBinding
      { bundleIdentity = validBundle.bundleIdentity; network.data = { }; };
  };

  bindingBundleIdentityMismatch = {
    expected = "NR_PLATFORM_BINDING_IDENTITY_MISMATCH: /bundleIdentity: expected";
    value = schema.validatePlatformBindingCanonical
      validBinding
      { bundleIdentity = "sha256:deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"; };
  };

  # The `deployment` category names the deployment facts a renderer may read
  # instead of reaching into the plain CPM. That is the whole reason it exists:
  # network-renderer-access-endpoint-nixos needs `endpointAssignment` (bridge,
  # runtimeAddressAssignments) and had no canonical home for it, so it read
  # control_plane_model and failed RR_RAW_CPM_INPUT.
  #
  # A category shape that accepts anything it is handed would not close that: a
  # renderer still could not tell a modelled fact from an invented one. This
  # asserts the shape rejects a field no category names.
  deploymentCategoryRejectsUnknownField = {
    # Reported as an unknown category: category entries are dotted keys, so a
    # fact the schema does not name under `deployment` presents as a category of
    # its own. That is the stronger outcome -- the schema refuses it at the
    # category level, before any renderer can read it -- and it is why the
    # negative case is worth having: without the shape list, a producer could
    # invent `deployment.anything` and every consumer would treat it as a
    # modelled deployment fact.
    expected = "NR_PLATFORM_BINDING_CATEGORY_UNKNOWN";
    value = schema.validatePlatformBinding (
      withBindingIdentity (
        validBinding
        // {
          # Dotted-key form, which is what the binding format actually uses
          # (examples/valid-platform-binding.nix: `deployment.hosts.router`).
          # A nested mutation here would be invisible to the shape check and the
          # negative case would pass for the wrong reason.
          categories = (validBinding.categories or { }) // {
            "deployment.inventedDeploymentFact" = { anything = true; };
          };
        }
      )
    );
  };
}
