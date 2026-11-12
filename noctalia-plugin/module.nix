{ src }:
{ pkgs, ... }: {
  xdg.dataFile."noctalia/plugins/pi-noctalia".source = pkgs.runCommand "pi-noctalia-plugin" {} ''
    mkdir -p "$out/translations"
    cp ${src}/plugin.toml ${src}/service.luau ${src}/widget.luau \
      ${src}/panel.luau ${src}/presentation.luau "$out/"
    cp -r ${src}/translations/. "$out/translations/"
  '';
}
