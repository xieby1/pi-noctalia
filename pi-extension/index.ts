import { randomUUID } from "node:crypto";
import { readFileSync, readlinkSync } from "node:fs";
import { basename } from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { createSender } from "./transport.ts";

const text = (value: string, length: number) =>
  Array.from(value.replace(/[\x00-\x1f\x7f-\x9f]/g, " " )).slice(0, length).join("");

function ghosttyOrigin() {
  const surfaceId = process.env.GHOSTTY_SURFACE_ID;
  if (process.platform !== "linux" || process.env.TERM_PROGRAM !== "ghostty" ||
      !surfaceId || !/^0x[0-9a-f]{16}$/i.test(surfaceId) || /^0x0{16}$/i.test(surfaceId)) return;
  let pid = process.ppid;
  for (let depth = 0; pid > 1 && depth < 32; depth++) {
    try {
      const executable = basename(readlinkSync(`/proc/${pid}/exe`));
      if (executable === "ghostty" || executable === ".ghostty-wrapped") {
        const stat = readFileSync("/proc/self/stat", "utf8");
        const end = stat.lastIndexOf(") ");
        const piStartTicks = end < 0 ? undefined : stat.slice(end + 2).trim().split(/\s+/)[19];
        if (!piStartTicks || !/^[1-9]\d*$/.test(piStartTicks)) return;
        return { pid, surfaceId: BigInt(surfaceId).toString(), piStartTicks };
      }
      const parent = readFileSync(`/proc/${pid}/status`, "utf8").match(/^PPid:\s*(\d+)$/m);
      if (!parent) break;
      pid = Number(parent[1]);
    } catch { break; }
  }
}

export default function (pi: ExtensionAPI) {
  let sender: ReturnType<typeof createSender> | undefined;
  let heartbeat: ReturnType<typeof setInterval> | undefined;
  let context: ExtensionContext;
  let ghostty: ReturnType<typeof ghosttyOrigin>;
  let instanceId: string;
  let startedAt: number;
  let sequence = 0;
  let working = false;
  let waiting = false;
  let aborted = false;

  function publish(ctx = context) {
    if (!sender) return;
    context = ctx;
    sender.send({
      schema: 1, instanceId, sequence: ++sequence, startedAt, pid: process.pid, ghostty,
      sessionId: text(ctx.sessionManager.getSessionId(), 128),
      name: text(ctx.sessionManager.getSessionName() || basename(ctx.cwd) || "Pi", 128),
      cwd: text(ctx.cwd, 1024),
      model: text(ctx.model ? `${ctx.model.provider}/${ctx.model.id}` : "", 256),
      state: waiting ? "waiting" : working ? "working" : "idle",
      aborted,
    });
  }

  pi.on("session_start", (_event, ctx) => {
    // RPC/print subagents are not independent interactive desktop sessions.
    if (ctx.mode !== "tui") return;
    instanceId = randomUUID();
    startedAt = Date.now();
    sequence = 0;
    working = !ctx.isIdle();
    waiting = aborted = false;
    ghostty = ghosttyOrigin();
    sender = createSender();
    publish(ctx);
    heartbeat = setInterval(() => {
      working = !context.isIdle();
      publish();
    }, 15_000);
    heartbeat.unref();
  });

  pi.on("agent_start", (_event, ctx) => {
    working = true;
    aborted = false;
    publish(ctx);
  });

  // agent_end can precede retries, compaction or queued work.
  pi.on("agent_settled", (event, ctx) => {
    working = false;
    aborted = event.aborted;
    publish(ctx);
  });

  pi.on("ui_prompt_start", (_event, ctx) => {
    waiting = true;
    publish(ctx);
  });
  pi.on("ui_prompt_end", (_event, ctx) => {
    waiting = false;
    publish(ctx);
  });
  pi.on("model_select", (_event, ctx) => publish(ctx));

  pi.on("session_shutdown", async () => {
    clearInterval(heartbeat);
    heartbeat = undefined;
    const closing = sender;
    sender = undefined;
    if (closing) {
      await closing.close({ schema: 1, instanceId, sequence: ++sequence });
    }
  });
}
