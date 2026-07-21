#!/usr/bin/env bash
# Regression guard: build cleanup paths must stay within one direct child of
# the repository's build/ directory.  A malformed BUILD_DIR must be rejected
# before any rm invocation can observe it.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# shellcheck source=../scripts/path-safety.sh
source "$ROOT/scripts/path-safety.sh"

for path in build/c build/linux-arm64 build/linux-amd64 build/win-cross; do
    cbm_require_safe_build_dir "$path"
done

for path in \
    "" \
    build \
    build/ \
    . \
    .. \
    ../outside \
    /tmp/outside \
    build/../outside \
    build/./c \
    build//c \
    build/nested/c \
    'build\..\outside'; do
    if cbm_require_safe_build_dir "$path" >/dev/null 2>&1; then
        echo "FAIL: unsafe BUILD_DIR was accepted: '$path'" >&2
        exit 1
    fi
done

# Lexical containment is not enough: an attacker-controlled or accidental
# build/ symlink would make ROOT/build/c traverse outside the repository.
symlink_fixture="$(mktemp -d "${TMPDIR:-/tmp}/cbm-build-dir-symlink.XXXXXX")"
trap 'rm -rf -- "$symlink_fixture"' EXIT
mkdir -p "$symlink_fixture/repo" "$symlink_fixture/outside"
ln -s "$symlink_fixture/outside" "$symlink_fixture/repo/build"
if (
    cd "$symlink_fixture/repo"
    cbm_require_safe_build_dir build/c "$symlink_fixture/repo"
); then
    echo "FAIL: BUILD_DIR accepted a symlinked build/ ancestor" >&2
    exit 1
fi

mkdir -p "$symlink_fixture/safe-repo/build" "$symlink_fixture/final-target"
printf 'keep\n' >"$symlink_fixture/final-target/sentinel"
ln -s "$symlink_fixture/final-target" "$symlink_fixture/safe-repo/build/c"
if ! cbm_remove_build_dir "$symlink_fixture/safe-repo" build/c; then
    echo "FAIL: safe removal rejected a final-component symlink" >&2
    exit 1
fi
if [ -e "$symlink_fixture/safe-repo/build/c" ] ||
    [ ! -f "$symlink_fixture/final-target/sentinel" ]; then
    echo "FAIL: final-component symlink removal followed the link" >&2
    exit 1
fi
mkdir -p "$symlink_fixture/safe-repo/build/ordinary"
printf 'remove\n' >"$symlink_fixture/safe-repo/build/ordinary/artifact"
cbm_remove_build_dir "$symlink_fixture/safe-repo" build/ordinary
if [ -e "$symlink_fixture/safe-repo/build/ordinary" ]; then
    echo "FAIL: ordinary build child was not removed" >&2
    exit 1
fi

# Direct Makefile cleanup is a public developer entrypoint too; it must use
# the same guard instead of interpolating an untrusted value into a shell.
if make -s -f "$ROOT/Makefile.cbm" clean-c BUILD_DIR=build/nested/c >/dev/null 2>&1; then
    echo "FAIL: make clean-c accepted an unsafe BUILD_DIR" >&2
    exit 1
fi

echo "Build directory safety contract passed"
