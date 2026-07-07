#!/usr/bin/env bash

set -u

THRESHOLD_MS="${JANK_THRESHOLD_MS:-800}"
TOP_LIMIT="${JANK_TOP:-20}"
IOS_BUNDLE_ID="${JANK_IOS_BUNDLE_ID:-com.Vita0818.Rokurics}"
COMMAND_TIMEOUT_SECONDS="${JANK_COMMAND_TIMEOUT_SECONDS:-12}"
TMP_ROOT="${TMPDIR:-/tmp}/rokurics-jank-report.$$"
IPHONE_STATUS="$TMP_ROOT/iphone-status.txt"

mkdir -p "$TMP_ROOT"
trap 'rm -rf "$TMP_ROOT"' EXIT

run_with_timeout() {
  local seconds="$1"
  local stdout_path="$2"
  local stderr_path="$3"
  shift 3

  python3 - "$seconds" "$stdout_path" "$stderr_path" "$@" <<'PY'
import contextlib
import subprocess
import sys

try:
    timeout = float(sys.argv[1])
except ValueError:
    timeout = 12.0
stdout_path = sys.argv[2]
stderr_path = sys.argv[3]
args = sys.argv[4:]

stdout_cm = open(stdout_path, "wb") if stdout_path != "-" else contextlib.nullcontext(subprocess.DEVNULL)
stderr_cm = open(stderr_path, "wb") if stderr_path != "-" else contextlib.nullcontext(subprocess.DEVNULL)
try:
    with stdout_cm as stdout_handle, stderr_cm as stderr_handle:
        completed = subprocess.run(
            args,
            stdout=stdout_handle,
            stderr=stderr_handle,
            timeout=timeout,
            check=False,
        )
    sys.exit(completed.returncode)
except subprocess.TimeoutExpired:
    if stderr_path != "-":
        with open(stderr_path, "ab") as handle:
            handle.write(f"timed out after {timeout:.1f}s\n".encode("utf-8"))
    sys.exit(124)
except OSError as error:
    if stderr_path != "-":
        with open(stderr_path, "ab") as handle:
            handle.write((str(error) + "\n").encode("utf-8"))
    sys.exit(127)
PY
}

find_mac_log() {
  if [ -n "${JANK_MAC_LOG:-}" ] && [ -f "$JANK_MAC_LOG" ]; then
    printf '%s\n' "$JANK_MAC_LOG"
    return 0
  fi

  python3 - <<'PY'
import os
import sys

home = os.path.expanduser("~")
roots = []

app_support = os.path.join(home, "Library", "Application Support")
if os.path.isdir(app_support):
    try:
        for name in os.listdir(app_support):
            if "Rokurics" in name:
                roots.append(os.path.join(app_support, name))
    except OSError:
        pass

containers = os.path.join(home, "Library", "Containers")
if os.path.isdir(containers):
    try:
        for name in os.listdir(containers):
            if "Rokurics" in name:
                roots.append(os.path.join(containers, name))
    except OSError:
        pass

candidates = []
for root in dict.fromkeys(roots):
    for dirpath, dirnames, filenames in os.walk(root):
        if "UITests" in dirpath:
            dirnames[:] = []
            continue
        dirnames[:] = [name for name in dirnames if "UITests" not in name]
        if "connection-diagnostics.jsonl" not in filenames:
            continue
        path = os.path.join(dirpath, "connection-diagnostics.jsonl")
        try:
            candidates.append((os.path.getmtime(path), path))
        except OSError:
            pass

if not candidates:
    sys.exit(1)
print(max(candidates)[1])
PY
}

