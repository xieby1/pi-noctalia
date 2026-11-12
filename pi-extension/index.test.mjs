import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import test from "node:test";
import extension from "./index.ts";
import { createSender } from "./transport.ts";

async function fixture(t) {
  const dir = await mkdtemp(join(tmpdir(), "pi-noctalia-"));
  const log = join(dir, "messages");
  const previous = { PATH: process.env.PATH, PI_NOCTALIA_TEST_LOG: process.env.PI_NOCTALIA_TEST_LOG, PI_NOCTALIA_TEST_MODE: process.env.PI_NOCTALIA_TEST_MODE };
  process.env.PATH = dir;
  process.env.PI_NOCTALIA_TEST_LOG = log;
  delete process.env.PI_NOCTALIA_TEST_MODE;
  await writeFile(log, "");
  await writeFile(join(dir, "noctalia"), `#!${process.execPath}
const fs = require('node:fs');
fs.appendFileSync(process.env.PI_NOCTALIA_TEST_LOG, JSON.stringify(process.argv.slice(2)) + String.fromCharCode(10));
if (process.env.PI_NOCTALIA_TEST_MODE === 'hang') setInterval(() => {}, 1000);
if (process.env.PI_NOCTALIA_TEST_MODE === 'error') process.exitCode = 1;
if (process.env.PI_NOCTALIA_TEST_MODE === 'slow') setTimeout(() => {}, 120);
if (process.env.PI_NOCTALIA_TEST_MODE === 'noise') process.stdout.write('x'.repeat(100000));
`, { mode: 0o700 });
  t.after(async () => {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[key]; else process.env[key] = value;
    }
    await rm(dir, { recursive: true, force: true });
  });
  async function messages() {
    return (await readFile(log, "utf8")).trim().split("\n").filter(Boolean).map(line => {
      const args = JSON.parse(line);
      assert.deepEqual(args.slice(0, 4), ["msg", "plugin", "local/pi-noctalia:service", "all"]);
      assert.equal(args.length, 6);
      return { event: args[4], payload: JSON.parse(args[5]) };
    });
  }
  async function waitFor(count) {
    const end = Date.now() + 4000;
    while (Date.now() < end) {
      const entries = await messages();
      if (entries.length >= count) return entries;
      await delay(10);
    }
    assert.fail(`Timed out waiting for ${count} IPC messages`);
  }
  return { dir, messages, waitFor };
}

function host(t, mode = "tui") {
  const handlers = new Map();
  let heartbeat;
  let cleared = false;
  const timer = { unref() {} };
  t.mock.method(globalThis, "setInterval", (fn, ms) => {
    assert.equal(ms, 15000);
    heartbeat = fn;
    cleared = false;
    return timer;
  });
  t.mock.method(globalThis, "clearInterval", () => { cleared = true; });
  const ctx = {
    mode, cwd: "/projects/example", model: { provider: "provider", id: "model" },
    isIdle: () => true,
    sessionManager: { getSessionId: () => "session-1", getSessionName: () => "Example" },
  };
  extension({ on: (event, fn) => handlers.set(event, fn) });
  const emit = (event, data = {}) => handlers.get(event)?.(data, ctx);
  return { ctx, emit, beat: () => heartbeat?.(), cleared: () => cleared };
}

test("lifecycle pushes full status and preserves working through agent_end", async t => {
  const f = await fixture(t);
  const h = host(t);
  h.emit("session_start");
  let events = await f.waitFor(1);
  const initial = events[0].payload;
  assert.equal(initial.state, "idle");
  assert.equal(initial.name, "Example");
  assert.equal(initial.pid, process.pid);
  assert.equal(initial.model, "provider/model");
  assert.match(initial.instanceId, /^[a-f0-9-]{36}$/);

  h.ctx.isIdle = () => false;
  h.emit("agent_start");
  await f.waitFor(2);
  h.emit("agent_end");
  h.beat();
  events = await f.waitFor(3);
  assert.equal(events.at(-1).payload.state, "working");

  h.emit("ui_prompt_start");
  events = await f.waitFor(4);
  assert.equal(events.at(-1).payload.state, "waiting");
  h.emit("ui_prompt_end");
  events = await f.waitFor(5);
  assert.equal(events.at(-1).payload.state, "working");

  h.ctx.isIdle = () => true;
  h.emit("agent_settled", { aborted: true });
  events = await f.waitFor(6);
  assert.equal(events.at(-1).payload.state, "idle");
  assert.equal(events.at(-1).payload.aborted, true);

  h.ctx.sessionManager.getSessionName = () => "Renamed";
  h.ctx.model.id = "another";
  h.beat();
  events = await f.waitFor(7);
  assert.equal(events.at(-1).payload.name, "Renamed");
  assert.equal(events.at(-1).payload.model, "provider/another");
  assert.equal(events.at(-1).payload.instanceId, initial.instanceId);

  await h.emit("session_shutdown");
  assert.equal(h.cleared(), true);
  events = await f.messages();
  assert.equal(events.at(-1).event, "remove");
  assert.equal(events.at(-1).payload.instanceId, initial.instanceId);
  assert.ok(events.every((e, i) => i === 0 || e.payload.sequence > events[i - 1].payload.sequence));
  h.beat();
  await delay(30);
  assert.equal((await f.messages()).length, events.length);
});

