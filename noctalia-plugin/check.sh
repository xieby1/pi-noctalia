#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
python3 - "$root" "$work/test.luau" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
chunks = ['local sources = {}']
for path in root.glob('*.luau'):
    if path.name == 'test.luau':
        continue
    text = path.read_text()
    assert ']===]' not in text
    chunks.append('sources["./' + path.name + '"] = [===[\n' + text + ']===]')
chunks.append((root / 'test.luau').read_text())
pathlib.Path(sys.argv[2]).write_text('\n'.join(chunks))
PY
luau "$work/test.luau"
noctalia plugins lint "$root"
