#!/usr/bin/env bash
# Copy LibRaw and its Homebrew runtime deps into NegSwift.app/Contents/Frameworks.
# Rewrites load commands so the app runs without a system/Homebrew install.
set -euo pipefail

APP="${1:?Usage: bundle_libraw.sh /path/to/NegSwift.app}"
EXEC="$APP/Contents/MacOS/NegSwift"
FRAMEWORKS="$APP/Contents/Frameworks"

test -f "$EXEC" || { echo "Missing executable: $EXEC" >&2; exit 1; }

if ! otool -L "$EXEC" | awk '{print $1}' | grep -qE 'libraw'; then
    cat >&2 <<'EOF'
NegSwift was built without LibRaw (stub backend).

Rebuild after installing LibRaw:
  brew install libraw libomp
  rm -rf App/build
  make build-release

A universal Release build cannot link Homebrew's single-arch LibRaw — make build-release
passes ONLY_ACTIVE_ARCH=YES automatically when LibRaw is present.
EOF
    exit 1
fi

should_bundle() {
    case "$1" in
        /opt/homebrew/* | /usr/local/*) return 0 ;;
        *) return 1 ;;
    esac
}

resolve_lib() {
    local path="$1"
    if [[ -L "$path" ]]; then
        local dir
        dir="$(cd "$(dirname "$path")" && pwd)"
        local target
        target="$(readlink "$path")"
        if [[ "$target" == /* ]]; then
            echo "$target"
        else
            echo "$dir/$target"
        fi
    else
        echo "$path"
    fi
}

seen_contains() {
    local base="$1"
    local item
    if [[ ${#SEEN[@]} -eq 0 ]]; then
        return 1
    fi
    for item in "${SEEN[@]}"; do
        if [[ "$item" == "$base" ]]; then
            return 0
        fi
    done
    return 1
}

SEEN=()
PATHS=()

collect_deps() {
    local bin="$1"
    while IFS= read -r lib; do
        [[ -z "$lib" ]] && continue
        should_bundle "$lib" || continue
        local resolved
        resolved="$(resolve_lib "$lib")"
        [[ -f "$resolved" ]] || continue
        local base
        base="$(basename "$resolved")"
        if seen_contains "$base"; then
            continue
        fi
        SEEN+=("$base")
        PATHS+=("$resolved")
        collect_deps "$resolved"
    done < <(otool -L "$bin" | tail -n +2 | awk '{print $1}')
}

collect_deps "$EXEC"

if [[ ${#SEEN[@]} -eq 0 ]]; then
    echo "No Homebrew dylibs to bundle (LibRaw may already use @rpath)." >&2
    exit 0
fi

mkdir -p "$FRAMEWORKS"

i=0
while [[ $i -lt ${#SEEN[@]} ]]; do
    base="${SEEN[$i]}"
    src="${PATHS[$i]}"
    dest="$FRAMEWORKS/$base"
    echo "Bundling $(basename "$src") → Frameworks/$base"
    cp -f "$src" "$dest"
    chmod 755 "$dest"
    install_name_tool -id "@rpath/$base" "$dest"
    i=$((i + 1))
done

install_name_tool -add_rpath @executable_path/../Frameworks "$EXEC" 2>/dev/null || true
for dylib in "$FRAMEWORKS"/*.dylib; do
    [[ -f "$dylib" ]] || continue
    install_name_tool -add_rpath @loader_path "$dylib" 2>/dev/null || true
done

rewrite_binary() {
    local bin="$1"
    while IFS= read -r lib; do
        [[ -z "$lib" ]] || should_bundle "$lib" || continue
        local base
        base="$(basename "$(resolve_lib "$lib")")"
        [[ -f "$FRAMEWORKS/$base" ]] || continue
        install_name_tool -change "$lib" "@rpath/$base" "$bin" 2>/dev/null || true
    done < <(otool -L "$bin" | tail -n +2 | awk '{print $1}')
}

rewrite_binary "$EXEC"
for dylib in "$FRAMEWORKS"/*.dylib; do
    rewrite_binary "$dylib"
done

echo "LibRaw bundle OK (${#SEEN[@]} dylibs in Frameworks)."