test("idle prompts restore idle; new runs clear aborted; reload registers a new identity", async t => {
  const f = await fixture(t);
  const h = host(t);
  h.emit("session_start");
  const first = (await f.waitFor(1))[0].payload;
  h.emit("ui_prompt_start");
  await f.waitFor(2);
  h.emit("ui_prompt_end");
  assert.equal((await f.waitFor(3)).at(-1).payload.state, "idle");
  h.emit("agent_settled", { aborted: true });
  await f.waitFor(4);
  h.emit("agent_start");
  assert.equal((await f.waitFor(5)).at(-1).payload.aborted, false);
  await h.emit("session_shutdown");
  h.emit("session_start");
  const next = (await f.waitFor(7)).at(-1).payload;
  assert.notEqual(next.instanceId, first.instanceId);
  assert.equal(next.sequence, 1);
  await h.emit("session_shutdown");
});

test("RPC and print sessions never publish", async t => {
  const f = await fixture(t);
  for (const mode of ["rpc", "print"]) {
    const h = host(t, mode);
    h.emit("session_start");
    h.emit("agent_start");
    h.emit("ui_prompt_start");
    h.emit("agent_settled", { aborted: false });
    await h.emit("session_shutdown");
  }
  assert.deepEqual(await f.messages(), []);
});

test("status metadata is bounded and passed as data, never evaluated by a shell", async t => {
  const f = await fixture(t);
  const h = host(t);
  h.ctx.sessionManager.getSessionName = () => `$(touch ${f.dir}/INJECTED) "quoted";\n${"界".repeat(1000)}`;
  h.emit("session_start");
  const payload = (await f.waitFor(1))[0].payload;
  assert.ok(payload.name.startsWith("$(touch "));
  assert.ok(!payload.name.includes("\n"));
  assert.ok(Buffer.byteLength(payload.name) <= 512);
  await assert.rejects(readFile(join(f.dir, "INJECTED")), { code: "ENOENT" });
  await h.emit("session_shutdown");
});

test("slow delivery coalesces updates and shutdown supersedes unsent snapshots", async t => {
  const f = await fixture(t);
  process.env.PI_NOCTALIA_TEST_MODE = "slow";
  const sender = createSender();
  sender.send({ sequence: 1 });
  await f.waitFor(1);
  for (let sequence = 2; sequence <= 100; sequence++) sender.send({ sequence });
  const events = await f.waitFor(2);
  assert.equal(events[1].payload.sequence, 100);
  sender.send({ sequence: 101 });
  await sender.close({ sequence: 102 });
  sender.send({ sequence: 103 });
  const final = await f.messages();
  assert.deepEqual(final.map(e => [e.event, e.payload.sequence]), [["upsert", 1], ["upsert", 100], ["remove", 102]]);
});

test("hung IPC is killed and bounded cleanup completes", async t => {
  const f = await fixture(t);
  process.env.PI_NOCTALIA_TEST_MODE = "hang";
  const sender = createSender();
  const start = Date.now();
  sender.send({ sequence: 1 });
  assert.ok(Date.now() - start < 500);
  await sender.close({ sequence: 2 });
  assert.ok(Date.now() - start < 3500);
  assert.equal((await f.messages()).at(-1).event, "remove");
});

test("missing, failing, or noisy IPC never rejects or stops later delivery", async t => {
  const f = await fixture(t);
  for (const mode of ["error", "noise"]) {
    process.env.PI_NOCTALIA_TEST_MODE = mode;
    const sender = createSender();
    sender.send({ sequence: 1 });
    await sender.close({ sequence: 2 });
  }
  await rm(join(f.dir, "noctalia"));
  const sender = createSender();
  sender.send({ sequence: 1 });
  await sender.close({ sequence: 2 });
});
