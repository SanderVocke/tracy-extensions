#!/usr/bin/env bash
set -euo pipefail

release_dir=${1:?usage: verify-release-files.sh RELEASE_DIR}
root=$(cd "$(dirname "$0")/../.." && pwd)
release_commit=$(git -C "$root" rev-parse HEAD)
expected=(
  tracy-query-linux-x86_64
  tracy-query-linux-arm64
  tracy-query-macos-x86_64
  tracy-query-macos-arm64
  tracy-query-windows-x86_64.exe
  tracy-query-windows-arm64.exe
  tracy-embedded-native-linux-x86_64.tar.gz
  tracy-embedded-native-linux-arm64.tar.gz
  tracy-embedded-native-macos-x86_64.tar.gz
  tracy-embedded-native-macos-arm64.tar.gz
  tracy-embedded-native-windows-x86_64.zip
  tracy-embedded-native-windows-arm64.zip
)
test "$(find "$release_dir" -maxdepth 1 -type f | wc -l)" -eq "${#expected[@]}"
for file in "${expected[@]}"; do
  test -s "$release_dir/$file"
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for platform in linux-x86_64 linux-arm64 macos-x86_64 macos-arm64 windows-x86_64 windows-arm64; do
  case "$platform" in
    linux-x86_64) extension=tar.gz; triple=x86_64-unknown-linux-gnu ;;
    linux-arm64) extension=tar.gz; triple=aarch64-unknown-linux-gnu ;;
    macos-x86_64) extension=tar.gz; triple=x86_64-apple-darwin ;;
    macos-arm64) extension=tar.gz; triple=aarch64-apple-darwin ;;
    windows-x86_64) extension=zip; triple=x86_64-pc-windows-msvc ;;
    windows-arm64) extension=zip; triple=aarch64-pc-windows-msvc ;;
  esac
  extract="$work/$platform"
  mkdir -p "$extract"
  archive=$(cd "$release_dir" && pwd)/tracy-embedded-native-$platform.$extension
  (cd "$extract" && cmake -E tar xf "$archive")
  cmake -DBUNDLE_DIR="$extract/tracy-embedded-native" -DEXPECTED_TARGET="$triple" \
    -DEXPECTED_COMMIT="$release_commit" \
    -P "$root/cmake/VerifyTracyEmbeddedNative.cmake"
done
