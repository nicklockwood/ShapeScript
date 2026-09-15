#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DERIVED_DATA_PATH="$ROOT_DIR/.build/quicklook-derived"
BUILT_APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/ShapeScript Viewer.app"
APP_PATH="${SHAPESCRIPT_QUICKLOOK_APP_PATH:-$HOME/Applications/ShapeScript Viewer Debug.app}"
APPEX_PATH="$APP_PATH/Contents/PlugIns/Preview (Mac).appex"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
PLUGIN_IDS=(
  "com.charcoaldesign.ShapeScriptViewer.Preview"
  "com.charcoaldesign.ShapeScriptMac.Preview"
)

log() {
  printf '\n==> %s\n' "$*"
}

registered_plugin_paths() {
  pluginkit -m -A -D -vvv -p com.apple.quicklook.preview 2>/dev/null |
    awk '
      /^[[:space:]]*[+?!-][[:space:]]+com\.charcoaldesign\.ShapeScript(Viewer|Mac)\.Preview/ {
        in_plugin = 1
        next
      }
      in_plugin && /^[[:space:]]*Path = / {
        sub(/^[[:space:]]*Path = /, "")
        print
        in_plugin = 0
      }
    ' |
    sort -u
}

unregister_containing_app() {
  local appex_path="$1"
  local app_path="${appex_path%/Contents/PlugIns/Preview (Mac).appex}"

  if [ "$app_path" != "$appex_path" ]; then
    printf 'Unregistering containing app %s\n' "$app_path"
    "$LSREGISTER" -u "$app_path" 2>/dev/null || true
  fi
}

log "Unregistering existing ShapeScript QuickLook previews"
while IFS= read -r path; do
  [ -n "$path" ] || continue
  printf 'Removing %s\n' "$path"
  pluginkit -r "$path" || true
  unregister_containing_app "$path"
done < <(registered_plugin_paths)
"$LSREGISTER" -u "$APP_PATH" 2>/dev/null || true

log "Building ShapeScript Viewer with QuickLook extension"
xcodebuild \
  -project "$ROOT_DIR/ShapeScript.xcodeproj" \
  -scheme "Viewer (Mac)" \
  -configuration Debug \
  -arch arm64 \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

if [ ! -d "$BUILT_APP_PATH" ]; then
  printf 'error: expected app not found at:\n%s\n' "$BUILT_APP_PATH" >&2
  exit 1
fi

log "Installing app to a stable Launch Services location"
mkdir -p "$(dirname "$APP_PATH")"
rm -rf "$APP_PATH"
ditto "$BUILT_APP_PATH" "$APP_PATH"
xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true

if [ ! -d "$APPEX_PATH" ]; then
  printf 'error: expected QuickLook extension not found at:\n%s\n' "$APPEX_PATH" >&2
  exit 1
fi

log "Registering containing app and fresh QuickLook preview"
"$LSREGISTER" -f -R "$APP_PATH"
pluginkit -a "$APP_PATH"
pluginkit -a "$APPEX_PATH"
for plugin_id in "${PLUGIN_IDS[@]}"; do
  pluginkit -e use -i "$plugin_id" || true
done

log "Resetting QuickLook and Finder caches"
qlmanage -r
qlmanage -r cache
killall Finder 2>/dev/null || true
killall pkd 2>/dev/null || true
killall QuickLookUIService 2>/dev/null || true
killall QuickLookSatellite 2>/dev/null || true
killall quicklookd 2>/dev/null || true

log "Registered ShapeScript QuickLook previews"
pluginkit -m -A -D -vvv -p com.apple.quicklook.preview |
  awk '
    /^[[:space:]]*[+?!-][[:space:]]+com\.charcoaldesign\.ShapeScript(Viewer|Mac)\.Preview/ {
      print
      in_plugin = 1
      next
    }
    in_plugin && /^[[:space:]]*(Path|UUID|Timestamp|Parent Bundle) = / {
      print
      next
    }
    in_plugin && /^[[:space:]]*$/ {
      print
      in_plugin = 0
    }
  '

cat <<EOF

Done. Test with:
  qlmanage -p "$ROOT_DIR/Examples/Dodecahedron.shape"

Fresh extension:
  $APPEX_PATH

Installed app:
  $APP_PATH
EOF
