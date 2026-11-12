{ src }:
{ lib, ... }: {
  xdg.dataFile."noctalia/plugins/pi-noctalia".source = lib.fileset.toSource {
    root = src;
    fileset = lib.fileset.unions [
      (src + "/plugin.toml")
      (src + "/service.luau")
      (src + "/widget.luau")
      (src + "/panel.luau")
      (src + "/presentation.luau")
      (src + "/translations")
    ];
  };
}
