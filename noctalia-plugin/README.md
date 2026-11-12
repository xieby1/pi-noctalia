# Pi Sessions

A Noctalia bar widget and popup for live interactive Pi sessions.
The service receives full snapshots over plugin IPC and keeps the registry in memory.

## Display

- Horizontal bars show short names and distinct working, waiting, idle, stopped and disconnected states.
- Vertical bars use glyphs to fit the bar thickness.
- Three sessions are visible by default; `max_visible` controls the limit and `+N` opens the full list.
- Tooltips and the popup show the project, model, logical session ID and instance ID.
- State changes do not reorder sessions, and the bar hides when the registry is empty.

## Delivery and recovery

The service validates snapshot types, bounds and state values before storing them.
It rejects duplicate and out-of-order sequences, keeps removal tombstones, and copies only contract fields into the UI state.

After 45 seconds without a fresh snapshot an instance becomes disconnected; after five minutes it is removed.
A five-second update interval bounds the transition delay.
A restarted service starts empty and is repopulated by the publisher's next heartbeat.

The service has no file polling, daemon, database, network listener or custom IPC server.

## Integration

The parent configuration repository installs the filtered plugin files and owns the saved-widget migration from `local/pi-sessions:widget` to `local/pi-noctalia:widget`.
The user-facing label is **Pi Sessions**.

## Checks

```sh
bash check.sh
```

This runs the isolated Luau behavior test and Noctalia's offline plugin lint.
