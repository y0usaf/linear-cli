#!/usr/bin/env bash
set -euo pipefail

err_log="$(mktemp)"
cleanup() { rm -f "$err_log"; }
trap cleanup EXIT

if nix build .#linear -L 2> >(tee "$err_log" >&2); then
  echo "denoDepsHash unchanged"
  exit 0
fi

new_hash="$(python - "$err_log" <<'PY'
from pathlib import Path
import re
import sys
text = Path(sys.argv[1]).read_text(errors="ignore")
matches = re.findall(r'got:\s*(sha256-[A-Za-z0-9+/=]+)', text)
print(matches[-1] if matches else "")
PY
)"

if [ -z "$new_hash" ]; then
  echo "build failed without a denoDepsHash mismatch" >&2
  exit 1
fi

python - "$new_hash" <<'PY'
from pathlib import Path
import re
import sys
new_hash = sys.argv[1]
path = Path("flake.nix")
text = path.read_text()
updated, count = re.subn(
    r'denoDepsHash = "sha256-[A-Za-z0-9+/=]+";',
    f'denoDepsHash = "{new_hash}";',
    text,
    count=1,
)
if count != 1:
    raise SystemExit("could not update denoDepsHash in flake.nix")
path.write_text(updated)
print(new_hash)
PY

nix build .#linear -L

echo "updated denoDepsHash=$new_hash"
