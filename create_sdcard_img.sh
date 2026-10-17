#!/usr/bin/env bash
# ==============================================================================
# create_sdcard_img.sh - Create raw FAT32 SDCard image for Fab Agon Emulator
# Uses macOS native hdiutil to create and populate an unpartitioned FAT32 image.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_EMU_DIR="$SCRIPT_DIR/../fab-agon-emulator-v1.2.6-macos-arm64"

SRC_DIR="${1:-$DEFAULT_EMU_DIR/sdcard}"
IMG_PATH="${2:-$DEFAULT_EMU_DIR/sdcard.img}"
SIZE_MB="${SIZE_MB:-64}"
VOL_NAME="${VOL_NAME:-AGONSD}"

if [[ ! -d "$SRC_DIR" ]]; then
    echo "Error: Source directory not found: $SRC_DIR" >&2
    echo "Usage: $0 [source_directory] [output_image_path]" >&2
    exit 1
fi

if ! command -v hdiutil >/dev/null 2>&1; then
    echo "Error: Required command 'hdiutil' not found." >&2
    exit 1
fi

if (( SIZE_MB < 33 )); then
    echo "Error: FAT32 requires a volume size of at least 33MB (specified: ${SIZE_MB}MB)." >&2
    exit 1
fi

ATTACHED_DEV=""
MOUNT_DIR=""

cleanup() {
    if [[ -n "$ATTACHED_DEV" ]]; then
        hdiutil detach "$ATTACHED_DEV" -force >/dev/null 2>&1 || true
    fi
    if [[ -n "$MOUNT_DIR" && -d "$MOUNT_DIR" ]]; then
        rmdir "$MOUNT_DIR" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

mkdir -p "$(dirname "$IMG_PATH")"

echo "==> Creating ${SIZE_MB}MB FAT32 disk image: $IMG_PATH"
# hdiutil creates an unpartitioned FAT32 image, automatically appending .dmg
hdiutil create -size "${SIZE_MB}m" -layout NONE -fs "MS-DOS FAT32" -volname "$VOL_NAME" -ov -quiet "$IMG_PATH"
mv "${IMG_PATH}.dmg" "$IMG_PATH"

echo "==> Mounting image to copy files..."
MOUNT_DIR=$(mktemp -d /tmp/agon_sd_XXXXXX)
ATTACH_OUT=$(hdiutil attach -nobrowse -noverify -noautofsck -noautoopen "$IMG_PATH" -mountpoint "$MOUNT_DIR")
ATTACHED_DEV=$(echo "$ATTACH_OUT" | grep -o '/dev/disk[0-9]*' | head -n1)

if [[ -z "$ATTACHED_DEV" ]]; then
    echo "Error: Failed to mount $IMG_PATH at $MOUNT_DIR" >&2
    exit 1
fi

echo "==> Copying contents from $SRC_DIR..."
cp -R "$SRC_DIR/." "$MOUNT_DIR/"

echo "==> Stripping macOS metadata..."
rm -rf "$MOUNT_DIR/.fseventsd"
find "$MOUNT_DIR" \( -name "._*" -o -name ".DS_Store" \) -delete 2>/dev/null || true

echo "==> Finalizing image..."
hdiutil detach "$ATTACHED_DEV" >/dev/null
ATTACHED_DEV=""
rmdir "$MOUNT_DIR"
MOUNT_DIR=""

echo "==> Successfully created: $IMG_PATH"