find_iphone_device_id() {
  if [ -n "${JANK_DEVICE_ID:-}" ]; then
    printf '%s\n' "$JANK_DEVICE_ID"
    return 0
  fi

  command -v xcrun >/dev/null 2>&1 || return 1

  local json_path="$TMP_ROOT/devices.json"
  if run_with_timeout "$COMMAND_TIMEOUT_SECONDS" "-" "$TMP_ROOT/devicectl-list.err" \
    xcrun devicectl list devices --json-output "$json_path"; then
    python3 - "$json_path" <<'PY'
import json
import re
import sys

path = sys.argv[1]
try:
    data = json.load(open(path, "r", encoding="utf-8"))
except Exception:
    sys.exit(1)

uuid_re = re.compile(r"^[0-9A-Fa-f-]{24,}$")

def walk(value):
    if isinstance(value, dict):
        text = json.dumps(value, ensure_ascii=False)
        if "iPhone" in text and ("available" in text.lower() or "connected" in text.lower() or "paired" in text.lower()):
            for key in ("identifier", "deviceIdentifier", "udid", "ecid", "serialNumber"):
                candidate = value.get(key)
                if isinstance(candidate, str) and candidate.strip():
                    return candidate.strip()
            for candidate in value.values():
                if isinstance(candidate, str) and uuid_re.match(candidate.strip()):
                    return candidate.strip()
        for child in value.values():
            found = walk(child)
            if found:
                return found
    elif isinstance(value, list):
        for child in value:
            found = walk(child)
            if found:
                return found
    return None

found = walk(data)
if not found:
    sys.exit(1)
print(found)
PY
    return $?
  fi

  local text_path="$TMP_ROOT/devices.txt"
  if ! run_with_timeout "$COMMAND_TIMEOUT_SECONDS" "$text_path" "$TMP_ROOT/devicectl-list-text.err" \
    xcrun devicectl list devices; then
    return 1
  fi

  python3 - "$text_path" <<'PY'
import re
import sys

path = sys.argv[1]
uuid_re = re.compile(r"([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}|[0-9A-Fa-f]{24,40})")
for line in open(path, "r", encoding="utf-8", errors="replace"):
    if "iPhone" not in line:
        continue
    match = uuid_re.search(line)
    if match:
        print(match.group(1))
        sys.exit(0)
sys.exit(1)
PY
}

pull_iphone_log_with_devicectl() {
  local device_id="$1"
  shift

  command -v xcrun >/dev/null 2>&1 || return 1

  local index=0
  local remote_path
  for remote_path in "$@"; do
    index=$((index + 1))
    local destination="$TMP_ROOT/iphone-devicectl-$index"
    mkdir -p "$destination"
    if run_with_timeout "$COMMAND_TIMEOUT_SECONDS" "-" "$TMP_ROOT/devicectl-copy-$index.err" \
      xcrun devicectl device copy from \
      --device "$device_id" \
      --domain-type appDataContainer \
      --domain-identifier "$IOS_BUNDLE_ID" \
      --source "$remote_path" \
      --destination "$destination"; then
      local copied
      copied="$(find "$destination" -name connection-diagnostics.jsonl -type f -print 2>/dev/null | head -n 1)"
      if [ -n "$copied" ] && [ -f "$copied" ]; then
        printf '%s\n' "$copied"
        return 0
      fi
      if [ -f "$destination/connection-diagnostics.jsonl" ]; then
        printf '%s\n' "$destination/connection-diagnostics.jsonl"
        return 0
      fi
    fi
  done
  return 1
}

pull_iphone_log_with_pymobiledevice3() {
  shift

  command -v pymobiledevice3 >/dev/null 2>&1 || return 1

  local index=0
  local remote_path
  for remote_path in "$@"; do
    index=$((index + 1))
    local destination="$TMP_ROOT/iphone-pymobiledevice3-$index.jsonl"
    if run_with_timeout "$COMMAND_TIMEOUT_SECONDS" "-" "$TMP_ROOT/pymobiledevice3-$index.err" \
      pymobiledevice3 apps afc "$IOS_BUNDLE_ID" pull "$remote_path" "$destination"; then
      if [ -f "$destination" ]; then
        printf '%s\n' "$destination"
        return 0
      fi
    fi
  done
  return 1
}

pull_iphone_log() {
  local remote_candidates=(
    "Library/Application Support/Rokurics/Diagnostics/connection-diagnostics.jsonl"
    "Documents/Rokurics/Sync/Diagnostics/connection-diagnostics.jsonl"
    "Documents/Rokurics/Diagnostics/connection-diagnostics.jsonl"
    "Library/Application Support/Rokurics/Sync/Diagnostics/connection-diagnostics.jsonl"
  )

  local device_id
  if ! device_id="$(find_iphone_device_id)"; then
    printf 'iPhone log unavailable: no USB iPhone detected by devicectl. Set JANK_DEVICE_ID to override.\n' >"$IPHONE_STATUS"
    return 1
  fi

  local pulled
  if pulled="$(pull_iphone_log_with_devicectl "$device_id" "${remote_candidates[@]}")"; then
    printf 'iPhone copy: devicectl device=%s bundle=%s\n' "$device_id" "$IOS_BUNDLE_ID" >"$IPHONE_STATUS"
    printf '%s\n' "$pulled"
    return 0
  fi

  if pulled="$(pull_iphone_log_with_pymobiledevice3 "$device_id" "${remote_candidates[@]}")"; then
    printf 'iPhone copy: pymobiledevice3 bundle=%s\n' "$IOS_BUNDLE_ID" >"$IPHONE_STATUS"
    printf '%s\n' "$pulled"
    return 0
  fi

  printf 'iPhone log unavailable: copy failed for bundle %s. Set JANK_IOS_BUNDLE_ID/JANK_DEVICE_ID if needed.\n' "$IOS_BUNDLE_ID" >"$IPHONE_STATUS"
  return 1
}

