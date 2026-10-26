#!/bin/bash
# CleanShot X 简体中文语言包 · 安装（公开版 / 纯资源）
#
# 三条覆盖路径（全部为**资源替换**，不改动任何二进制、不做注入）：
#   1) Localizable.strings   → SwiftUI / NSLocalizedString 查表（设置窗口正文等）
#   2) 本地化 nib            → AppKit 菜单（状态栏菜单、编辑菜单等）
#   3) 框架资源包语言文件     → Lava / Legit 是静态链接的框架，组件查自己的表
#
#   坑：CleanShot 的原版 nib 直接躺在 Contents/Resources/ 根目录下，
#   而 CFBundle 的资源查找里「根目录」优先于「<语言>.lproj」，
#   所以必须先把原版 nib 挪进 en.lproj/，zh-Hans.lproj/ 里的汉化版才会被加载。
set -uo pipefail
cd "$(dirname "$0")"

BUNDLE_ID="pl.maketheweb.cleanshotx"
LPROJ="zh-Hans.lproj"
NIBS="MainMenu NameTemplateWindow ANResizeControlViewController ChangelogView RenewLicense"

# ---- 定位 CleanShot X.app（不写死路径，别人的电脑可能装在别处）----
find_app() {
  # 顺序很关键：Spotlight 会把磁盘上的任何副本都列出来（备份、旧测试副本…），
  # 必须让标准安装位置优先，否则会改错目标。
  # 1) 显式指定：双击时把 app 拖到脚本上，或命令行传参
  [ -n "${1:-}" ] && [ -d "$1" ] && { echo "$1"; return; }
  # 2) 标准位置
  local p
  for p in "/Applications/CleanShot X.app" "${HOME}/Applications/CleanShot X.app"; do
    [ -d "${p}" ] && [ -x "${p}/Contents/MacOS/CleanShot X" ] && { echo "${p}"; return; }
  done
  # 3) Spotlight 兜底，但排除备份/测试副本
  while IFS= read -r p; do
    [ -z "${p}" ] && continue
    case "${p}" in
      *.orig/*|*backup*|*/.Trash/*) continue ;;
    esac
    [ -x "${p}/Contents/MacOS/CleanShot X" ] && { echo "${p}"; return; }
  done <<< "$(mdfind "kMDItemCFBundleIdentifier == '${BUNDLE_ID}'" 2>/dev/null)"
}

APP=$(find_app "${1:-}")
if [ -z "${APP}" ]; then
  echo "✗ 没有找到 CleanShot X.app"
  echo "  请先安装 CleanShot X，或把 CleanShot X.app 拖到本脚本上再运行。"
  exit 1
fi
RES="${APP}/Contents/Resources"

echo "=============================================="
echo " CleanShot X 简体中文语言包 · 安装"
echo "=============================================="

[ -d "${APP}" ] || { echo "✗ 未找到 ${APP}"; exit 1; }
[ -d "${LPROJ}" ] || { echo "✗ 语言包目录缺失：$(pwd)/${LPROJ}"; exit 1; }

GOT_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "${APP}/Contents/Info.plist" 2>/dev/null)
VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP}/Contents/Info.plist" 2>/dev/null)
if [ "${GOT_ID}" != "${BUNDLE_ID}" ]; then
  echo "✗ Bundle ID 不符：期望 ${BUNDLE_ID}，实际 ${GOT_ID}"
  exit 1
fi
echo "目标应用：${APP}（版本 ${VER}）"

if [ -w "/Applications" ] && [ -w "${RES}" ]; then
  SUDO=""; echo "权限：直接写入（无需密码）"
else
  SUDO="sudo"; echo "权限：需要管理员密码"
fi

# 1. 退出应用
echo "→ 退出 CleanShot X ..."
pkill -x "CleanShot X" 2>/dev/null
pkill -x "LaunchAtLoginHelper" 2>/dev/null
sleep 2

# 2. 首次安装记录原始信息（供卸载还原）
BK="${HOME}/.cleanshot-x-cn-backup"
if [ ! -d "${BK}" ]; then
  mkdir -p "${BK}"
  cp "${APP}/Contents/Info.plist" "${BK}/Info.plist" 2>/dev/null
  cp -R "${APP}/Contents/_CodeSignature" "${BK}/_CodeSignature" 2>/dev/null
  echo "→ 已记录原始签名信息 → ${BK}"
fi

# 3. nib 内容指纹守卫
#    汉化 nib 是按特定一份原版 nib 生成的（NIBArchive 里对象按索引互相引用）。
#    用「版本号是否相同」来判太粗：小版本升级往往只改代码、nib 一字未动，
#    那种情况汉化 nib 完全可用。所以这里直接比对**原版 nib 的 SHA-256**：
#      指纹一致 → 界面没动过，放心铺汉化 nib
#      指纹不一致 → 界面改了，宁可跳过（铺旧 nib 会把新加的菜单项弄丢），
#                    菜单栏保持英文，其余界面不受影响。
DO_NIB=1
if [ -f "nib-manifest.txt" ]; then
  CHANGED=""
  MISSING=""
  for n in ${NIBS}; do
    want=$(awk -v k="${n}" '$1 == k { print $2 }' "nib-manifest.txt")
    [ -z "${want}" ] && continue
    # 目标机上的原版 nib：首次装在根目录，装过一次后在 en.lproj
    src="${RES}/${n}.nib"
    [ -f "${src}" ] || src="${RES}/en.lproj/${n}.nib"
    if [ ! -f "${src}" ]; then MISSING="${MISSING} ${n}"; continue; fi
    got=$(shasum -a 256 "${src}" | cut -d' ' -f1)
    [ "${got}" != "${want}" ] && CHANGED="${CHANGED} ${n}"
  done
  if [ -n "${MISSING}" ]; then
    DO_NIB=0
    echo "→ ⚠ 找不到原版 nib：${MISSING}"
    echo "   已跳过 nib 汉化（菜单栏保持英文），其余界面不受影响。"
  elif [ -n "${CHANGED}" ]; then
    DO_NIB=0
    echo "→ ⚠ 本机界面与语言包不一致，涉及：${CHANGED}"
    echo "   已跳过 nib 汉化 —— 菜单栏保持英文，其余界面不受影响。"
    echo "   （这通常意味着 CleanShot X 换过界面；重新生成语言包即可恢复）"
  else
    echo "→ nib 指纹一致，菜单栏将一并汉化"
  fi
elif [ -f "nib-version.txt" ]; then
  # 没有指纹清单时退回版本比对
  BUILT_V=$(tr -d '[:space:]' < "nib-version.txt")
  if [ -n "${BUILT_V}" ] && [ "${BUILT_V}" != "${VER}" ]; then
    DO_NIB=0
    echo "→ ⚠ nib 版本不匹配（包基于 ${BUILT_V}，本机 ${VER}）"
    echo "   已跳过 nib 汉化，菜单栏可能仍为英文；其余界面不受影响。"
  fi
fi

# 3b. 把原版 nib 挪进 en.lproj（腾出位置给汉化版）
if [ "${DO_NIB}" = "1" ]; then
  echo "→ 归置原版 nib 到 en.lproj ..."
  ${SUDO} mkdir -p "${RES}/en.lproj"
  for n in ${NIBS}; do
    if [ -f "${RES}/${n}.nib" ]; then
      ${SUDO} mv "${RES}/${n}.nib" "${RES}/en.lproj/${n}.nib"
      echo "   ${n}.nib → en.lproj/"
    fi
  done
fi

# 4. 铺汉化语言包（nib 被跳过时只铺词表）
echo "→ 安装 ${LPROJ} ..."
[ -d "${RES}/${LPROJ}" ] && ${SUDO} rm -rf "${RES}/${LPROJ}"
${SUDO} mkdir -p "${RES}/${LPROJ}"
${SUDO} cp "${LPROJ}/Localizable.strings" "${RES}/${LPROJ}/Localizable.strings"
if [ "${DO_NIB}" = "1" ]; then
  for n in ${NIBS}; do
    [ -f "${LPROJ}/${n}.nib" ] && ${SUDO} cp "${LPROJ}/${n}.nib" "${RES}/${LPROJ}/${n}.nib"
  done
fi

# 4b. 框架自带资源包（Lava / Legit）的中文语言文件
#     静态链接框架里的组件查的是框架自己的 Localizable.strings，必须一并覆盖
echo "→ 合并框架语言文件 ..."
for pair in "Lava_Lava.bundle:Lava_Lava.strings" "Legit_Legit.bundle:Legit_Legit.strings"; do
  BNAME="${pair%%:*}"
  FNAME="${pair##*:}"
  TGT="${RES}/${BNAME}/Contents/Resources/zh-Hans.lproj/Localizable.strings"
  if [ -f "${TGT}" ] && [ -f "bundle-overrides/${FNAME}" ]; then
    [ -f "${BK}/${FNAME}.orig" ] || ${SUDO} cp "${TGT}" "${BK}/${FNAME}.orig"
    ${SUDO} cp "bundle-overrides/${FNAME}" "${TGT}"
    echo "   ${BNAME} → 已合并"
  fi
done

# 说明：本「公开版」只替换语言资源文件，不做任何二进制注入。
#       因此不需要改动 MacOS 目录，也不涉及任何运行时库。

# 5. 重签名（改动包内文件会破坏原签名）
echo "→ 重新签名（ad-hoc）..."
${SUDO} codesign --force --deep --sign - "${APP}" 2>/dev/null

# 6. 清隔离属性、刷新 LaunchServices
${SUDO} xattr -dr com.apple.quarantine "${APP}" 2>/dev/null
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "${APP}" 2>/dev/null

# 7. 校验
echo "→ 校验 ..."
FAIL=0
if codesign --verify --deep "${APP}" 2>/dev/null; then echo "  ✓ 签名有效"; else echo "  ✗ 签名校验失败"; FAIL=1; fi
if [ -f "${RES}/${LPROJ}/Localizable.strings" ]; then
  # 用 plutil 转 XML 后数 <key>，不依赖 python（别人电脑上没装命令行工具也不会弹窗）
  N=$(plutil -convert xml1 -o - "${RES}/${LPROJ}/Localizable.strings" 2>/dev/null | grep -c '<key>')
  echo "  ✓ 主语言包已就位（${N} 条词条）"
else
  echo "  ✗ 主语言包缺失"; FAIL=1
fi
if [ "${DO_NIB}" = "1" ]; then
  for n in ${NIBS}; do
    if [ -f "${RES}/${LPROJ}/${n}.nib" ] && [ -f "${RES}/${n}.nib" ]; then
      echo "  ✗ ${n}.nib 仍留在根目录，会被优先加载"; FAIL=1
    fi
  done
  if [ -f "${RES}/${LPROJ}/MainMenu.nib" ] && [ ! -f "${RES}/MainMenu.nib" ]; then
    echo "  ✓ 主菜单本地化生效条件满足"
  fi
else
  echo "  · nib 已按版本守卫跳过（属预期行为）"
fi
[ "${FAIL}" = "1" ] && exit 1

cat <<'EOF'

==============================================
 ✓ 安装完成，正在启动 CleanShot X
==============================================

  · 若界面仍是英文：完全退出应用（菜单栏图标 → Quit）后重新打开
  · 若提示需要「屏幕录制」「辅助功能」权限：这是重签名导致的，
    在 系统设置 → 隐私与安全性 里取消勾选再重新勾选即可
  · 恢复英文：双击『卸载.command』

EOF
open -a "CleanShot X"

