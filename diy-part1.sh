#!/bin/bash
# ==============================================================================
# DIY Part 1: 在拉取 feeds 之前执行 (Feeds 订阅配置与自定义插件源初始化)
# ==============================================================================

set -e

echo "=================================================="
echo "--> 执行 DIY Part 1: 配置自定义 Feed 与插件源码..."
echo "=================================================="

# 1. 解除官方 Feeds 的 Commit 静态锁定，全面跟踪 openwrt-25.12 官方最新维护分支以获取最新包修复
sed -i -E 's/\^[0-9a-fA-F]+/;openwrt-25.12/g' feeds.conf.default

# 2. 准备 package/custom-apps 目录
mkdir -p package/custom-apps

# 3. 克隆外部独立维护的自定义插件仓库
echo "--> 正在同步外部自定义插件仓库..."
[ ! -d "package/custom-apps/luci-app-lucky" ] && git clone --depth=1 https://github.com/gdy666/luci-app-lucky.git package/custom-apps/luci-app-lucky || true
[ ! -d "package/custom-apps/openwrt-daede" ] && git clone --depth=1 https://github.com/kenzok8/openwrt-daede.git package/custom-apps/openwrt-daede || true
[ ! -d "package/custom-apps/rtp2httpd" ] && git clone --depth=1 https://github.com/stackia/rtp2httpd.git package/custom-apps/rtp2httpd || true
[ ! -d "package/custom-apps/openwrt-honk" ] && git clone --depth=1 https://github.com/kenzok8/openwrt-honk.git package/custom-apps/openwrt-honk || true

# 4. 注册 custom 本地 Feed
sed -i -E '/^[[:space:]]*src-link[[:space:]]+custom[[:space:]]+/d' feeds.conf.default
printf '\nsrc-link custom %s/package/custom-apps\n' "$PWD" >> feeds.conf.default

echo "--> DIY Part 1 执行完成！feeds.conf.default 配置如下："
cat feeds.conf.default
