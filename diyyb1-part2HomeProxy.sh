#!/bin/bash
# diyyb1-part2.sh (Master 终极防弹版 - 偏执狂级除雷)

set -e
export GIT_TERMINAL_PROMPT=0

clone_or_pull() {
    local repo=$1 dir=$2 branch=${3:-}
    if [[ -d "$dir/.git" ]]; then
        echo "Update $dir ..."
        git -C "$dir" fetch --depth 1
        if [ -n "$branch" ]; then
            git -C "$dir" reset --hard origin/$branch
        else
            git -C "$dir" reset --hard origin/HEAD
        fi
    else
        echo "Clone $repo -> $dir ..."
        if [ -n "$branch" ]; then
            git clone --depth 1 -b $branch "$repo" "$dir"
        else
            git clone --depth 1 "$repo" "$dir"
        fi
    fi
}

echo "=== 开始执行 diyyb1-part2.sh ==="

# 1. 清理官方冲突依赖包
echo "清理默认冲突依赖..."
rm -rf feeds/packages/net/{chinadns-ng,dns2socks,geoview,hysteria,ipt2socks,microsocks,naiveproxy,shadow-tls,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,sing-box,tcping,trojan-plus,tuic-client,v2ray-core,v2ray-geodata,v2ray-plugin,xray-core,xray-plugin}
rm -rf feeds/luci/applications/luci-app-passwall

# =================================================================
# 2. 批量拉取所有第三方源码 (全名单无遗漏)
# =================================================================
echo "拉取第三方插件..."

# PassWall
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git package/pw-packages
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall.git package/pw-luci
cp -rf package/pw-packages/* package/pw-luci/
rm -rf package/pw-packages package/pw-luci/shadowsocksr-libev

# Lucky & Dockerman
clone_or_pull https://github.com/gdy666/luci-app-lucky.git package/lucky
clone_or_pull https://github.com/lisaac/luci-app-dockerman.git package/luci-app-dockerman

# DAE
rm -rf package/dae package/luci-app-dae
git clone --depth=1 https://github.com/immortalwrt/packages package/immortalwrt-packages
mv package/immortalwrt-packages/net/dae package/dae
rm -rf package/immortalwrt-packages
# 修复 dae 的 golang 依赖路径
sed -i 's|../../lang/golang/golang-package.mk|$(TOPDIR)/feeds/packages/lang/golang/golang-package.mk|g' package/dae/Makefile

git clone --depth=1 https://github.com/immortalwrt/luci package/immortalwrt-luci
mv package/immortalwrt-luci/applications/luci-app-dae package/luci-app-dae
rm -rf package/immortalwrt-luci package/luci-app-dae/dae

# 【核心修复】：修复 luci-app-dae 的 luci.mk 相对路径依赖（菜单消失的唯一元凶！）
sed -i 's|../../luci.mk|$(TOPDIR)/feeds/luci/luci.mk|g' package/luci-app-dae/Makefile

# DDNS-GO, Fakehttp & Geodata
clone_or_pull https://github.com/sbwml/v2ray-geodata package/v2ray-geodata
clone_or_pull https://github.com/sirpdboy/luci-app-ddns-go package/ddns-go
clone_or_pull https://github.com/yingziwu/openwrt-fakehttp package/openwrt-fakehttp
clone_or_pull https://github.com/yingziwu/luci-app-fakehttp package/luci-app-fakehttp

# AdGuardHome 和 Diskman
# clone_or_pull https://github.com/rufengsuixing/luci-app-adguardhome.git package/luci-app-adguardhome
# clone_or_pull https://github.com/lisaac/luci-app-diskman.git package/luci-app-diskman

# === 【修改标注：恢复 SmartDNS 源码拉取】 ===
echo "处理 smartdns 和 luci-app-smartdns..."
sed -i 's/1.2024.45/1.2025.47/g; s/9ee27e7ba2d9789b7e007410e76c06a957f85e98/0f1912ab020ea9a60efac4732442f0bb7093f40b/g; /^PKG_MIRROR_HASH/s/^/#/' feeds/packages/net/smartdns/Makefile
rm -rf package/luci-app-smartdns
clone_or_pull https://github.com/pymumu/luci-app-smartdns.git package/luci-app-smartdns master
# ==========================================

# 拉取 Tailscale 的 LuCI 图形界面
clone_or_pull https://github.com/asvow/luci-app-tailscale.git package/luci-app-tailscale

# === 暴力排雷：解决 tailscale 与 luci-app-tailscale 的核心文件冲突 ===
rm -rf package/luci-app-tailscale/root/etc/init.d/tailscale
rm -rf package/luci-app-tailscale/root/etc/config/tailscale
# ====================================================================

# 3. 终极 apk 净化 (严格修复正则执行顺序)
# =================================================================
echo "正在对所有第三方包进行强力净化..."

# === 【修改标注：去除了 feeds/momo，并恢复了 package/luci-app-smartdns】 ===
THIRD_PARTY_DIRS="feeds/istore feeds/istore_packages package/pw-luci package/lucky package/luci-app-dockerman package/dae package/luci-app-dae package/v2ray-geodata package/ddns-go package/openwrt-fakehttp package/luci-app-fakehttp package/luci-app-diskman package/luci-app-smartdns"
# ===========================================================================

for dir in $THIRD_PARTY_DIRS; do
    if [ -d "$dir" ]; then
        # 步骤 A：彻底清除带符号的依赖限制
        find "$dir" -type f -name "Makefile" -exec sed -i -E 's/\([<=>]+[^)]+\)//g' {} + || true
        # 步骤 B：先去掉版本号最前面的字母 v 或 V
        find "$dir" -type f -name "Makefile" -exec sed -i -E 's/^([[:space:]]*PKG_VERSION[[:space:]]*:?=[[:space:]]*)[vV]([0-9])/\1\2/g' {} + || true
        # 步骤 C：一刀切截断法，保留纯数字和点
        find "$dir" -type f -name "Makefile" -exec sed -i -E 's/^([[:space:]]*PKG_VERSION[[:space:]]*:?=[[:space:]]*[0-9\.]+).*/\1/g' {} + || true
        # 步骤 D：PKG_RELEASE 严格截断为纯数字
        find "$dir" -type f -name "Makefile" -exec sed -i -E 's/^([[:space:]]*PKG_RELEASE[[:space:]]*:?=[[:space:]]*[0-9]+).*/\1/g' {} + || true
    fi
