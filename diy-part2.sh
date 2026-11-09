#!/bin/bash
# ==============================================================================
# DIY Part 2: 在执行 make 之前执行 (补丁注入、系统菜单纯化、服务菜单排序与语法门禁)
# ==============================================================================

set -e

echo "=================================================="
echo "--> 执行 DIY Part 2: 注入底层补丁与定制配置..."
echo "=================================================="

# 1. 确保版本号对齐为 25.12.2，保证与官方发布源及 distfeeds 完全兼容
if [ -f "include/version.mk" ]; then
  sed -i -E "s/25\.12-SNAPSHOT/25.12.2/g" include/version.mk 2>/dev/null || true
fi

# 2. 强化 include/scan.mk 扫描缓存覆盖，强制使用 mv -f 防止特定环境下终端提示卡死
if [ -f "include/scan.mk" ]; then
  sed -i -E 's/\bmv[[:space:]]+(\$\(TMP_DIR\)\/\.\$\(SCAN_TARGET\)\.tmp)/mv -f \1/g' include/scan.mk 2>/dev/null || true
fi

# 3. 幂等适配 include/bpf.mk：自动探测系统 Clang/LLVM BPF 路径（优先检索 /usr/bin 与 /usr/lib/llvm-*/bin）
if [ -f "include/bpf.mk" ]; then
  if ! grep -q 'LLVM_PATH:=$(or $(shell for path in /usr/bin' include/bpf.mk 2>/dev/null; then
    sed -i '/CLANG:=\$(LLVM_PATH)\/clang/i \
  ifeq ($(LLVM_PATH),/invalid)\
    LLVM_PATH:=$(or $(shell for path in /usr/bin /usr/lib/llvm-18/bin /usr/lib/llvm-*/bin /usr/local/bin; do \\\
      test -x $$path/clang \&\& test -x $$path/llc \&\& test -x $$path/llvm-dis \&\& \\\
      test -x $$path/opt \&\& test -x $$path/llvm-strip \&\& { echo $$path; break; }; \\\
    done),/invalid)\
  endif' include/bpf.mk 2>/dev/null || true
  fi
fi

# 3.1 修复 daed / dae 源码硬编码 go >= 1.27.0 导致与系统官方内置 go 1.26 工具链冲突
python3 -c '
import os
targets = [
    ("openwrt-daede/daed/Makefile", "DAED_BUILD_DIR"),
    ("openwrt-daede/dae/Makefile", "DAE_BUILD_DIR")
]
for rel_path, bdir in targets:
    for base in ["package/custom-apps", "custom-apps", "package/feeds/custom", "feeds/custom"]:
        mf = os.path.join(base, rel_path)
        if os.path.exists(mf):
            try:
                with open(mf, "r", encoding="utf-8") as f:
                    content = f.read()
                target_marker = "\t$(TAR) --strip-components=1"
                hook = f"\tfind $({bdir}) -type f -name \"go.mod\" -exec sed -i -E '\''s/^go 1\\.[0-9]+(\\.[0-9]+)?/go 1.26/g; /^toolchain /d'\'' {{}} +"
                if target_marker in content and hook not in content:
                    lines = content.splitlines(True)
                    new_lines = []
                    for line in lines:
                        new_lines.append(line)
                        if line.startswith(target_marker):
                            new_lines.append(hook + "\n")
                    with open(mf, "w", encoding="utf-8") as f:
                        f.writelines(new_lines)
                    print(f"[+] 成功为 {mf} 注入 Go 1.26 自动兼容补丁")
            except Exception as e:
                print(f"[!] 注入 {mf} 补丁异常: {e}")
' 2>/dev/null || true

# 4. 修复 luci-app-daede 与 luci-app-honk 在线热更新脚本，适配带 @tag 仓库标签的 apk 依赖约束
for upd_sh in package/custom-apps/openwrt-daede/luci-app-daede/root/usr/share/luci-app-daede/update-pkg.sh \
              package/custom-apps/openwrt-honk/luci-app-honk/root/usr/share/luci-app-honk/update-pkg.sh; do
  if [ -f "$upd_sh" ]; then
    sed -i 's/constraint="\$PKG=\$ver"/tag=$(grep -E "^${PKG}@" \/etc\/apk\/world 2>\/dev\/null | head -1 | cut -d"@" -f2); if [ -n "$tag" ]; then constraint="${PKG}@${tag}=${ver}"; else constraint="${PKG}=${ver}"; fi/' "$upd_sh" 2>/dev/null || true
  fi
