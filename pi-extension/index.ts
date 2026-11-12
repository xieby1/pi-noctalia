import { randomUUID } from "node:crypto";
import { basename } from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { createSender } from "./transport.ts";

const text = (value: string, length: number) =>
  Array.from(value.replace(/[\x00-\x1f\x7f-\x9f]/g, " " )).slice(0, length).join("");

export default function (pi: ExtensionAPI) {
  let sender: ReturnType<typeof createSender> | undefined;
  let heartbeat: ReturnType<typeof setInterval> | undefined;
  let context: ExtensionContext;
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
      schema: 1, instanceId, sequence: ++sequence, startedAt, pid: process.pid,
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
