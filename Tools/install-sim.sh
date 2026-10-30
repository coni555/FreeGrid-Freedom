#!/bin/bash
# 把当前分支装到它自己的模拟器上给用户看：先存账本快照，再构建、安装、启动。
#
#   Tools/install-sim.sh --sim FG-UI              # 分支预览，Debug
#   Tools/install-sim.sh --sim FG-UI --release    # 看真实用户看到的样子
#   Tools/install-sim.sh --sim FG-Main            # 只允许 main，自动用 Release
#
# 在哪个 worktree 里运行就装哪个分支；分支 worktree 里还没有这个脚本时，
# 用主仓的绝对路径调用：~/Desktop/FreeGrid/Tools/install-sim.sh。
set -euo pipefail
. "$(dirname "$0")/sim-common.sh"

usage() { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

SIM=""; CONFIG=Debug; LAUNCH=1; DERIVED_NAME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --sim) SIM=${2:-}; shift 2 ;;
    --release) CONFIG=Release; shift ;;
    --no-launch) LAUNCH=0; shift ;;
    --derived) DERIVED_NAME=${2:-}; shift 2 ;;
    -h|--help) usage ;;
    *) echo "✗ 不认识的参数：$1" >&2; usage 1 ;;
  esac
done
[ -n "$SIM" ] || { echo "✗ 要用 --sim 指定这个分支的模拟器" >&2; usage 1; }

resolve_sim "$SIM"
guard_fg_main
guard_sim_idle

cd "$WORKTREE"
if [ "$SIM_NAME" = "FG-Main" ]; then
  # FG-Main 是用户眼里的 main：装已提交的 main，用 Release，没有调试卡。
  CONFIG=Release
  dirty=$(git status --porcelain -- FreeGrid FreeGridWidgets Shared FreeGrid.xcodeproj Config)
  [ -z "$dirty" ] || die "main 的源码有未提交改动，FG-Main 只装已提交的 main：
$dirty"
fi

DERIVED="$MAIN_REPO/_local/derived/${DERIVED_NAME:-$SHORT}"
mkdir -p "$RUN_DIR"
LOG="$RUN_DIR/install-$STAMP.log"
APP="$DERIVED/Build/Products/$CONFIG-iphonesimulator/FreeGrid.app"
HEAD_SHORT=$(git rev-parse --short HEAD)

echo "== $BRANCH @ $HEAD_SHORT ($CONFIG)  →  $SIM_NAME ($SIM_UDID)"
xcodebuild build -project FreeGrid.xcodeproj -scheme FreeGrid -configuration "$CONFIG" \
  -destination "platform=iOS Simulator,id=$SIM_UDID" -derivedDataPath "$DERIVED" \
  -parallel-testing-enabled NO > "$LOG" 2>&1 \
  || { grep -E 'error:' "$LOG" | sort -u | head -20; die "构建失败，日志：$LOG"; }
echo "✓ 构建通过"

snapshot_container before-install
xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
xcrun simctl install "$SIM_UDID" "$APP"
echo "✓ 已装到 $SIM_NAME"
if [ "$LAUNCH" = 1 ]; then
  # Xcode 27 起模拟器窗口在 DeviceHub 里，没有 Simulator.app 了；打不开窗口也照样启动
  open -a Simulator --args -CurrentDeviceUDID "$SIM_UDID" 2>/dev/null \
    || open -a "$(xcode-select -p)/../Applications/DeviceHub.app" 2>/dev/null || true
  xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID" > /dev/null
  echo "✓ 已启动"
fi
echo "· 记得更新 HANDOFF.md「模拟器与账本」：$SIM_NAME = $BRANCH $HEAD_SHORT ${CONFIG}（${TODAY}）"
echo "· 日志：$LOG"
