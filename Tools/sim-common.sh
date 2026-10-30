# verify.sh 和 install-sim.sh 共用：定位工作区、找模拟器、查占用、存账本快照。
# 只被 source，不单独运行。

BUNDLE_ID="cn.conilab.FreeGrid"

die() { echo "✗ $*" >&2; exit 1; }

# 当前所在的 worktree，以及放 _local 的主仓（分支 worktree 也共用主仓的 _local）。
WORKTREE=$(git rev-parse --show-toplevel 2>/dev/null) || die "要在 FreeGrid 仓库或它的 worktree 里运行"
[ -d "$WORKTREE/FreeGrid.xcodeproj" ] || die "$WORKTREE 不是 FreeGrid 工程"
MAIN_REPO=$(dirname "$(git -C "$WORKTREE" rev-parse --path-format=absolute --git-common-dir)")
BRANCH=$(git -C "$WORKTREE" branch --show-current)
[ -n "$BRANCH" ] || die "当前是 detached HEAD，先切到分支"
SHORT=${BRANCH##*/}
TODAY=$(date +%F)
STAMP=$(date +%H%M%S)
RUN_DIR="$MAIN_REPO/_local/runs/$TODAY/$SHORT"

# 按名字找模拟器 UDID。找不到就停：新建、克隆模拟器会下载系统资源，要用户同意。
sim_udid() {
  xcrun simctl list devices -j | /usr/bin/python3 -I -c '
import json, sys
name = sys.argv[1]
for devices in json.load(sys.stdin)["devices"].values():
    for d in devices:
        if d["name"] == name and d.get("isAvailable", True):
            print(d["udid"]); sys.exit(0)
sys.exit(1)' "$1"
}

list_fg_sims() {
  xcrun simctl list devices | grep -E '^ +FG-' | sed -E 's/^ +//; s/ \(([0-9A-F-]+)\) / (\1) /'
}

resolve_sim() {
  SIM_NAME=$1
  SIM_UDID=$(sim_udid "$SIM_NAME") || {
    echo "✗ 没有叫 $SIM_NAME 的模拟器。现有的：" >&2
    list_fg_sims >&2
    die "不要新建或克隆模拟器；分支对应哪台看 HANDOFF.md「模拟器与账本」"
  }
}

# FG-Main 只装、只跑 main。
guard_fg_main() {
  if [ "$SIM_NAME" = "FG-Main" ] && [ "$BRANCH" != "main" ]; then
    die "FG-Main 只给 main 用，当前分支是 ${BRANCH}。分支用它自己的模拟器（见 HANDOFF.md「模拟器与账本」）"
  fi
}

# 别的任务正在用这台模拟器构建或测试时不抢。
guard_sim_idle() {
  local busy
  busy=$(pgrep -fl xcodebuild | grep "$SIM_UDID" || true)
  [ -z "$busy" ] || die "$SIM_NAME 正被另一个 xcodebuild 使用：
$busy
等它结束，或换这个分支自己的模拟器"
}

# 单元测试的宿主就是 App，会用这台模拟器上的账本启动；装新版也会迁移账本。动之前先打包数据容器。
snapshot_container() {
  local reason=$1 container dest
  # 关机的模拟器查不到 App 容器，会被误当成「没装」而跳过快照，所以先开机。
  xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
  container=$(xcrun simctl get_app_container "$SIM_UDID" "$BUNDLE_ID" data 2>/dev/null) || {
    echo "· $SIM_NAME 上还没装 FreeGrid，跳过账本快照"
    return 0
  }
  mkdir -p "$MAIN_REPO/_local/snapshots/auto"
  dest="$MAIN_REPO/_local/snapshots/auto/$SIM_NAME-$reason-$SHORT-$TODAY-$STAMP.tgz"
  tar -czf "$dest" -C "$container" . || die "账本快照失败，停止（$dest）"
  echo "· 账本快照：$dest"
  # 自动快照每台模拟器只留最近 5 份；手动存的快照在上一级目录，不动。
  ls -t "$MAIN_REPO/_local/snapshots/auto/$SIM_NAME-"*.tgz 2>/dev/null | tail -n +6 | while read -r old; do rm -f "$old"; done
}