done

echo "净化完成，清空编译系统缓存并重建索引..."
rm -rf tmp/
./scripts/feeds update -i
./scripts/feeds install -a

# 双保险：强行挂载 ZeroTier 确保菜单被解析
./scripts/feeds install -p istore_packages luci-app-zerotier

# =================================================================
# 4. 动态最新版注入与系统核心剥离
# =================================================================
SING_BOX_LATEST=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | awk -F '"' '/tag_name/{print $4}' | sed 's/^v//')
if [ -n "$SING_BOX_LATEST" ] && [ -f "package/pw-luci/sing-box/Makefile" ]; then
    sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$SING_BOX_LATEST/" package/pw-luci/sing-box/Makefile
    sed -i "s/^PKG_HASH:=.*/PKG_HASH:=skip/" package/pw-luci/sing-box/Makefile
fi

DDNS_GO_LATEST=$(curl -s "https://api.github.com/repos/jeessy2/ddns-go/releases/latest" | awk -F '"' '/tag_name/{print $4}' | sed 's/^v//')
if [ -n "$DDNS_GO_LATEST" ] && [ -f "package/ddns-go/ddns-go/Makefile" ]; then
    sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$DDNS_GO_LATEST/" package/ddns-go/ddns-go/Makefile
    sed -i "s/^PKG_HASH:=.*/PKG_HASH:=skip/" package/ddns-go/ddns-go/Makefile
fi

sed -i 's/192.168.1.1/10.0.0.10/g' package/base-files/files/bin/config_generate
mkdir -p package/base-files/files/etc
echo 'net.netfilter.nf_conntrack_max=165535' >> package/base-files/files/etc/sysctl.conf
echo 'export PS1="\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]$ "' >> package/base-files/files/etc/profile
sed -i "s/IMG_PREFIX:=.*/IMG_PREFIX:=OpenWrt-PVE-N6000-$(date +%Y%m%d)/g" include/image.mk

echo "执行底层剥离与配置注入..."
touch .config # 核心护城河：强行生成配置底文件，防止后续 sed 报错