done

# 5. 修复 luci-app-honk 后台维护任务调用 nohup 导致导出备份失败 (OpenWrt busybox 环境无 nohup 命令)
honk_rpcd="package/custom-apps/openwrt-honk/luci-app-honk/root/usr/libexec/rpcd/honk"
if [ -f "$honk_rpcd" ]; then
  sed -i 's/nohup \"\$JOB_RUNNER\"/\"\$JOB_RUNNER\"/g' "$honk_rpcd" 2>/dev/null || true
fi

# 6. 修复 upstream feeds 中 sms-tool-js 的 JSON 尾随逗号语法错误
sms_json="feeds/luci/applications/luci-app-sms-tool-js/root/usr/share/luci/menu.d/luci-app-sms-tool-js.json"
if [ -f "$sms_json" ]; then
  python3 -c "
import re
p = '$sms_json'
try:
    with open(p, 'r', encoding='utf-8') as f:
        text = f.read()
    fixed = re.sub(r'\},(\s*\}\s*)$', r'}\1', text)
    if fixed != text:
        with open(p, 'w', encoding='utf-8') as f:
            f.write(fixed)
except Exception:
    pass
" 2>/dev/null || true
fi

# 7. 导入自定义 files 覆盖层
if [ -d "$GITHUB_WORKSPACE/files" ]; then
  echo "--> 正在合并 files/ 文件覆盖层..."
  mkdir -p files
  cp -r "$GITHUB_WORKSPACE/files/"* files/ 2>/dev/null || true
fi

# 8. 动态从 feeds 提取原版 luci-mod-system.json，剔除 plugins 并写入 files/ 覆盖层
orig_mod_json=$(find feeds/ -type f -path "*/luci-mod-system/root/usr/share/luci/menu.d/luci-mod-system.json" 2>/dev/null | head -n 1)
if [ -n "$orig_mod_json" ] && [ -f "$orig_mod_json" ]; then
  echo "--> 动态生成 files/ 纯净系统菜单 (移除插件，保留软件包)..."
  mkdir -p files/usr/share/luci/menu.d/
  python3 -c "
import json, sys
src = sys.argv[1]
dst = sys.argv[2]
try:
    with open(src, 'r', encoding='utf-8') as f:
        data = json.load(f)
    if 'admin/system/plugins' in data:
        del data['admin/system/plugins']
    output = json.dumps(data, indent=4, ensure_ascii=False)
    with open(dst, 'w', encoding='utf-8') as f:
        f.write(output)
except Exception as e:
    print(f'[WARN] 生成 files/luci-mod-system.json 告警: {e}', file=sys.stderr)
" "$orig_mod_json" "files/usr/share/luci/menu.d/luci-mod-system.json" || true
fi

# 9. 根据 .config 动态校验是否引入 @honk apk 源
if grep -q "CONFIG_PACKAGE_luci-app-honk=y" .config 2>/dev/null || grep -q "CONFIG_PACKAGE_honk=y" .config 2>/dev/null; then
  mkdir -p files/etc/apk/repositories.d/
  touch files/etc/apk/repositories.d/customfeeds.list
  if ! grep -q "@honk" files/etc/apk/repositories.d/customfeeds.list 2>/dev/null; then
    echo "@honk https://down.dllkids.xyz/openwrt-feed/25.12/x86_64/packages.adb" >> files/etc/apk/repositories.d/customfeeds.list
  fi
fi

# 10. 服务子菜单排序 (按 10 步进递增)
echo "--> 正在重构服务子菜单顺序 (步进 10)..."

package_selected() {
  grep -Eq "^CONFIG_PACKAGE_$1=[ym]$" .config
}

update_json_order() {
  local config_symbol="$1"
  local pkg_pattern="$2"
  local json_name="$3"
  local menu_key="$4"
  local order_val="$5"
  local rename_title="$6"
  local found=0

  if ! package_selected "$config_symbol"; then
    return 0
  fi

  while IFS= read -r -d '' file; do
    [ -f "$file" ] || continue
    found=1

    python3 -c "
import json, sys

path = sys.argv[1]
target_key = sys.argv[2]
order = int(sys.argv[3])
rename = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4] != '' else None

