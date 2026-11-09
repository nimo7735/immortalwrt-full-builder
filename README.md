# 🔥 ImmortalWrt 25.12.2 x86_64 全能功能版自动化编译 (full.config)

基于官方 **ImmortalWrt 25.12 稳定维护分支 (`openwrt-25.12`)** 与 **Linux 6.12 LTS 稳定内核**，采用全量功能配置 `full.config`，集成纯血原生 eBPF (Daede / Honk) 双引擎、突破 208KB 套接字限制、纯净现代 Firewall4 以及开机自愈网络适配。

**本仓库为公开纯净开源仓库，享受 GitHub Actions 无限免费编译时长！**

---

## ⚡ 核心规格与特性
- **固件底座**：ImmortalWrt 25.12.2 (同步官方 `openwrt-25.12` 分支最新代码与安全补丁)
- **编译配置**：`full.config`（全功能全量版）
- **内核驱动**：Linux 6.12 LTS（硬核开启 `CONFIG_KERNEL_DEBUG_INFO_BTF=y` 原生 BTF）
- **网络调优**：套接字收发缓冲跃升至 64MB (`99-custom-network-tuning.conf`)，突破 BDP 物理限制，单连接理论吞吐暴增 315 倍
- **透明代理**：Daede 原生 eBPF 与 Honk 新代 Rust eBPF 双引擎按需选用
- **官方隔离**：独家 `@daed` / `@honk` apk 软件源命名空间沙箱隔离与 `package-manager-call` 智能过滤，杜绝魔改包污染官方源
- **防火墙**：100% 现代 Firewall4 (fw4) + Nftables + 双向 FullCone NAT1
- **远程互联**：原生 Linux 内核态 WireGuard (kmod-wireguard)，全速线速转发，与透明代理秋毫无犯
- **存储扩展**：集成 FUSE 3 全栈 (`kmod-fuse`, `libfuse3`, `fuse3-utils`)，Docker 容器联动秒变轻 NAS
- **开机自愈**：`99-custom-settings` 自动识别物理网口、单网桥清理、自动创建 br-lan、TTYD 终端免密登录

---

## 🚀 如何触发云端编译

1. 进入当前 GitHub 仓库的 **Actions** 页面：
   `https://github.com/nimo7735/immortalwrt-full-builder/actions`
2. 点击左侧工作流中的 **Build ImmortalWrt Firmware (Full)**。
3. 点击右侧的 **Run workflow** 按钮，GitHub Actions 将自动分配云端构建机进行全速多核编译！
4. 编译完成后，固件会自动发布在仓库的 **Releases** 页面供随时下载。