MAC_LOG=""
IPHONE_LOG=""

if ! MAC_LOG="$(find_mac_log)"; then
  MAC_LOG=""
fi

if ! IPHONE_LOG="$(pull_iphone_log)"; then
  IPHONE_LOG=""
fi

python3 - "$THRESHOLD_MS" "$TOP_LIMIT" "$MAC_LOG" "$IPHONE_LOG" "$IPHONE_STATUS" <<'PY'
import json
import os
import sys

threshold = int(sys.argv[1])
limit = int(sys.argv[2])
mac_log = sys.argv[3]
iphone_log = sys.argv[4]
iphone_status_path = sys.argv[5]
stage_keys = ["inventoryBuildMs", "projectionRebuildMs", "hashMs", "applyMs", "waitBackgroundMs"]

def as_int(value):
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    if isinstance(value, str):
        try:
            return int(float(value))
        except ValueError:
            return None
    return None

def dominant_stage(obj):
    name = obj.get("dominantSubphase")
    value = as_int(obj.get("dominantSubphaseMs"))
    if name and value is not None:
        return name, value

    best = None
    for key in stage_keys:
        candidate = as_int(obj.get(key))
        if candidate is None:
            continue
        if best is None or candidate > best[1]:
            best = (key, candidate)
    return best or ("unknown", None)

def read_records(side, path):
    rows = []
    if not path or not os.path.isfile(path):
        return rows
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        for line_number, line in enumerate(handle, 1):
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            operation = obj.get("operation")
            total_ms = as_int(obj.get("totalMs"))
            if not operation or total_ms is None or total_ms <= threshold:
                continue
            phase = obj.get("phase") or ""
            dominant_name, dominant_ms = dominant_stage(obj)
            rows.append({
                "side": side,
                "operation": operation,
                "total_ms": total_ms,
                "dominant": dominant_name,
                "dominant_ms": dominant_ms,
                "phase": phase,
                "path": path,
                "line": line_number,
            })
    return rows

all_rows = read_records("Mac", mac_log) + read_records("iPhone", iphone_log)

jank_keys = {
    (row["side"], row["operation"], row["total_ms"], row["dominant"], row["dominant_ms"])
    for row in all_rows
    if row["phase"] == "jankDetected"
}
deduped = []
seen = set()
for row in all_rows:
    key = (row["side"], row["operation"], row["total_ms"], row["dominant"], row["dominant_ms"])
    if row["phase"] != "jankDetected" and key in jank_keys:
        continue
    if key in seen:
        continue
    seen.add(key)
    deduped.append(row)

deduped.sort(key=lambda row: row["total_ms"], reverse=True)

print(f"Rokurics jank report (threshold: >{threshold}ms)")
print(f"Mac log: {mac_log or 'not found'}")
if iphone_log:
    print(f"iPhone log: {iphone_log}")
else:
    try:
        status = open(iphone_status_path, "r", encoding="utf-8").read().strip()
    except OSError:
        status = "iPhone log unavailable"
    print(status)
print()

if not deduped:
    print("No operations over threshold.")
    sys.exit(0)

print("SIDE\tOPERATION\tTOTAL_MS\tDOMINANT_SUBPHASE\tPHASE")
for row in deduped[:limit]:
    dominant_ms = row["dominant_ms"]
    dominant = row["dominant"] if dominant_ms is None else f"{row['dominant']}={dominant_ms}ms"
    print(f"{row['side']}\t{row['operation']}\t{row['total_ms']}\t{dominant}\t{row['phase']}")
PY
