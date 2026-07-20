{
  description = "Pinned canonical network realization schema contract";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    {
      self,
      nixpkgs,
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
      lib = schemaLib;

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
