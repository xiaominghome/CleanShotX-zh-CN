#!/bin/bash
# CleanShot X 简体中文语言包 · 卸载（恢复英文）
set -uo pipefail
cd "$(dirname "$0")"

BUNDLE_ID="pl.maketheweb.cleanshotx"
LPROJ="zh-Hans.lproj"
NIBS="MainMenu NameTemplateWindow ANResizeControlViewController ChangelogView RenewLicense"

find_app() {
  # 与安装脚本一致：标准位置优先，Spotlight 只作兜底（它会把备份/旧副本也列出来）
  [ -n "${1:-}" ] && [ -d "$1" ] && { echo "$1"; return; }
  local p
  for p in "/Applications/CleanShot X.app" "${HOME}/Applications/CleanShot X.app"; do
    [ -d "${p}" ] && [ -x "${p}/Contents/MacOS/CleanShot X" ] && { echo "${p}"; return; }
  done
  while IFS= read -r p; do
    [ -z "${p}" ] && continue
    case "${p}" in
      *.orig/*|*backup*|*/.Trash/*) continue ;;
    esac
    [ -x "${p}/Contents/MacOS/CleanShot X" ] && { echo "${p}"; return; }
  done <<< "$(mdfind "kMDItemCFBundleIdentifier == '${BUNDLE_ID}'" 2>/dev/null)"
}

APP=$(find_app "${1:-}")
[ -z "${APP}" ] && { echo "✗ 没有找到 CleanShot X.app"; exit 1; }
RES="${APP}/Contents/Resources"

echo "=============================================="
echo " CleanShot X 简体中文语言包 · 卸载"
echo "=============================================="

[ -d "${APP}" ] || { echo "✗ 未找到 ${APP}"; exit 1; }

if [ -w "/Applications" ] && [ -w "${RES}" ]; then SUDO=""; else SUDO="sudo"; fi

echo "→ 退出 CleanShot X ..."
pkill -x "CleanShot X" 2>/dev/null
pkill -x "LaunchAtLoginHelper" 2>/dev/null
sleep 2

# 1. 还原原版 nib
echo "→ 还原原版 nib ..."
for n in ${NIBS}; do
  if [ -f "${RES}/en.lproj/${n}.nib" ]; then
    ${SUDO} mv -f "${RES}/en.lproj/${n}.nib" "${RES}/${n}.nib"
    echo "   en.lproj/${n}.nib → Resources/"
  fi
done
if [ -d "${RES}/en.lproj" ] && [ -z "$(ls -A "${RES}/en.lproj" 2>/dev/null)" ]; then
  ${SUDO} rm -rf "${RES}/en.lproj" && echo "   en.lproj/ 已清空移除"
fi

# 2. 还原框架语言文件
echo "→ 还原框架语言文件 ..."
BK="${HOME}/.cleanshot-x-cn-backup"
for pair in "Lava_Lava.bundle:Lava_Lava.strings" "Legit_Legit.bundle:Legit_Legit.strings"; do
  BNAME="${pair%%:*}"
  FNAME="${pair##*:}"
  TGT="${RES}/${BNAME}/Contents/Resources/zh-Hans.lproj/Localizable.strings"
  if [ -f "${BK}/${FNAME}.orig" ] && [ -f "${TGT}" ]; then
    ${SUDO} cp "${BK}/${FNAME}.orig" "${TGT}"
    echo "   ${BNAME} → 已还原"
  fi
done

# 3. 删掉语言包
echo "→ 移除 ${LPROJ} ..."
[ -d "${RES}/${LPROJ}" ] && ${SUDO} rm -rf "${RES}/${LPROJ}"

# 3b. （公开版无运行时注入，无需还原）

# 4. 重签名
echo "→ 重新签名（ad-hoc）..."
${SUDO} codesign --force --deep --sign - "${APP}" 2>/dev/null
${SUDO} xattr -dr com.apple.quarantine "${APP}" 2>/dev/null
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "${APP}" 2>/dev/null

# 5. 校验
echo "→ 校验 ..."
FAIL=0
if codesign --verify --deep "${APP}" 2>/dev/null; then echo "  ✓ 签名有效"; else echo "  ✗ 签名校验失败"; FAIL=1; fi
[ -d "${RES}/${LPROJ}" ] && { echo "  ✗ 语言包仍存在"; FAIL=1; } || echo "  ✓ 语言包已移除"
[ -f "${RES}/MainMenu.nib" ] && echo "  ✓ 原版 MainMenu.nib 已复位" || { echo "  ✗ 原版 MainMenu.nib 缺失"; FAIL=1; }

cat <<'EOF'

==============================================
 卸载完成，CleanShot X 已恢复英文
==============================================

  重签名后若截图/录屏失效，请到
  系统设置 → 隐私与安全性 → 屏幕录制，
  取消勾选 CleanShot X 再重新勾选，然后重启应用。

EOF
[ "${FAIL}" = "1" ] && exit 1
open -a "CleanShot X"
