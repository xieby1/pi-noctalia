# Pi Sessions

A Noctalia bar widget and popup for live interactive Pi sessions.
The service receives full snapshots over plugin IPC and keeps the registry in memory.

## Display

- Horizontal bars show short names and distinct working, waiting, idle, stopped and disconnected states.
- Vertical bars use glyphs to fit the bar thickness.
- Three sessions are visible by default; `max_visible` controls the limit and `+N` opens the full list.
- Clicking π opens the panel; clicking a live Ghostty chip or panel row focuses its exact tab or split. Unfocusable chips open the panel; unfocusable panel rows are labeled and not clickable.
- π, each session chip, and +N use separate native button hover feedback; gaps between them are not clickable. Bar status glyphs remain distinct but use a neutral foreground; the popup retains status colors.
- Tooltips and the popup show the project, model, logical session ID and instance ID.
- State changes do not reorder sessions, and the bar hides when the registry is empty.

## Delivery and recovery

The service validates snapshot types, bounds and state values before storing them.
It rejects duplicate and out-of-order sequences, keeps removal tombstones, and copies only contract fields into the UI state.

After 45 seconds without a fresh snapshot an instance becomes disconnected; after five minutes it is removed.
A five-second update interval bounds the transition delay.
A restarted service starts empty and is repopulated by the publisher's next heartbeat.

The service has no file polling, daemon, database, network listener or custom IPC server.
For focus, the shared chip/panel action checks the Pi process's start time against `/proc` (including after asynchronous bus lookup), uses `busctl` to find the owning Ghostty process on the user bus, verifies its GTK `present-surface` action, and passes the full uint64 surface ID as text. This is an internal Ghostty action rather than a public CLI; a missing or changed action fails without focusing another session.

## Integration

Install this directory under `$XDG_DATA_HOME/noctalia/plugins/pi-noctalia` (default `~/.local/share/noctalia/plugins/pi-noctalia`) and configure a bar widget of type `local/pi-noctalia:widget`. Noctalia v5.3.0 or newer is required for the per-widget hover opt-out (plugin API 34). If upgrading from `local/pi-sessions:widget`, migrate saved widget types in your deployment configuration.
The user-facing label remains **Pi Sessions**.

## Checks

```sh
bash check.sh
```

This runs the isolated Luau behavior test and Noctalia's offline plugin lint.
