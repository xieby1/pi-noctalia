# Pi publisher

The Pi extension publishes live status for interactive TUI sessions to the Noctalia `Pi Sessions` plugin.
It does not send prompts, change Pi state, or duplicate notification behavior.

## Lifecycle

- Register only TUI sessions on `session_start`.
- Report `working` on `agent_start` and `idle` on `agent_settled`; retries and continuations therefore do not flicker to idle.
- Overlay `waiting` while native `ui_prompt_start` / `ui_prompt_end` spans are active.
- Preserve `aborted` after a settled run until the next run starts.
- Send a complete snapshot on changes and every 15 seconds so a restarted Noctalia instance recovers automatically.
- Stop the heartbeat on shutdown or reload and send an ordered `remove` message.

IPC uses `execFile` with argument arrays, one in-flight subprocess, one replaceable pending snapshot, a one-second timeout and bounded output.
Failures are silent and fail-open so a missing or slow Noctalia cannot block Pi.

## Snapshot contract

Snapshots use schema `1` and contain a random `instanceId`, process `pid`, logical `sessionId`, `startedAt`, `sequence`, `name`, `cwd`, `model`, `state` and `aborted`.
On local Linux Ghostty, they also carry `ghostty.pid`, a decimal-string `ghostty.surfaceId` (uint64), and the Pi process's `ghostty.piStartTicks` from `/proc/self/stat`. The strings preserve exact identities through Luau and D-Bus; the field is omitted when the surface or either process identity cannot be verified.
The receiver validates these fields and uses full snapshots so retries are idempotent.

## Checks

```sh
node --test index.test.mjs
```

For a real Pi TUI smoke check (with `pi` on `PATH`), run from the repository root:

```sh
python3 pi-extension/smoke.py pi-extension/index.ts
```

Install `index.ts` and `transport.ts` together in an auto-discovered Pi extension directory (or link this directory as described in the root README).
