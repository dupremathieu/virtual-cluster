#!/usr/bin/env bash
# Convert a compressed SEAPATH .wic.gz build artifact (e.g. seapath-yocto.wic.gz,
# seapath-yocto-cluster.wic.gz, seapath-yocto-observer.wic.gz produced by the
# training/yocto build CI) into a qcow2 disk image usable by this sandbox as a
# Terraform base_image_path or VM disk.
#
# Usage:
#   scripts/wic2qcow2.sh [-o DIR] [-n NAME] [-s SIZE] [-f] <image.wic.gz>
#
# Options:
#   -o DIR    Output directory (default: images)
#   -n NAME   Output file name (default: input name with .gz -> .qcow2,
#             e.g. foo.wic.gz -> foo.wic.qcow2)
#   -s SIZE   Grow the qcow2 after conversion (qemu-img resize, e.g. 40G) so
#             'make ansible-grow-rootfs' has room to extend the root filesystem
#   -f        Overwrite the output file if it already exists
#
# A sibling '<image>.wic.bmap' is detected and reported but not required: it is
# only meaningful for bmaptool sparse flashing, qemu-img reads the full content.

set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") [-o DIR] [-n NAME] [-s SIZE] [-f] <image.wic.gz>"
  echo "  -o DIR    Output directory (default: images)"
  echo "  -n NAME   Output file name (default: foo.wic.gz -> foo.wic.qcow2)"
  echo "  -s SIZE   Resize the qcow2 after conversion (qemu-img resize, e.g. 40G)"
  echo "  -f        Overwrite the output file if it already exists"
}

OUT_DIR="images"
OUT_NAME=""
RESIZE=""
FORCE=0
POSITIONAL=()

# Options may appear before or after the positional .wic.gz argument.
while [ $# -gt 0 ]; do
  case "$1" in
    -o|--out-dir)
      [ $# -ge 2 ] || { echo "ERROR: $1 requires a value" >&2; exit 1; }
      OUT_DIR=$2; shift 2 ;;
    -n|--name)
      [ $# -ge 2 ] || { echo "ERROR: $1 requires a value" >&2; exit 1; }
      OUT_NAME=$2; shift 2 ;;
    -s|--size)
      [ $# -ge 2 ] || { echo "ERROR: $1 requires a value" >&2; exit 1; }
      RESIZE=$2; shift 2 ;;
    -f|--force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; POSITIONAL+=("$@"); break ;;
    -*) usage >&2; echo "ERROR: unknown option: $1" >&2; exit 1 ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done

if [ ${#POSITIONAL[@]} -ne 1 ]; then
  usage >&2
  exit 1
fi

WIC=${POSITIONAL[0]}

case "$WIC" in
  *.wic.gz) ;;
  *) echo "ERROR: '$WIC' does not look like a .wic.gz file" >&2; exit 1 ;;
esac
if [ ! -f "$WIC" ]; then
  echo "ERROR: no such file: $WIC" >&2
  exit 1
fi

command -v qemu-img >/dev/null || {
  echo "ERROR: qemu-img not found (install 'qemu-utils' on Debian/Ubuntu, 'qemu-img' on Fedora)" >&2
  exit 1
}

if command -v pigz >/dev/null; then
  DECOMPRESS=(pigz -dc)
else
  DECOMPRESS=(gzip -dc)
fi

BMAP="${WIC%.gz}.bmap"
if [ -f "$BMAP" ]; then
  echo "→ Found $BMAP: only used for bmaptool flashing, ignoring it."
fi

STEM=$(basename "$WIC" .gz)          # foo.wic.gz -> foo.wic
if [ -z "$OUT_NAME" ]; then
  OUT_NAME="$STEM.qcow2"             # matches release naming: *.wic.qcow2
fi
OUT_DIR=${OUT_DIR:-images}
OUT_FILE="$OUT_DIR/$OUT_NAME"

if [ -e "$OUT_FILE" ] && [ "$FORCE" -ne 1 ]; then
  echo "ERROR: $OUT_FILE already exists (use -f / FORCE=1 to overwrite)" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT_FILE")"

TMP_RAW=$(mktemp "$OUT_DIR/.wic2qcow2.raw.XXXXXX")
TMP_QCOW=$(mktemp "$OUT_DIR/.wic2qcow2.qcow2.XXXXXX")
trap 'rm -f "$TMP_RAW" "$TMP_QCOW"' EXIT

echo "→ Decompressing $WIC with ${DECOMPRESS[0]}..."
"${DECOMPRESS[@]}" -- "$WIC" > "$TMP_RAW"

echo "→ Converting to qcow2: $OUT_FILE"
# Convert and resize into temporary files, then move the result in place so an
# interrupted run never leaves a partial image behind.
qemu-img convert -p -f raw -O qcow2 "$TMP_RAW" "$TMP_QCOW"

rm -f "$TMP_RAW"

if [ -n "$RESIZE" ]; then
  echo "→ Resizing image to $RESIZE"
  qemu-img resize "$TMP_QCOW" "$RESIZE"
fi

mv -f "$TMP_QCOW" "$OUT_FILE"

echo ""
echo "Conversion complete:"
ls -lh "$OUT_FILE"
qemu-img info "$OUT_FILE"
echo ""
echo "Next steps:"
echo "  Point terraform/terraform.tfvars 'base_image_path' at it, or use it as vm_disk for ansible-deploy-vm."
[ -n "$RESIZE" ] || echo "  Tip: pass -s SIZE (e.g. -s 40G) so 'make ansible-grow-rootfs' has room to grow the rootfs."