sed -i '/luci-app-transmission/d' .config
sed -i '/luci-i18n-transmission/d' .config
sed -i '/transmission-daemon/d' .config

# 必须删除，否则 opkg 依赖缺失会导致全局崩溃
sed -i '/luci-app-store/d' .config
sed -i '/luci-i18n-store/d' .config

echo "CONFIG_LUCI_LANG_zh_Hans=y" >> .config
echo "CONFIG_LUCI_LANG_zh_cn=y" >> .config

# =================================================================
# 5. 固件版本号与真实编译日期注入 (官方正统通道 - 极简单日期版)
# =================================================================
echo "注入专属编译日期与版本号..."

COMPILE_DATE_SHORT="$(date +"%y.%m.%d")"

# 1. 开启 OpenWrt 官方底层版本自定义总开关
touch .config
sed -i '/CONFIG_IMAGEOPT/d' .config
sed -i '/CONFIG_VERSIONOPT/d' .config
sed -i '/CONFIG_VERSION_NUMBER/d' .config
sed -i '/CONFIG_VERSION_CODE/d' .config

echo "CONFIG_IMAGEOPT=y" >> .config
echo "CONFIG_VERSIONOPT=y" >> .config
# 保留短日期 (例如：R26.03.16)
echo "CONFIG_VERSION_NUMBER=\"R${COMPILE_DATE_SHORT}\"" >> .config
# 核心改动：强制将长日期置空，避免双日期重叠，且防止系统回退显示 git hash
echo "CONFIG_VERSION_CODE=\"\"" >> .config

# 2. 保留首次开机强制中文配置
mkdir -p package/base-files/files/etc/uci-defaults
cat > package/base-files/files/etc/uci-defaults/99-custom-language <<EOF
#!/bin/sh
uci set luci.main.lang='zh_cn'
uci commit luci

rm -f /etc/uci-defaults/99-custom-language
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-custom-language
# =================================================================
# 6. 强制编译磁盘挂载核心组件 (自动修复 Docker 数据盘不挂载)
# =================================================================
echo "注入磁盘挂载与 ext4 驱动组件..."

# 保证配置落盘
touch .config
sed -i '/CONFIG_PACKAGE_block-mount/d' .config
echo "CONFIG_PACKAGE_block-mount=y" >> .config

sed -i '/CONFIG_PACKAGE_kmod-fs-ext4/d' .config
echo "CONFIG_PACKAGE_kmod-fs-ext4=y" >> .config

sed -i '/CONFIG_PACKAGE_e2fsprogs/d' .config
echo "CONFIG_PACKAGE_e2fsprogs=y" >> .config

sed -i '/CONFIG_PACKAGE_blkid/d' .config
echo "CONFIG_PACKAGE_blkid=y" >> .config

# 注入首次开机自动配置 sda3 挂载的脚本
cat > package/base-files/files/etc/uci-defaults/99-auto-mount <<'EOF'
#!/bin/sh
# 1. 自动生成 fstab 挂载配置
uci -q delete fstab.sda3
uci set fstab.sda3="mount"
uci set fstab.sda3.device="/dev/sda3"
uci set fstab.sda3.target="/mnt/sda3"
uci set fstab.sda3.fstype="ext4"
uci set fstab.sda3.options="rw,relatime"
uci set fstab.sda3.enabled="1"
uci commit fstab

# 2. 启用自动挂载服务并立即挂载
/etc/init.d/fstab enable
block mount

# 3. 探针保护重启：只在 Docker 存在时才重启，防止初始化卡死
[ -x /etc/init.d/dockerd ] && /etc/init.d/dockerd restart || true

# 清理自身，深藏功与名
rm -f /etc/uci-defaults/99-auto-mount
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-auto-mount

# =================================================================
# 7. PassWall 满血核心唤醒 (强制编译所有底层协议，告别组件缺失)
# =================================================================
echo "正在为 PassWall 注入满血协议核心..."

# 1. 唤醒 Hysteria 核心 (通常包含 Hysteria v1 和 v2)
echo "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Hysteria=y" >> .config
echo "CONFIG_PACKAGE_hysteria=y" >> .config

