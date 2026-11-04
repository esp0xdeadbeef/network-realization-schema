let
  schema = import ../schema/default.nix;
  paths = import ./paths.nix;

  isNonEmptyString = value: builtins.isString value && value != "";

  fail =
    code: path: detail:
    throw "${code}: ${path}: ${detail}";

  requireAttrs =
    code: path: value:
    if builtins.isAttrs value then value else fail code path "expected attribute set";

  requireList =
    code: path: value:
    if builtins.isList value then value else fail code path "expected list";

  requireString =
    code: path: value:
    if isNonEmptyString value then value else fail code path "expected non-empty string";

  requireEqual =
    code: path: expected: observed:
    if expected == observed then
      observed
    else
      fail code path "expected ${builtins.toJSON expected}, observed ${builtins.toJSON observed}";

  forceAll = value: builtins.deepSeq value true;

  uniqueStrings =
    values:
    let
      attrs = builtins.listToAttrs (
        map (value: {
          name = value;
          value = true;
        }) values
      );
    in
    builtins.length values == builtins.length (builtins.attrNames attrs);

  startsWithSlash = value: isNonEmptyString value && builtins.substring 0 1 value == "/";

  containsForbiddenProtectedField =
    value:
    if builtins.isAttrs value then
      builtins.any (
        name:
        builtins.elem name [
          "value"
          "material"
          "plaintext"
          "cleartext"
        ]
        || containsForbiddenProtectedField value.${name}
      ) (builtins.attrNames value)
    else if builtins.isList value then
      builtins.any containsForbiddenProtectedField value
    else
      false;

  containsBindingAuthority =
    value:
    if builtins.isAttrs value then
      builtins.any (
        name:
        builtins.elem name [
          "networkAuthority"
          "firewallAuthority"
          "routingAuthority"
          "dnsAuthority"
          "natAuthority"
          "trustAuthority"
          "publicEgressAuthority"
        ]
        || containsBindingAuthority value.${name}
      ) (builtins.attrNames value)
    else if builtins.isList value then
      builtins.any containsBindingAuthority value
    else
      false;

  schemaMetadata = schema // {
    canonicalSerialization = "builtins.toJSON";
    identityAlgorithm = "sha256";
    pathFormat = "json-pointer";
  };

  schemaSetIdentity = builtins.hashString "sha256" (builtins.toJSON schemaMetadata);

  bundleIdentityPayload =
    bundle:
    builtins.removeAttrs bundle [
      "bundleIdentity"
      "validation"
    ];

  bindingIdentityPayload =
    binding:
    builtins.removeAttrs binding [
      "bindingIdentity"
      "validation"
    ];

  computeBundleIdentity =
    bundle: builtins.hashString "sha256" (builtins.toJSON (bundleIdentityPayload bundle));

  computeBindingIdentity =
    binding: builtins.hashString "sha256" (builtins.toJSON (bindingIdentityPayload binding));

  validateProtectedReferences =
    references:
    let
      refs = requireList "NR_SCHEMA_SHAPE_INVALID" "/protectedReferences" references;
      validateOne =
        index: reference:
        let
          path = "/protectedReferences/${toString index}";
          attrs = requireAttrs "NR_SCHEMA_SHAPE_INVALID" path reference;
          ref = requireString "NR_SCHEMA_SHAPE_INVALID" "${path}/reference" (attrs.reference or null);
          classification = requireString "NR_SCHEMA_SHAPE_INVALID" "${path}/classification" (
            attrs.classification or null
          );
          _classification =
            requireEqual "NR_SCHEMA_SHAPE_INVALID" "${path}/classification" "protected"
              classification;
          _material =
            if containsForbiddenProtectedField attrs then
              fail "NR_PROTECTED_VALUE_EXPOSED" path "protected material field is forbidden"
            else
              true;
        in
        builtins.deepSeq [ ref _classification _material ] true;
    in
    builtins.deepSeq (builtins.genList (index: validateOne index (builtins.elemAt refs index)) (
      builtins.length refs
    )) true;

  validateScope =
    scope: networkData:
    let
      scopeKind = scope.kind or null;
      scopeIdentity = scope.identity or null;
      sites = builtins.attrNames networkData;
    in
    if scopeKind == "complete-artifact" then
      true
    else if scopeKind == "site" then
      if builtins.length sites == 0 then
        fail "NR_SCOPE_MISMATCH" "/network/data"
          "network data is empty for site scope \"${scopeIdentity}\""
      else if builtins.length sites != 1 || builtins.elemAt sites 0 != scopeIdentity then
        fail "NR_SCOPE_MISMATCH" "/network/data"
          "site scope \"${scopeIdentity}\" does not match network data sites ${builtins.toJSON sites}"
      else
        true
    else
      fail "NR_SCOPE_MISMATCH" "/requestScope/kind" "unsupported scope kind \"${scopeKind}\"";

  # Upstream coverage accounting, computed from the artifact's own network
  # content plus the declared invariants.
  #
  # A bundle no longer ships one record per CPM leaf. It ships the invariants
  # that decide a path's classification and versioned rule, plus a
  # `coverageIdentity` bound to the canonical artifact identity. Verification
  # recomputes the same accounting from `network.data` and compares. The answer
  # is therefore identical to the expanded form, without carrying 341k rows that
  # no consumer reads.
  coverageInvariantsFor =
    bundle:
    let
      declared = bundle.coverageInvariants or { };
      attrs = requireAttrs "NR_SCHEMA_SHAPE_INVALID" "/coverageInvariants" declared;
      classification = requireString "NR_COVERAGE_INVALID" "/coverageInvariants/classification" (
        attrs.classification or null
      );
      transformationRule = requireString "NR_COVERAGE_INVALID" "/coverageInvariants/transformationRule" (
        attrs.transformationRule or null
      );
      _classification =
        if
          builtins.elem classification [
            "realized"
            "not-applicable"
            "rejected-unsupported"
          ]
        then
          true
        else
          fail "NR_COVERAGE_INVALID" "/coverageInvariants/classification" "unsupported classification";
    in
    builtins.deepSeq [ classification transformationRule _classification ] {
      inherit classification transformationRule;
    };

  # Rebuild the per-path accounting from bundle network content.
  canonicalCoverageRows =
    bundle:
    let
      invariants = coverageInvariantsFor bundle;
      records = paths.leafRecords {
        value = bundle.network.data;
        rootPath = "/control_plane_model";
      };
      stripPrefix =
        prefix: value:
        let
          plen = builtins.stringLength prefix;
        in
        if
          builtins.stringLength value >= plen
          && builtins.substring 0 plen value == prefix
        then
          builtins.substring plen (builtins.stringLength value - plen) value
        else
          fail "NR_UPSTREAM_DESTINATION_INVALID" value "source path is outside control_plane_model";
    in
    map (record: {
      sourcePath = record.path;
      destinationPath = "/network/data" + stripPrefix "/control_plane_model" record.path;
      inherit (invariants) classification transformationRule;
    }) records;

  computeCoverageIdentity =
    bundle: builtins.hashString "sha256" (builtins.toJSON (canonicalCoverageRows bundle));

  validateCoverage =
    coverage:
    let
      rows = requireList "NR_SCHEMA_SHAPE_INVALID" "/upstreamCoverage" coverage;
      validateOne =
        index: row:
        let
          path = "/upstreamCoverage/${toString index}";
          attrs = requireAttrs "NR_SCHEMA_SHAPE_INVALID" path row;
          sourcePath = requireString "NR_COVERAGE_INVALID" "${path}/sourcePath" (attrs.sourcePath or null);
          destinationPath = requireString "NR_COVERAGE_INVALID" "${path}/destinationPath" (
            attrs.destinationPath or null
          );
          classification = requireString "NR_COVERAGE_INVALID" "${path}/classification" (
            attrs.classification or null
          );
          transformationRule = requireString "NR_COVERAGE_INVALID" "${path}/transformationRule" (
            attrs.transformationRule or null
          );
          _source =
            if startsWithSlash sourcePath then
              true
            else
              fail "NR_COVERAGE_INVALID" "${path}/sourcePath" "expected JSON pointer";
          _destination =
            if startsWithSlash destinationPath then
              true
            else
              fail "NR_COVERAGE_INVALID" "${path}/destinationPath" "expected JSON pointer";
          _classification =
            if
              builtins.elem classification [
                "realized"
                "not-applicable"
                "rejected-unsupported"
              ]
            then
              true
            else
              fail "NR_COVERAGE_INVALID" "${path}/classification" "unsupported classification";
        in
        builtins.deepSeq
          [
            sourcePath
            destinationPath
            transformationRule
            _source
            _destination
            _classification
          ]
          {
            inherit sourcePath destinationPath;
          };
      validated = builtins.genList (index: validateOne index (builtins.elemAt rows index)) (
        builtins.length rows
      );
      sourcePaths = map (row: row.sourcePath) validated;
      destinationPaths = map (row: row.destinationPath) validated;
      _uniqueSources =
        if uniqueStrings sourcePaths then
          true
        else
          fail "NR_COVERAGE_INVALID" "/upstreamCoverage" "duplicate source path";
      _uniqueDestinations =
        if uniqueStrings destinationPaths then
          true
        else
          fail "NR_COVERAGE_INVALID" "/upstreamCoverage" "duplicate destination path";
    in
    builtins.deepSeq [ validated _uniqueSources _uniqueDestinations ] true;

  validateBundle =
    bundle:
    let
      candidate = requireAttrs "NR_SCHEMA_SHAPE_INVALID" "/" bundle;
      kind = requireString "NR_SCHEMA_SHAPE_INVALID" "/kind" (candidate.kind or null);
      revision = requireString "NR_SCHEMA_UNKNOWN" "/schemaRevision" (candidate.schemaRevision or null);
      identity = requireString "NR_SCHEMA_SHAPE_INVALID" "/bundleIdentity" (
        candidate.bundleIdentity or null
      );
      scope = requireAttrs "NR_SCHEMA_SHAPE_INVALID" "/requestScope" (candidate.requestScope or null);
      scopeIdentity = requireString "NR_SCHEMA_SHAPE_INVALID" "/requestScope/identity" (
        scope.identity or null
      );
      sources = requireAttrs "NR_SCHEMA_SHAPE_INVALID" "/sources" (candidate.sources or null);
      cpmSource = requireAttrs "NR_SCHEMA_SHAPE_INVALID" "/sources/cpm" (sources.cpm or null);
      sourceIdentity = requireString "NR_SCHEMA_SHAPE_INVALID" "/sources/cpm/identity" (
        cpmSource.identity or null
      );
      sourceDigest = requireString "NR_SCHEMA_SHAPE_INVALID" "/sources/cpm/digest" (
        cpmSource.digest or null
      );
      network = requireAttrs "NR_SCHEMA_SHAPE_INVALID" "/network" (candidate.network or null);
      networkData = requireAttrs "NR_SCHEMA_SHAPE_INVALID" "/network/data" (network.data or null);
      provenance = requireAttrs "NR_PROVENANCE_INVALID" "/provenance" (candidate.provenance or null);
      producer = requireString "NR_PROVENANCE_INVALID" "/provenance/producer" (
        provenance.producer or null
      );
      producerRevision = requireString "NR_PROVENANCE_INVALID" "/provenance/producerRevision" (
        provenance.producerRevision or null
      );
      transformationRuleSet = requireString "NR_PROVENANCE_INVALID" "/provenance/transformationRuleSet" (
        provenance.transformationRuleSet or null
      );
      _kind = requireEqual "NR_SCHEMA_SHAPE_INVALID" "/kind" schema.bundle.kind kind;
      _revision = requireEqual "NR_SCHEMA_UNKNOWN" "/schemaRevision" schema.bundle.revision revision;
      expectedIdentity = computeBundleIdentity candidate;
      _identity = requireEqual "NR_ARTIFACT_DIGEST_MISMATCH" "/bundleIdentity" expectedIdentity identity;
      _scope = validateScope scope networkData;
      _protected = validateProtectedReferences (candidate.protectedReferences or null);
      # Expansion is optional now. When it is present it must agree with the
      # accounting recomputed from network content, so the two forms can never
      # diverge; when it is absent only the recomputed form is checked.
      _expanded =
        if candidate ? upstreamCoverage then
          builtins.deepSeq (validateCoverage candidate.upstreamCoverage) (
            let
              expanded = map (row: {
                sourcePath = row.sourcePath or null;
                destinationPath = row.destinationPath or null;
                classification = row.classification or null;
                transformationRule = row.transformationRule or null;
              }) candidate.upstreamCoverage;
              recomputed = canonicalCoverageRows candidate;
            in
            if builtins.toJSON expanded == builtins.toJSON recomputed then
              true
            else
              fail "NR_COVERAGE_IDENTITY_MISMATCH" "/upstreamCoverage"
                "expanded coverage disagrees with the recomputed accounting"
          )
        else
          true;
      declaredCoverageIdentity = requireString "NR_COVERAGE_INVALID" "/coverageIdentity" (
        candidate.coverageIdentity or null
      );
      _coverageIdentity =
        if declaredCoverageIdentity == computeCoverageIdentity candidate then
          true
        else
          fail "NR_COVERAGE_IDENTITY_MISMATCH" "/coverageIdentity"
            "recomputed accounting disagrees with the delivered coverage identity";
    in
    builtins.deepSeq
      [
        _kind
        _revision
        _identity
        _scope
        scopeIdentity
        sourceIdentity
        sourceDigest
        networkData
        producer
        producerRevision
        transformationRuleSet
        _protected
        _expanded
        _coverageIdentity
      ]
      {
        valid = true;
        artifactKind = schema.bundle.kind;
        schemaRevision = schema.bundle.revision;
        artifactIdentity = identity;
        inherit schemaSetIdentity scopeIdentity;
      };

  validatePlatformBinding =
    binding:
    let
      candidate = requireAttrs "NR_PLATFORM_BINDING_SCHEMA_INVALID" "/" binding;
      unknownTopLevel = builtins.filter (
        name: !(builtins.elem name schema.platformBinding.allowedTopLevel)
      ) (builtins.attrNames candidate);
      kind = requireString "NR_PLATFORM_BINDING_SCHEMA_INVALID" "/kind" (candidate.kind or null);
      revision = requireString "NR_PLATFORM_BINDING_SCHEMA_INVALID" "/schemaRevision" (
        candidate.schemaRevision or null
      );
      identity = requireString "NR_PLATFORM_BINDING_SCHEMA_INVALID" "/bindingIdentity" (
        candidate.bindingIdentity or null
      );
      bundleIdentity = requireString "NR_PLATFORM_BINDING_IDENTITY_MISMATCH" "/bundleIdentity" (
        candidate.bundleIdentity or null
      );
      target = requireString "NR_PLATFORM_BINDING_TARGET_MISMATCH" "/target" (candidate.target or null);
      scope = requireAttrs "NR_PLATFORM_BINDING_SCHEMA_INVALID" "/requestScope" (
        candidate.requestScope or null
      );
      scopeIdentity = requireString "NR_PLATFORM_BINDING_SCHEMA_INVALID" "/requestScope/identity" (
        scope.identity or null
      );
      categories = requireAttrs "NR_PLATFORM_BINDING_SCHEMA_INVALID" "/categories" (
        candidate.categories or null
      );
      categoryNames = builtins.attrNames categories;
      unknownCategories = builtins.filter (
        name: !(builtins.elem name schema.platformBinding.allowedCategories)
      ) categoryNames;
      provenance = requireAttrs "NR_PLATFORM_BINDING_SCHEMA_INVALID" "/provenance" (
        candidate.provenance or null
      );
      producer = requireString "NR_PLATFORM_BINDING_SCHEMA_INVALID" "/provenance/producer" (
        provenance.producer or null
      );
      producerRevision =
        requireString "NR_PLATFORM_BINDING_SCHEMA_INVALID" "/provenance/producerRevision"
          (provenance.producerRevision or null);
      _kind = requireEqual "NR_PLATFORM_BINDING_SCHEMA_INVALID" "/kind" schema.platformBinding.kind kind;
      _revision =
        requireEqual "NR_PLATFORM_BINDING_SCHEMA_INVALID" "/schemaRevision" schema.platformBinding.revision
          revision;
      _categories =
        if unknownCategories == [ ] then
          true
        else
          fail "NR_PLATFORM_BINDING_CATEGORY_UNKNOWN" "/categories" (builtins.toJSON unknownCategories);
      _authority =
        if containsBindingAuthority categories then
          fail "NR_PLATFORM_BINDING_AUTHORITY" "/categories" "network authority field is forbidden"
        else
          true;
      _sidecars =
        if unknownTopLevel == [ ] then
          true
        else
          fail "NR_PLATFORM_SIDECAR_STACKED" "/"
            "one normalized platform-binding bundle is allowed; unexpected top-level fields ${builtins.toJSON unknownTopLevel}";
      _protected =
        if containsForbiddenProtectedField (categories.secretDelivery or { }) then
          fail "NR_PROTECTED_VALUE_EXPOSED" "/categories/secretDelivery"
            "protected material field is forbidden"
        else
          true;
      expectedIdentity = computeBindingIdentity candidate;
      _identity =
        requireEqual "NR_PLATFORM_BINDING_IDENTITY_MISMATCH" "/bindingIdentity" expectedIdentity
          identity;
    in
    builtins.deepSeq
      [
        _kind
        _revision
        _categories
        _sidecars
        _authority
        _protected
        _identity
        bundleIdentity
        target
        scopeIdentity
        producer
        producerRevision
      ]
      {
        valid = true;
        artifactKind = schema.platformBinding.kind;
        schemaRevision = schema.platformBinding.revision;
        artifactIdentity = identity;
        inherit
          bundleIdentity
          target
          schemaSetIdentity
          scopeIdentity
          ;
        categoryNames = categoryNames;
      };

  validatePlatformBindingCanonical =
    binding: canonicalBundle:
    let
      _envelope = validatePlatformBinding binding;
      candidate = requireAttrs "NR_PLATFORM_BINDING_SCHEMA_INVALID" "/" binding;
      categories = requireAttrs "NR_PLATFORM_BINDING_SCHEMA_INVALID" "/categories" (
        candidate.categories or null
      );
      bundleForResolution = canonicalBundle;
      expectedTarget = canonicalBundle.target or canonicalBundle.expectedTarget or null;

      # NR-BIND-N4: target must match
      _target =
        if expectedTarget != null then
          requireEqual "NR_PLATFORM_BINDING_TARGET_MISMATCH" "/target" expectedTarget
            (candidate.target or null)
        else
          true;

      # NR-BIND-N6: bundle identity must match canonical
      canonicalIdentity =
        if canonicalBundle ? bundleIdentity then
          canonicalBundle.bundleIdentity
        else if canonicalBundle ? artifactIdentity then
          canonicalBundle.artifactIdentity
        else
          null;
      _bundleIdentity =
        if canonicalIdentity != null then
          requireEqual "NR_PLATFORM_BINDING_IDENTITY_MISMATCH" "/bundleIdentity" canonicalIdentity
            (candidate.bundleIdentity or null)
        else
          true;

      # NR-BIND-N5: every canonicalPath reference must exist in the bundle data
      collectCanonicalPaths =
        value:
        if builtins.isAttrs value then
          builtins.concatMap (
            name:
            if name == "canonicalPath" && builtins.isString value.${name} then
              [ value.${name} ]
            else
              collectCanonicalPaths value.${name}
          ) (builtins.attrNames value)
        else if builtins.isList value then
          builtins.concatMap collectCanonicalPaths value
        else
          [ ];

      # Resolve a JSON pointer path against attrs
      resolvePointer =
        path: attrs:
        let
          splitPath =
            s:
            let
              slash = builtins.match "([^/]*)/(.*)" s;
            in
            if s == "" then [ ] else if slash == null then [ s ] else [ (builtins.elemAt slash 0) ] ++ splitPath (
              builtins.elemAt slash 1
            );
          stripLeadingSlash =
            s:
            if builtins.substring 0 1 s == "/" then builtins.substring 1 (builtins.stringLength s - 1) s else s;
          segments = splitPath (stripLeadingSlash path);
          resolve =
            segs: current:
            if segs == [ ] then
              true
            else if !builtins.isAttrs current then
              false
            else
              resolve (builtins.tail segs) (current.${builtins.head segs} or null);
        in
        resolve segments attrs;

      canonicalRefs = collectCanonicalPaths categories;
      _refs = builtins.deepSeq (
        builtins.map (
          ref:
          if resolvePointer ref bundleForResolution then
            true
          else
            fail "NR_PLATFORM_BINDING_REFERENCE_MISSING" ref
              "canonical path not found in bundle"
        ) canonicalRefs
      ) true;
    in
    builtins.deepSeq
      [
        _envelope
        _target
        _bundleIdentity
        _refs
        (candidate.target or null)
        (candidate.bundleIdentity or null)
      ]
      (_envelope
        // {
          canonicalBundleIdentity = canonicalIdentity;
          expectedTarget = expectedTarget;
          validatedRefs = canonicalRefs;
        });

  assertBundle = bundle: builtins.deepSeq (validateBundle bundle) bundle;

  assertPlatformBinding = binding: builtins.deepSeq (validatePlatformBinding binding) binding;
in
{
  inherit
    assertBundle
    assertPlatformBinding
    bindingIdentityPayload
    bundleIdentityPayload
    canonicalCoverageRows
    computeBindingIdentity
    computeBundleIdentity
    computeCoverageIdentity
    coverageInvariantsFor
    forceAll
    paths
    schema
    schemaMetadata
    schemaSetIdentity
    validateBundle
    validatePlatformBinding
    validatePlatformBindingCanonical
    validateScope
    ;
}
