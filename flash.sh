#!/bin/bash
# Convenient launcher for SP Flash Tool with B760H firmware
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_DIR="$SCRIPT_DIR/tools/spflash/SP_Flash_Tool-5.1916_Linux"
SCATTER="$SCRIPT_DIR/firmware/extracted/MT8127_Android_scatter.txt"

echo "=========================================================="
echo " SP Flash Tool v5.1916 (Linux) — ZTE B760H Flasher"
echo " Scatter: $SCATTER"
echo "=========================================================="

if [ "${1:-}" = "--gui" ]; then
    echo "Mode: Graphical UI"
    echo "Instructions:"
    echo " 1. Select Scatter File: $SCATTER"
    echo " 2. Select 'Download Only' and click the green 'Download' button."
    echo " 3. Plug in the USB cable to B760H (powered off)."
    echo ""
    cd "$TOOL_DIR"
    exec ./flash_tool.sh
fi

echo "Mode: Headless CLI (Zero-touch automated flashing)"
echo ""
echo "Instructions:"
echo " 1. Ensure B760H is powered OFF (unplug barrel / USB power)."
echo " 2. Plug USB cable into the B760H (port next to MicroSD slot)."
echo " 3. The CLI flasher will detect BROM and flash automatically."
echo ""
echo "Tip: Run './flash.sh --gui' if you prefer the graphical interface."
echo "----------------------------------------------------------"

export LD_LIBRARY_PATH="$TOOL_DIR/lib:${LD_LIBRARY_PATH:-}"
exec "$TOOL_DIR/flash_tool" \
    -d "$TOOL_DIR/MTK_AllInOne_DA.bin" \
    -s "$SCATTER" \
    -c download
