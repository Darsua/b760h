#!/bin/bash
# Convenient launcher for SP Flash Tool with B760H firmware
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_DIR="$SCRIPT_DIR/tools/spflash/SP_Flash_Tool-5.1916_Linux"
SCATTER="$SCRIPT_DIR/firmware/extracted/MT8127_Android_scatter.txt"

echo "=========================================================="
echo " Starting SP Flash Tool v5.1916 (Linux)"
echo " Scatter file: $SCATTER"
echo "=========================================================="
echo ""
echo "Instructions in GUI:"
echo " 1. Click 'choose' next to 'Scatter-loading File' and select:"
echo "    $SCATTER"
echo " 2. Ensure 'Download Only' or 'Format All + Download' is selected."
echo " 3. Click the green 'Download' button."
echo " 4. Connect the USB cable to B760H (powered off), then plug in 12V power."
echo " 5. Wait for the green checkmark circle to appear (~60s)."
echo ""

cd "$TOOL_DIR"
exec ./flash_tool.sh "$@"
