{
  perSystem =
    { config, pkgs, ... }:
    {
      devShells = {
        gleam = pkgs.mkShellNoCC {
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

        elm = pkgs.mkShellNoCC {
          packages =
            builtins.attrValues {
              inherit (pkgs.elmPackages)
                elm
                elm-format
                elm-test
                ;
              inherit (pkgs)
                esbuild
                gnused # CI
                ;
            };
        };

        default = pkgs.mkShellNoCC {
          inputsFrom = [
            config.devShells.gleam
            config.devShells.elm
          ];
        };
      };
    };
}