try:
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    modified = False
    for k, v in list(data.items()):
        if isinstance(v, dict):
            if k == target_key or k.endswith('/' + target_key.split('/')[-1]):
                v['order'] = order
                if rename:
                    v['title'] = rename
                modified = True

    if modified:
        output = json.dumps(data, indent=4, ensure_ascii=False)
        with open(path, 'w', encoding='utf-8') as f:
            f.write(output)
except Exception as err:
    print(f'[WARN] 菜单排序处理跳过: {path} -> {err}', file=sys.stderr)
" "$file" "$menu_key" "$order_val" "$rename_title" || true

  done < <(find package/ feeds/ -type f -path "$pkg_pattern/root/usr/share/luci/menu.d/$json_name" -print0 2>/dev/null)
}

# --- 1. daede (order: 10) ---
update_json_order "luci-app-daede" "*luci-app-daede*" "luci-app-daede.json" "admin/services/daede" 10 ""

# --- 2. honk (order: 20) ---
update_json_order "luci-app-honk" "*luci-app-honk*" "luci-app-honk.json" "admin/services/honk" 20 ""

# --- 3. lucky (order: 30) ---
update_json_order "luci-app-lucky" "*luci-app-lucky*" "luci-app-lucky.json" "admin/services/lucky" 30 ""
if package_selected "luci-app-lucky"; then
  find package/ feeds/ -type f -path "*luci-app-lucky*" -name "lucky.lua" \
    -exec sed -i -E 's/_([[:space:]]*\("Lucky"\)),[[:space:]]*-?[0-9]+/_("Lucky"), 30/g' {} + 2>/dev/null || true
fi

# --- 4. rtp2httpd (order: 40) ---
update_json_order "luci-app-rtp2httpd" "*luci-app-rtp2httpd*" "luci-app-rtp2httpd.json" "admin/services/rtp2httpd" 40 ""

# --- 5. iptv-seven-days (order: 50) ---
if package_selected "luci-app-iptv-seven-days"; then
  find package/ feeds/ -type f -path "*luci-app-iptv-seven-days*menu.json" \
    -exec sed -i -E 's/"order":[[:space:]]*[0-9]+/"order": 50/g' {} + 2>/dev/null || true
fi

# --- 6. upnp (order: 60) ---
update_json_order "luci-app-upnp" "*luci-app-upnp*" "luci-app-upnp.json" "admin/services/upnp" 60 ""

# --- 7. dockerman (order: 70 & 统一显示名为 Docker) ---
update_json_order "luci-app-dockerman" "*luci-app-dockerman*" "luci-app-dockerman.json" "admin/services/dockerman" 70 "Docker"
if package_selected "luci-app-dockerman"; then
  find package/ feeds/ -type f -path "*luci-app-dockerman*" -name "*.po" \
    -exec sed -i 's|msgstr "Dockerman JS"|msgstr "Docker"|g; s|msgstr "Dockerman"|msgstr "Docker"|g' {} + 2>/dev/null || true
fi

# 11. JSON 语法自检门禁
echo "--> 正在执行 JSON 语法自检门禁..."
python3 -c "
import json, os, sys

invalid = []
for root_dir in ['package', 'feeds', 'files']:
    if not os.path.exists(root_dir):
        continue
    for root, _, files in os.walk(root_dir):
        for f in files:
            if f.endswith('.json') and 'menu.d' in root:
                p = os.path.join(root, f)
                try:
                    with open(p, 'r', encoding='utf-8') as fp:
                        json.load(fp)
                except Exception as err:
                    invalid.append(f'{p}: {err}')

if invalid:
    for item in invalid:
        print(f'[ERROR] JSON 语法校验失败: {item}', file=sys.stderr)
    print('[ERROR] 发现损坏的 LuCI 菜单文件，已停止编译。', file=sys.stderr)
    raise SystemExit(1)
else:
    print('[OK] 所有 LuCI 菜单 JSON 格式严格通过校验！')
"

echo "--> DIY Part 2 执行成功！"
