{ src }:
{ pkgs, lib, ... }: lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
  home.file.".pi/agent/extensions/pi-noctalia".source = pkgs.runCommand "pi-noctalia-extension" {} ''
    mkdir -p "$out"
    cp ${src}/index.ts ${src}/transport.ts "$out/"
  '';
}
