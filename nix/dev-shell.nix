{
  perSystem =
    { pkgs, ... }:
    {
      devShells.default = pkgs.mkShellNoCC {
        packages =
          builtins.attrValues {
            inherit (pkgs)
              gleam
              bun
              nodejs
              rebar3
              inotify-tools
              gnused # CI
              ;
          }
          ++ [ pkgs.beamPackages.erlang ];
      };
    };
}
