{ src }:
{ pkgs, lib, ... }: lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
  home.file.".pi/agent/extensions/pi-noctalia".source = lib.fileset.toSource {
    root = src;
    fileset = lib.fileset.unions [
      (src + "/index.ts")
      (src + "/transport.ts")
    ];
  };
}
