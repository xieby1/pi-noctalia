# pi-noctalia

Show live interactive Pi sessions in a Noctalia bar and popup.

The project has two runtime halves that share one versioned IPC contract:

- `pi-extension/` publishes bounded session snapshots from interactive Pi TUI sessions.
- `noctalia-plugin/` receives snapshots and renders the Pi Sessions bar widget and popup.

Both directories are source-only; deployment and machine-specific settings belong to the host configuration.

## Install

From the repository root, link the components into their hosts' discovery directories:

```sh
mkdir -p "$HOME/.pi/agent/extensions" "${XDG_DATA_HOME:-$HOME/.local/share}/noctalia/plugins"
ln -s "$PWD/pi-extension" "$HOME/.pi/agent/extensions/pi-noctalia"
ln -s "$PWD/noctalia-plugin" "${XDG_DATA_HOME:-$HOME/.local/share}/noctalia/plugins/pi-noctalia"
```

Enable `local/pi-noctalia` and add its `widget` to your Noctalia bar. Reload Pi and Noctalia after installation.

## Checks

From this repository (with Node.js, Luau and Noctalia on `PATH`):

```sh
node --test pi-extension/index.test.mjs
bash noctalia-plugin/check.sh
```

The first command tests lifecycle delivery, ordering, coalescing, bounded IPC and shutdown behavior. The second compiles and exercises the Luau plugin and runs Noctalia's offline plugin lint.

The Pi TUI smoke check additionally requires `pi` on `PATH`:

```sh
python3 pi-extension/smoke.py pi-extension/index.ts
```

Deployment configuration and integration checks are maintained outside this repository.
