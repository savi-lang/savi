{
  description = "Savi dev environment flake";
  outputs = { self, nixpkgs }: {

    devShell.x86_64-linux = 
    with import nixpkgs { system = "x86_64-linux"; };
    let
      stdenv = clang9Stdenv; 
      fhsenv = buildFHSUserEnv.override { stdenv = stdenv; } {
        name = "savi-fhs";
        targetPkgs = pkgs: with pkgs; [
          stdenv.cc.libc_dev.dev
          clang-tools
          crystal
          llvm

          # used by Crystal
          boehmgc.dev
          libevent.dev
          pcre.dev

          # necessary for some build steps
          curl util-linux

          # dev tooling
          lldb
        ];
      };
    in
    clang9Stdenv.mkDerivation {
      name = "savi-env";
      buildInputs = with nixpkgs.legacyPackages; [
          fhsenv
      ];
      shellHook = ''
        savi-fhs
      '';
    };
  };
}
