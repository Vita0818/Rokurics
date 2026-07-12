#!/bin/zsh

set -u
set -o pipefail

SCRIPT_NAME="${0:t}"

usage() {
  echo "Usage: $SCRIPT_NAME --device <UDID-or-device-name> [--bundle-id <id>] [--output <directory>]"
  echo ""
  echo "Collects redacted Rokurics development logs and state snapshots from the Mac and a USB-connected iPhone."
}

DEVICE="${ROKURICS_IPHONE_DEVICE:-}"
BUNDLE_ID="${ROKURICS_IPHONE_BUNDLE_ID:-com.Vita0818.Rokurics}"
OUTPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device)
      DEVICE="${2:-}"
      shift 2
      ;;
    --bundle-id)
      BUNDLE_ID="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$DEVICE" ]]; then
  echo "Missing --device. Set it once with ROKURICS_IPHONE_DEVICE or pass the connected iPhone UDID/name." >&2
  exit 2
fi

COLLECTION_ID="collection-$(date -u +%Y%m%dT%H%M%SZ)"
if [[ -z "$OUTPUT" ]]; then
  OUTPUT="$(pwd)/codex-report/diagnostics/$COLLECTION_ID"
fi

mkdir -p "$OUTPUT/mac" "$OUTPUT/iphone" "$OUTPUT/validation"

WARNINGS_FILE="$OUTPUT/validation/collection-warnings.txt"
: > "$WARNINGS_FILE"

copy_mac_item() {
  local source="$1"
  local destination="$2"
  if [[ -e "$source" ]]; then
    mkdir -p "${destination:h}"
    cp -R "$source" "$destination"
  fi
}

for profile in local production; do
  if [[ "$profile" == "local" ]]; then
    container_id="com.Vita0818.RokuricsMac.local"
    data_folder="RokuricsLocal"
  else
    container_id="com.Vita0818.RokuricsMac"
    data_folder="Rokurics"
  fi
  root="$HOME/Library/Containers/$container_id/Data/Library/Application Support/$data_folder"
  destination="$OUTPUT/mac/$profile"
  copy_mac_item "$root/Diagnostics" "$destination/Diagnostics"
  copy_mac_item "$root/Sync/device-connection-status.json" "$destination/Sync/device-connection-status.json"
  copy_mac_item "$root/Sync/local-network-sync-state.json" "$destination/Sync/local-network-sync-state.json"
  copy_mac_item "$root/Sync/study-library-sync-state.json" "$destination/Sync/study-library-sync-state.json"
  copy_mac_item "$root/Sync/pending-sync-start-signals.json" "$destination/Sync/pending-sync-start-signals.json"
  copy_mac_item "$root/system/upload-trace.jsonl" "$destination/system/upload-trace.jsonl"
  copy_mac_item "$root/system/upload-trace.jsonl.1" "$destination/system/upload-trace.jsonl.1"
done

copy_from_iphone() {
  local source="$1"
  local destination="$2"
  mkdir -p "${destination:h}"
  if ! xcrun devicectl device copy from \
    --device "$DEVICE" \
    --domain-type appDataContainer \
    --domain-identifier "$BUNDLE_ID" \
    --source "$source" \
    --destination "$destination" \
    --timeout 30 \
    --quiet; then
    echo "Could not copy iPhone path: $source" >> "$WARNINGS_FILE"
  fi
}

copy_from_iphone "Library/Application Support/Rokurics/Diagnostics" "$OUTPUT/iphone/application-support-diagnostics"
copy_from_iphone "Library/Application Support/Rokurics/Sync" "$OUTPUT/iphone/sync"
copy_from_iphone "Documents/Rokurics/Diagnostics" "$OUTPUT/iphone/documents-diagnostics"

python3 - "$OUTPUT" "$COLLECTION_ID" "$DEVICE" "$BUNDLE_ID" <<'PY'
import datetime
import json
import pathlib
import sys

output = pathlib.Path(sys.argv[1])
collection_id = sys.argv[2]
device = sys.argv[3]
bundle_id = sys.argv[4]

manifest = {
    "schemaVersion": 1,
    "collectionID": collection_id,
    "collectedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "iphoneDeviceSelector": device,
    "iphoneBundleIdentifier": bundle_id,
    "contents": {
        "mac": "redacted diagnostics plus connection/sync state snapshots",
        "iphone": "redacted diagnostics plus connection/sync state snapshots",
    },
}
(output / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")

results = []
for path in sorted(output.rglob("*")):
    if not path.is_file() or ".jsonl" not in path.name:
        continue
    valid = 0
    invalid = []
    for number, raw_line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), start=1):
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("ROKURICS_UPLOAD_TRACE "):
            line = line[len("ROKURICS_UPLOAD_TRACE "):]
        try:
            json.loads(line)
            valid += 1
        except Exception as exc:
            invalid.append({"line": number, "error": type(exc).__name__})
    results.append({
        "path": str(path.relative_to(output)),
        "validLines": valid,
        "invalidLineCount": len(invalid),
        "invalidLines": invalid[:50],
    })

summary = {
    "schemaVersion": 1,
    "filesChecked": len(results),
    "validLines": sum(item["validLines"] for item in results),
    "invalidLines": sum(item["invalidLineCount"] for item in results),
    "files": results,
}
(output / "validation" / "jsonl-validation.json").write_text(
    json.dumps(summary, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY

echo "Diagnostics collection complete: $OUTPUT"
echo "JSONL validation: $OUTPUT/validation/jsonl-validation.json"