# 2. 唤醒 Sing-Box 核心 (极其重要：现在很多高级别 Hysteria2 节点和 VLESS Reality 都靠它跑)
echo "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_SingBox=y" >> .config
echo "CONFIG_PACKAGE_sing-box=y" >> .config

# 3. 唤醒 Xray 核心 (PassWall 的绝对灵魂基础)
echo "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Xray=y" >> .config
echo "CONFIG_PACKAGE_xray-core=y" >> .config

# 4. 唤醒 Trojan-Go 和 Trojan-Plus (如果你有这方面老节点需求的话，否则可删)
echo "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Trojan_Go=y" >> .config
echo "CONFIG_PACKAGE_trojan-go=y" >> .config
echo "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Trojan_Plus=y" >> .config
echo "CONFIG_PACKAGE_trojan-plus=y" >> .config

# === 【修改标注：此处已删除了 Momo 相关的配置注入】 ===

# ==================== 新增：HomeProxy 控制面板 ====================
echo "CONFIG_PACKAGE_luci-app-homeproxy=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-homeproxy-zh-cn=y" >> .config
# =================================================================

# ==================== 新增：高效网络共享 (ksmbd) ====================
# 1. 核心包与 LuCI 界面
echo "CONFIG_PACKAGE_ksmbd-server=y" >> .config
echo "CONFIG_PACKAGE_luci-app-ksmbd=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-ksmbd-zh-cn=y" >> .config

# 2. Windows 网络发现支持 (必选，否则 Windows 无法在“网络”里直接看到路由器)
echo "CONFIG_PACKAGE_wsdd2=y" >> .config

# 3. 磁盘辅助工具 (配合你之前的磁盘挂载脚本)
echo "CONFIG_PACKAGE_autosamba=y" >> .config
# =================================================================

# ==================== 新增：Tailscale 异地组网 ====================
# 1. 核心程序与 LuCI 界面（由 istore 源提供支持）
echo "CONFIG_PACKAGE_tailscale=y" >> .config
echo "CONFIG_PACKAGE_luci-app-tailscale=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-tailscale-zh-cn=y" >> .config

# 2. 确保内核支持（Tailscale 运行依赖虚拟网卡驱动）
echo "CONFIG_PACKAGE_kmod-tun=y" >> .config

# ==================== 新增：Web 网页终端 (TTYD) ====================
# 允许在 LuCI 网页后台直接使用 SSH 终端，无需第三方客户端
echo "CONFIG_PACKAGE_ttyd=y" >> .config
echo "CONFIG_PACKAGE_luci-app-ttyd=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-ttyd-zh-cn=y" >> .config

# === 【修改标注：添加初始化脚本，强制禁止 PassWall 和 SmartDNS 自动启动】 ===
mkdir -p package/base-files/files/etc/uci-defaults
cat > package/base-files/files/etc/uci-defaults/99-disable-services <<'EOF'
#!/bin/sh
# 禁止 PassWall 自动启动
uci -q set passwall.main.enabled='0'
uci commit passwall
/etc/init.d/passwall disable || true

# 禁止 SmartDNS 自动启动
uci -q set smartdns.@smartdns[0].enabled='0'
uci commit smartdns
/etc/init.d/smartdns disable || true

rm -f /etc/uci-defaults/99-disable-services
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-disable-services
# ============================================================================

# ==================== 终极暴力修复：直写底层内核配置 ====================
# 应对 OpenWrt master 分支内核升级带来的 eBPF 提问卡死
# 强制向通用内核模板注入 =y 参数，顺从 dae 的依赖需求
for conf in target/linux/generic/config-*; do
    echo "CONFIG_NET_SCH_BPF=y" >> "$conf"
    echo "CONFIG_NET_ACT_BPF=y" >> "$conf"
    echo "CONFIG_NET_CLS_BPF=y" >> "$conf"
done
for conf in target/linux/x86/config-*; do
    echo "CONFIG_NET_SCH_BPF=y" >> "$conf"
    echo "CONFIG_NET_ACT_BPF=y" >> "$conf"
    echo "CONFIG_NET_CLS_BPF=y" >> "$conf"
done
# =================================================================

# =================================================================
echo "=== diyyb1-part2.sh 执行完成，零警告护航模式就绪 ==="
# === 【修改标注：删除了末尾多余的 '}' 符号】 ===
