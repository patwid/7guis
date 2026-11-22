{
  perSystem =
    { pkgs, ... }:
    {
      devShells.default = pkgs.mkShellNoCC {
        packages = builtins.attrValues {
          inherit (pkgs)
            gleam
            bun
            nodejs
            erlang
            rebar3
            inotify-tools
            gnused # CI
            ;
        };
      };
    };
}
