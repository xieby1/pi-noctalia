# pi-noctalia

Show live interactive Pi sessions in a Noctalia bar and popup.

The project has two runtime halves that share one versioned IPC contract:

- `pi-extension/` publishes bounded session snapshots from interactive Pi TUI sessions.
- `noctalia-plugin/` receives snapshots and renders the Pi Sessions bar widget and popup.

The Nix modules in each component package only the runtime files. The parent `nixpkgs` configuration supplies the local source path and owns its Home Manager settings and integration checks.

## Standalone checks

From this repository:

```sh
node --test pi-extension/index.test.mjs
bash noctalia-plugin/check.sh
```

The first command tests lifecycle delivery, ordering, coalescing, bounded IPC and shutdown behavior. The second compiles and exercises the Luau plugin and runs Noctalia's offline plugin lint.

## Nix integration

The configuration repository imports `pi-extension/module.nix` and `noctalia-plugin/module.nix`, while keeping machine-specific settings such as enabled plugins and widget placement in its own repository.

The integration checks remain in the configuration repository because they evaluate its pinned Pi, Noctalia, nixpkgs and Home Manager versions.
