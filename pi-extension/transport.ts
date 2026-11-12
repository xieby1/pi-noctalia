import { execFile } from "node:child_process";

// One subprocess plus one latest-value slot; never queue a turn's token stream.
export function createSender() {
  let pending: { event: string; payload: object } | undefined;
  let running: Promise<void> | undefined;
  let closed = false;

  function drain() {
    if (running || !pending) return;
    const { event, payload } = pending;
    pending = undefined;
    running = new Promise<void>((resolve) => {
      execFile("noctalia", [
        "msg", "plugin", "local/pi-noctalia:service", "all",
        event, JSON.stringify(payload),
      ], { timeout: 1000, killSignal: "SIGKILL", maxBuffer: 8192 }, () => resolve());
    });
    void running.then(() => {
      running = undefined;
      drain();
    });
  }

  return {
    send(payload: object) {
      if (closed) return;
      pending = { event: "upsert", payload };
      drain();
    },
    async close(payload: object) {
      if (closed) return;
      closed = true;
      // Remove follows any already-sent update; unsent updates are obsolete.
      pending = { event: "remove", payload };
      drain();
      while (running) await running;
    },
  };
}
