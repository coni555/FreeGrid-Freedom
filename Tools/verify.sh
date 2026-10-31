#!/bin/bash
# FreeGrid 的标准验证：在分支自己的模拟器上跑指定测试，参数固定成 AGENTS.md「测试」里的约定。
#
#   Tools/verify.sh --sim FG-UI --only FreeGridTests/DailyBurnTests [--only ...] [--mac]
#   Tools/verify.sh --sim FG-UI --full --mac        # 提审前
#   Tools/verify.sh --sim FG-UI                     # 不跑测试，只编译 App 和测试
#
# 在哪个 worktree 里运行就验证哪个分支；分支 worktree 里还没有这个脚本时，
# 用主仓的绝对路径调用：~/Desktop/FreeGrid/Tools/verify.sh。
set -euo pipefail
. "$(dirname "$0")/sim-common.sh"

usage() { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

SIM=""; FULL=0; MAC=0; DERIVED_NAME=""; ONLY=()
while [ $# -gt 0 ]; do
  case "$1" in
    --sim) SIM=${2:-}; shift 2 ;;
    --only) ONLY+=("-only-testing:${2:?--only 后面要写测试，如 FreeGridTests/DailyBurnTests}"); shift 2 ;;
    --full) FULL=1; shift ;;
    --mac) MAC=1; shift ;;
    --derived) DERIVED_NAME=${2:-}; shift 2 ;;
    -h|--help) usage ;;
    *) echo "✗ 不认识的参数：$1" >&2; usage 1 ;;
  esac
done
[ -n "$SIM" ] || { echo "✗ 要用 --sim 指定这个分支的模拟器" >&2; usage 1; }
[ "$FULL" = 1 ] && [ ${#ONLY[@]} -gt 0 ] && die "--full 和 --only 二选一"

resolve_sim "$SIM"
guard_fg_main
guard_sim_idle

DERIVED="$MAIN_REPO/_local/derived/${DERIVED_NAME:-$SHORT}"
mkdir -p "$RUN_DIR"
LOG="$RUN_DIR/verify-$STAMP.log"
RESULT="$RUN_DIR/verify-$STAMP.xcresult"
STATUS=0

cd "$WORKTREE"
echo "== $BRANCH @ $(git rev-parse --short HEAD)  →  $SIM_NAME ($SIM_UDID)"
echo "· 构建缓存：$DERIVED"

COMMON=(-project FreeGrid.xcodeproj -scheme FreeGrid
        -destination "platform=iOS Simulator,id=$SIM_UDID"
        -derivedDataPath "$DERIVED" -parallel-testing-enabled NO)

if [ "$FULL" = 0 ] && [ ${#ONLY[@]} -eq 0 ]; then
  echo "· 没指定测试：只编译（build-for-testing）"
  if xcodebuild build-for-testing "${COMMON[@]}" > "$LOG" 2>&1; then
    echo "✓ iOS 编译通过"
  else
    echo "✗ iOS 编译失败，日志：$LOG"; grep -E 'error:' "$LOG" | sort -u | head -20; STATUS=1
  fi
else
  snapshot_container before-verify
  [ "$FULL" = 1 ] && echo "· 全量测试（单元 + UI）" || printf '· 只跑：%s\n' "${ONLY[@]#-only-testing:}"
  set +e
  xcodebuild test "${COMMON[@]}" -resultBundlePath "$RESULT" ${ONLY[@]+"${ONLY[@]}"} > "$LOG" 2>&1
  CODE=$?
  set -e
  if [ -d "$RESULT" ]; then
    xcrun xcresulttool get test-results summary --path "$RESULT" | /usr/bin/python3 -I -c '
import json, sys
s = json.load(sys.stdin)
mark = "✓" if s["result"] == "Passed" else "✗"
print("%s 测试 %s：通过 %d，失败 %d，跳过 %d" % (mark, s["result"], s["passedTests"], s["failedTests"], s["skippedTests"]))
for f in s.get("testFailures", [])[:20]:
    name = f.get("testIdentifierString") or f.get("testName")
    text = (f.get("failureText") or "").strip().splitlines()
    print("  - %s: %s" % (name, text[0] if text else ""))'
  else
    echo "✗ 没有生成测试结果（多半是编译失败），日志：$LOG"
    grep -E 'error:' "$LOG" | sort -u | head -20
  fi
  [ "$CODE" = 0 ] || STATUS=1
  echo "· 结果包：$RESULT"
fi

if [ "$MAC" = 1 ]; then
  MAC_LOG="$RUN_DIR/verify-$STAMP-mac.log"
  if xcodebuild build -project FreeGrid.xcodeproj -scheme FreeGrid -destination 'platform=macOS' \
       -derivedDataPath "$DERIVED-mac" CODE_SIGNING_ALLOWED=NO > "$MAC_LOG" 2>&1; then
    echo "✓ macOS 构建通过"
  else
    echo "✗ macOS 构建失败，日志：$MAC_LOG"; grep -E 'error:' "$MAC_LOG" | sort -u | head -20; STATUS=1
  fi
fi

if git diff --check HEAD > /dev/null; then
  echo "✓ git diff --check 通过"
else
  echo "✗ git diff --check 有问题："; git diff --check HEAD | head -20; STATUS=1
fi

echo "· 日志：$LOG"
exit $STATUS
