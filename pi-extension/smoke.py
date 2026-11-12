"""Exercise the real Pi TUI in a private profile; all Noctalia IPC goes to a fixture."""
import fcntl
import json
import os
import pathlib
import pty
import select
import shutil
import struct
import subprocess
import sys
import tempfile
import termios
import time

extension = pathlib.Path(sys.argv[1]).resolve()
pi = shutil.which("pi")
assert pi, "Pi must be on PATH"
with tempfile.TemporaryDirectory(prefix="pi-noctalia-smoke-") as directory:
    root = pathlib.Path(directory)
    binary = root / "bin"
    binary.mkdir()
    log = root / "messages.jsonl"
    fixture = binary / "noctalia"
    fixture.write_text(chr(10).join([
        "#!" + sys.executable,
        "import json, os, sys",
        "with open(os.environ['PI_NOCTALIA_SMOKE_LOG'], 'a') as f:",
        "    f.write(json.dumps(sys.argv[1:]) + chr(10))",
        "",
    ]))
    fixture.chmod(0o700)
    env = {**os.environ, "HOME": str(root), "PI_CODING_AGENT_DIR": str(root / "agent"),
           "XDG_CONFIG_HOME": str(root / "config"), "XDG_DATA_HOME": str(root / "data"),
           "XDG_STATE_HOME": str(root / "state"), "TERM": "xterm-256color",
           "PATH": str(binary) + os.pathsep + os.environ["PATH"],
           "PI_NOCTALIA_SMOKE_LOG": str(log)}
    args = [pi, "--offline", "--no-session", "--no-extensions", "--no-skills",
            "--no-prompt-templates", "-e", str(extension)]
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 35, 120, 0, 0))
    proc = subprocess.Popen(args, stdin=slave, stdout=slave, stderr=slave,
                            cwd=root, env=env, start_new_session=True)
    os.close(slave)
    output = bytearray()

    def messages():
        if not log.exists():
            return []
        lines = log.read_text().splitlines()
        return [json.loads(line) for line in lines if line]

    def pump():
        if select.select([master], [], [], 0.03)[0]:
            try:
                output.extend(os.read(master, 65536))
            except OSError:
                pass

    def until(predicate):
        end = time.monotonic() + 15
        while time.monotonic() < end:
            pump()
            if predicate():
                return
        raise AssertionError(output[-6000:].decode(errors="replace"))

    try:
        until(lambda: len(messages()) >= 1)
        first = json.loads(messages()[0][-1])
        assert first["state"] == "idle" and first["pid"] == proc.pid
        # Let the first prompt render before typing a real built-in command.
        for _ in range(15):
            pump()
        os.write(master, b"/reload" + bytes([13]))
        until(lambda: len([m for m in messages() if m[-2] == "upsert"]) >= 2)
        after = messages()
        assert any(m[-2] == "remove" and json.loads(m[-1])["instanceId"] == first["instanceId"] for m in after)
        second = json.loads([m for m in after if m[-2] == "upsert"][-1][-1])
        assert second["instanceId"] != first["instanceId"]
        for _ in range(10):
            pump()
        os.write(master, bytes([4]))
        until(lambda: proc.poll() is not None)
        assert proc.returncode == 0
        assert messages()[-1][-2] == "remove"
        assert json.loads(messages()[-1][-1])["instanceId"] == second["instanceId"]
        assert "Failed to load extension" not in output.decode(errors="replace")
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        os.close(master)

print("Real Pi TUI: startup, reload, fresh identity and clean shutdown passed")
