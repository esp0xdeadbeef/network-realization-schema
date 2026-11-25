{
  description = "Pinned canonical network realization schema contract";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  # Producer inputs, for the cross-repository contract tests ONLY.
  #
  # tests/test-canonical-set-drift.sh and tests/test-canonical-collection-loss.sh
  # compare this repository's closed `canonicalCollections` set against what the
  # real producer actually publishes. Neither direction is visible from inside this
  # repository, so the comparison needs a producer -- and without one the tests
  # used to SKIP, which CI (correctly) reports as a failure: a skipped case is not a
  # verdict.
  #
  # Pinning them here is what makes CI materialise them: the tests-matrix workflow
  # checks out every esp0xdeadbeef github input of flake.lock beside the workspace.
  # The schema itself still does not CONSUME producer output -- nothing in
  # lib/ or schema/ imports these; they are read by the audit tests and by nothing
  # else. There is no dependency cycle: network-control-plane-model depends on
  # network-forwarding-model and network-labs, neither of which depends on the
  # schema.
  inputs.network-control-plane-model.url = "github:esp0xdeadbeef/network-control-plane-model";
  inputs.network-control-plane-model.inputs.nixpkgs.follows = "nixpkgs";
  inputs.network-control-plane-model.inputs.network-labs.follows = "network-labs";
  inputs.network-labs.url = "github:esp0xdeadbeef/network-labs";
  inputs.network-labs.inputs.nixpkgs.follows = "nixpkgs";

  outputs =
    {
      self,
      nixpkgs,
      network-control-plane-model,
      network-labs,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems f;
      schemaLib = import ./lib/default.nix;
      diagnosticCases = import ./tests/diagnostics.nix {
        schema = schemaLib;
      };
      testsPass = import ./tests/default.nix {
        schema = schemaLib;
      };
    in
    {

      # THE ENVIRONMENT THE TESTS NEED, DECLARED IN THE REPO-ROOT FLAKE.
      #
      # Every suite here shells out to nix, jq and git, and some use rg, ssh and
      # python3. Until this existed those came from the runner image plus ad-hoc
      # `curl`s in the workflow, so the environment was implicit: no derivation
      # described it, nothing could cache it coherently, and each job re-fetched the
      # same bytes.
      #
      # `nix develop` and `nix build .#devShells.<sys>.default` are the two consumers.
      # CI reads the PATH that `nix print-dev-env` reports and exports it, so the tools
      # a test runs are the ones declared here and nothing is installed outside it.
      #
      # Deliberately no `pkgs.nix`: CI installs its own Nix, and two versions evaluate
      # the same flake to different derivations -- which silently breaks every cache.
      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            name = "network-tests";
            packages = [
              pkgs.git
              pkgs.jq
              pkgs.openssh
              pkgs.python3
              pkgs.ripgrep
              pkgs.zstd
            ];
          };
        }
      );

      lib = schemaLib;

      # Where the producer audit tests find the producer and its example.
      #
      # The tests run as plain shell, so they need PATHS, not flake attrs. These
      # are the pinned input stores: resolved from flake.lock, reproducible, and
      # present in CI because the workflow materialises them. The tests still
      # prefer a sibling checkout when one exists (a developer's ../network-*),
      # because that is the tree they are about to change.
      producerAuditRoots = {
        inherit network-control-plane-model network-labs;
        canonicalExample = network-labs + "/examples/wireguard-provider-overlay";
      };

      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          manifest = pkgs.writeText "network-realization-schema.json" (
            builtins.toJSON (
              schemaLib.schemaMetadata
              // {
                schemaSetIdentity = schemaLib.schemaSetIdentity;
              }
            )
          );
        in
        {
          default = manifest;
          schema-manifest = manifest;
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          diagnosticChecks = nixpkgs.lib.mapAttrs' (
            name: testCase:
            nixpkgs.lib.nameValuePair "diagnostic-${name}" (
              pkgs.runCommand "network-realization-schema-diagnostic-${name}" { } ''
                  export HOME="$TMPDIR/home"
                  export NIX_CONFIG='flake-registry ='
                  mkdir -p "$HOME"
                  if ${pkgs.nix}/bin/nix-instantiate \
                  --eval \
                  --strict \
                  --attr ${name}.value \
                    ${self}/tests/diagnostics.nix \
                  >stdout 2>stderr
                then
                  echo "negative case ${name} unexpectedly succeeded" >&2
                  exit 1
                fi
                  if ! grep -F -- ${builtins.toJSON testCase.expected} stderr
                  then
                    echo "negative case ${name} emitted the wrong diagnostic" >&2
                    cat stderr >&2
                    exit 1
                  fi
                touch "$out"
              ''
            )
          ) diagnosticCases;
        in
        assert testsPass;
        {
          schema-contract = pkgs.runCommand "network-realization-schema-contract" { } ''
            mkdir -p "$out"
            cp "${self.packages.${system}.schema-manifest}" "$out/schema.json"
          '';
        }
        // diagnosticChecks
      );

      formatter = forAllSystems (system: (import nixpkgs { inherit system; }).nixfmt-tree);
    };
}
