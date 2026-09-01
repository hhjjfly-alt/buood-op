#!/bin/bash
# diyyb1-part2.sh
# 最终生产精简版（已修复语法错误 + smartdns 哈希 + 强制禁用 Docker + sing-box 固定稳定版）
# 适配最新 OpenWrt + N6000/PVE + I226
# ===== 完整 Daed Web 界面版（已修复 daed / daed-geoip / daed-geosite 依赖问题）=====
set -e
export GIT_TERMINAL_PROMPT=0
clone_or_pull() {
    local repo=$1 dir=$2 branch=${3:-}
    if [[ -d "$dir/.git" ]]; then
        git -C "$dir" fetch --depth 1 || true
        if [ -n "$branch" ]; then
            git -C "$dir" reset --hard "origin/$branch" || git -C "$dir" reset --hard "origin/HEAD"
        else
            git -C "$dir" reset --hard origin/HEAD || true
        fi
    else
        if [ -n "$branch" ]; then
            git clone --depth 1 -b "$branch" "$repo" "$dir"
        else
            git clone --depth 1 "$repo" "$dir"
        fi
    fi
}
get_latest_tag() {
    local repo="$1"
    local tag
    tag=$(curl -sL --connect-timeout 12 --max-time 25 \
        "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
        | grep -oE '"tag_name":[[:space:]]*"[^"]+"' | head -1 \
        | sed -E 's/.*"([^"]+)".*/\1/')
    echo "$tag"
}
echo "=== 开始执行 diyyb1-part2.sh（完整 Daed Web 界面版） ==="
##############################################################################
# 1. 清理官方冲突包
##############################################################################
rm -rf feeds/packages/net/{chinadns-ng,dns2socks,geoview,hysteria,ipt2socks,microsocks,naiveproxy,shadow-tls,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,sing-box,tcping,trojan-plus,tuic-client,v2ray-core,v2ray-geodata,v2ray-plugin,xray-core,xray-plugin}
rm -rf feeds/luci/applications/luci-app-passwall
##############################################################################
# 2. 拉取必要第三方源（无 Docker）
##############################################################################
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git package/passwall-packages
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall.git package/passwall-luci
rm -rf package/passwall-packages/shadowsocksr-libev 2>/dev/null || true

# 清理 passwall2
rm -rf package/passwall2

clone_or_pull https://github.com/gdy666/luci-app-lucky.git package/lucky

# dae（保留轻度 luci-app-dae）
rm -rf package/dae package/luci-app-dae
git clone --depth=1 https://github.com/immortalwrt/packages package/immortalwrt-packages
[ -d package/immortalwrt-packages/net/dae ] && mv package/immortalwrt-packages/net/dae package/dae
rm -rf package/immortalwrt-packages
git clone --depth=1 https://github.com/immortalwrt/luci package/immortalwrt-luci
[ -d package/immortalwrt-luci/applications/luci-app-dae ] && {
    mv package/immortalwrt-luci/applications/luci-app-dae package/luci-app-dae
    rm -rf package/luci-app-dae/dae 2>/dev/null || true
}
rm -rf package/immortalwrt-luci

# ===== 完整 Daed Web 界面 =====
rm -rf package/luci-app-daed package/daed
clone_or_pull https://github.com/QiuSimons/luci-app-daed package/luci-app-daed
# 备用拉取
if [ ! -d package/luci-app-daed ] || [ ! -f package/luci-app-daed/Makefile ]; then
    echo "主仓库拉取失败，尝试备用源..."
    rm -rf package/luci-app-daed
    git clone --depth=1 https://github.com/immortalwrt/luci package/immortalwrt-luci-tmp
    if [ -d package/immortalwrt-luci-tmp/applications/luci-app-daed ]; then
        mv package/immortalwrt-luci-tmp/applications/luci-app-daed package/luci-app-daed
    fi
    rm -rf package/immortalwrt-luci-tmp
fi
find package/luci-app-daed -type d -name "web" -exec rm -rf {} + 2>/dev/null || true
# ===== 结束 =====

clone_or_pull https://github.com/sbwml/v2ray-geodata package/v2ray-geodata
clone_or_pull https://github.com/sirpdboy/luci-app-ddns-go package/ddns-go
clone_or_pull https://github.com/lisaac/luci-app-diskman.git package/luci-app-diskman
rm -rf feeds/packages/net/smartdns
clone_or_pull https://github.com/pymumu/openwrt-smartdns.git package/smartdns master
rm -rf package/luci-app-smartdns
clone_or_pull https://github.com/pymumu/luci-app-smartdns.git package/luci-app-smartdns master
##############################################################################
# 3. 路径与哈希修复
##############################################################################
if [ -f package/dae/Makefile ]; then
    sed -i 's|../../lang/golang/golang-package.mk|$(TOPDIR)/feeds/packages/lang/golang/golang-package.mk|g' package/dae/Makefile
    sed -i 's/PKG_HASH:=.*/PKG_HASH:=skip/g' package/dae/Makefile
    sed -i 's/^PKG_MIRROR_HASH:=.*/PKG_MIRROR_HASH:=skip/g' package/dae/Makefile
fi
[ -f package/luci-app-dae/Makefile ] && sed -i 's|../../luci.mk|$(TOPDIR)/feeds/luci/luci.mk|g' package/luci-app-dae/Makefile

# ===== 修改处：完整 Daed 路径/哈希修复 + 强化主包处理 =====
if [ -f package/luci-app-daed/Makefile ]; then
    sed -i 's|../../luci.mk|$(TOPDIR)/feeds/luci/luci.mk|g' package/luci-app-daed/Makefile
    sed -i 's/PKG_HASH:=.*/PKG_HASH:=skip/g' package/luci-app-daed/Makefile 2>/dev/null || true
    sed -i 's/^PKG_MIRROR_HASH:=.*/PKG_MIRROR_HASH:=skip/g' package/luci-app-daed/Makefile 2>/dev/null || true
fi

if [ -d package/luci-app-daed/daed ]; then
    find package/luci-app-daed/daed -name "Makefile" -exec sed -i \
        -e 's/PKG_HASH:=.*/PKG_HASH:=skip/g' \
        -e 's/^PKG_MIRROR_HASH:=.*/PKG_MIRROR_HASH:=skip/g' \
        -e 's|../../lang/golang/golang-package.mk|$(TOPDIR)/feeds/packages/lang/golang/golang-package.mk|g' \
        {} + 2>/dev/null || true

    # 补充 node/host 依赖（解决前端 embed 问题）
    for mk in package/luci-app-daed/daed/Makefile package/luci-app-daed/Makefile; do
        [ -f "$mk" ] || continue
        if ! grep -q 'node/host' "$mk" 2>/dev/null; then
            sed -i '/PKG_BUILD_DEPENDS/s/$/ +node\/host/' "$mk" 2>/dev/null || \
            sed -i '/include $(INCLUDE_DIR)\/package.mk/a PKG_BUILD_DEPENDS:=node/host' "$mk" 2>/dev/null || true
        fi
    done
fi
# ===== 修改处结束 =====

if [ -f package/smartdns/Makefile ]; then
    sed -i 's|../../lang/rust/rust-package.mk|$(TOPDIR)/feeds/packages/lang/rust/rust-package.mk|g' package/smartdns/Makefile
    if ! grep -q 'DEPENDS.*zlib' package/smartdns/Makefile; then
        sed -i 's/^DEPENDS:=/DEPENDS:=+zlib /' package/smartdns/Makefile
    fi
fi
##############################################################################
# 4. Feeds 更新 + APK 版本净化
##############################################################################
rm -rf tmp/
./scripts/feeds update -i
THIRD_PARTY_DIRS="package/passwall-packages package/passwall-luci package/lucky package/dae package/luci-app-dae package/luci-app-daed package/v2ray-geodata package/ddns-go package/luci-app-diskman package/smartdns package/luci-app-smartdns feeds/istore_packages"
for dir in $THIRD_PARTY_DIRS; do
    [ -d "$dir" ] || continue
    find "$dir" -type f -name "Makefile" -exec sed -i -E \
        -e 's/\([<=>]+[^)]+\)//g' \
        -e 's/^([[:space:]]*PKG_VERSION[[:space:]]*:?=[[:space:]]*)[vV]([0-9])/\1\2/g' \
        -e 's/^([[:space:]]*PKG_VERSION[[:space:]]*:?=[[:space:]]*[0-9]+(\.[0-9]+)*)[^0-9.].*/\1/g' \
        -e 's/^([[:space:]]*PKG_RELEASE[[:space:]]*:?=[[:space:]]*[0-9]+).*/\1/g' \
        -e 's/^([[:space:]]*PKG_RELEASE[[:space:]]*:?=)[[:space:]]*$/\11/g' \
        {} + || true
done
# luci-app-zerotier 强制兼容 apk
ZT_MK="feeds/istore_packages/luci-app-zerotier/Makefile"
if [ -f "$ZT_MK" ]; then
    sed -i 's/^PKG_VERSION:=.*/PKG_VERSION:=1.3.0/' "$ZT_MK"
    sed -i 's/^PKG_RELEASE:=.*/PKG_RELEASE:=1/' "$ZT_MK"
    grep -q '^PKG_RELEASE:=' "$ZT_MK" || sed -i '/^PKG_VERSION:=/a PKG_RELEASE:=1' "$ZT_MK"
fi
./scripts/feeds install -a
./scripts/feeds install -p istore_packages luci-app-zerotier 2>/dev/null || true
##############################################################################
# 5. 注入版本 + 强力跳过哈希
##############################################################################
SING_BOX_LATEST="1.12.12"
if [ -f package/passwall-packages/sing-box/Makefile ]; then
    echo "更新 sing-box 到 $SING_BOX_LATEST（固定稳定版，避免编译失败）"
    sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$SING_BOX_LATEST/" package/passwall-packages/sing-box/Makefile
    sed -i '/PKG_HASH/d;/PKG_MIRROR_HASH/d' package/passwall-packages/sing-box/Makefile
    sed -i "/^PKG_VERSION:=/a PKG_HASH:=skip\nPKG_MIRROR_HASH:=skip" package/passwall-packages/sing-box/Makefile
fi
DDNS_GO_LATEST=$(get_latest_tag "jeessy2/ddns-go")
DDNS_GO_LATEST=${DDNS_GO_LATEST#v}
if [ -n "$DDNS_GO_LATEST" ] && [ -f package/ddns-go/ddns-go/Makefile ]; then
    sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$DDNS_GO_LATEST/" package/ddns-go/ddns-go/Makefile
    sed -i "s/^PKG_HASH:=.*/PKG_HASH:=skip/" package/ddns-go/ddns-go/Makefile
fi
SMARTDNS_TAG=$(get_latest_tag "pymumu/smartdns")
SMARTDNS_LATEST=$(echo "$SMARTDNS_TAG" | sed 's/^Release//')
[ -z "$SMARTDNS_LATEST" ] && SMARTDNS_LATEST="48.4" && SMARTDNS_TAG="Release48.4"
if [ -f package/smartdns/Makefile ]; then
    echo "更新 smartdns 到 $SMARTDNS_LATEST ($SMARTDNS_TAG) 并强制跳过哈希"
    sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$SMARTDNS_LATEST/" package/smartdns/Makefile
    sed -i "s/^PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=$SMARTDNS_TAG/" package/smartdns/Makefile
    sed -i '/PKG_HASH/d' package/smartdns/Makefile
    sed -i '/PKG_MIRROR_HASH/d' package/smartdns/Makefile
    sed -i "/^PKG_SOURCE_VERSION:=/a PKG_HASH:=skip\nPKG_MIRROR_HASH:=skip" package/smartdns/Makefile
fi
for dir in package/passwall-packages package/ddns-go package/smartdns; do
    [ -d "$dir" ] || continue
    find "$dir" -type f -name "Makefile" -exec sed -i -E \
        -e 's/^([[:space:]]*PKG_VERSION[[:space:]]*:?=[[:space:]]*[0-9]+(\.[0-9]+)*)[^0-9.].*/\1/g' \
        {} + || true
done
##############################################################################
# 6. 系统基础修改
##############################################################################
sed -i 's/192.168.1.1/10.0.0.10/g' package/base-files/files/bin/config_generate
mkdir -p package/base-files/files/etc
echo 'net.netfilter.nf_conntrack_max=262144' >> package/base-files/files/etc/sysctl.conf
echo 'net.core.default_qdisc=fq' >> package/base-files/files/etc/sysctl.conf
echo 'net.ipv4.tcp_congestion_control=bbr' >> package/base-files/files/etc/sysctl.conf
echo 'export PS1="\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "' >> package/base-files/files/etc/profile
sed -i "s/IMG_PREFIX:=.*/IMG_PREFIX:=OpenWrt-PVE-N6000-$(date +%Y%m%d)/g' include/image.mk
mkdir -p package/base-files/files/etc/uci-defaults
cat > package/base-files/files/etc/uci-defaults/99-custom-language << 'EOF'
#!/bin/sh
uci set luci.main.lang='zh_cn'
uci commit luci
rm -f /etc/uci-defaults/99-custom-language
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-custom-language
##############################################################################
# 7. 精简 .config（最终生产版 + 强制禁用 Docker）
##############################################################################
touch .config
sed -i '/luci-app-transmission/d;/transmission-daemon/d' .config
sed -i '/luci-app-store/d;/luci-i18n-store/d' .config
sed -i '/qemu-ga/d;/dockerd/d;/docker/d;/dockerman/d;/mihomo/d' .config
echo "# CONFIG_PACKAGE_dockerd is not set" >> .config
echo "# CONFIG_PACKAGE_docker is not set" >> .config
echo "# CONFIG_PACKAGE_luci-app-dockerman is not set" >> .config
echo "# CONFIG_PACKAGE_containerd is not set" >> .config
echo "# CONFIG_PACKAGE_runc is not set" >> .config
echo "# CONFIG_PACKAGE_tini is not set" >> .config
echo "# CONFIG_PACKAGE_libnetwork is not set" >> .config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> .config
echo "CONFIG_LUCI_LANG_zh_cn=y" >> .config
COMPILE_DATE_SHORT="$(date +%y.%m.%d)"
echo "CONFIG_IMAGEOPT=y" >> .config
echo "CONFIG_VERSIONOPT=y" >> .config
echo "CONFIG_VERSION_NUMBER=\"R${COMPILE_DATE_SHORT}\"" >> .config
echo "CONFIG_VERSION_CODE=\"\"" >> .config
echo "CONFIG_TARGET_x86=y" >> .config
echo "CONFIG_TARGET_x86_64=y" >> .config
echo "CONFIG_TARGET_x86_64_DEVICE_generic=y" >> .config
echo "CONFIG_TARGET_ROOTFS_EXT4FS=y" >> .config
echo "CONFIG_TARGET_ROOTFS_SQUASHFS=y" >> .config
echo "CONFIG_PACKAGE_kmod-igc=y" >> .config
echo "CONFIG_PACKAGE_kmod-igb=y" >> .config
echo "CONFIG_PACKAGE_kmod-e1000e=y" >> .config
echo "CONFIG_PACKAGE_kmod-r8169=y" >> .config
echo "CONFIG_PACKAGE_kmod-usb-storage=y" >> .config
echo "CONFIG_PACKAGE_kmod-usb-storage-uas=y" >> .config
echo "CONFIG_PACKAGE_kmod-fs-ext4=y" >> .config
echo "CONFIG_PACKAGE_kmod-fs-ntfs3=y" >> .config
echo "CONFIG_PACKAGE_kmod-vfat=y" >> .config
echo "CONFIG_PACKAGE_kmod-nls-utf8=y" >> .config
echo "CONFIG_PACKAGE_kmod-tun=y" >> .config
echo "CONFIG_PACKAGE_kmod-nft-tproxy=y" >> .config
echo "CONFIG_PACKAGE_kmod-nft-socket=y" >> .config
echo "CONFIG_PACKAGE_kmod-nft-bridge=y" >> .config
echo "CONFIG_PACKAGE_kmod-virtio-net=y" >> .config
echo "CONFIG_PACKAGE_kmod-virtio-blk=y" >> .config
echo "CONFIG_PACKAGE_kmod-virtio-scsi=y" >> .config
echo "CONFIG_PACKAGE_kmod-crypto-hw-aesni=y" >> .config
echo "CONFIG_PACKAGE_kmod-crypto-xts=y" >> .config
echo "CONFIG_PACKAGE_kmod-crypto-gcm=y" >> .config
echo "CONFIG_PACKAGE_kmod-crypto-sha256=y" >> .config
echo "CONFIG_PACKAGE_kmod-crypto-sha512=y" >> .config
echo "CONFIG_PACKAGE_block-mount=y" >> .config
echo "CONFIG_PACKAGE_e2fsprogs=y" >> .config
echo "CONFIG_PACKAGE_blkid=y" >> .config
echo "CONFIG_PACKAGE_ntfs-3g=y" >> .config
echo "CONFIG_PACKAGE_fdisk=y" >> .config
echo "CONFIG_PACKAGE_parted=y" >> .config
echo "CONFIG_PACKAGE_lsblk=y" >> .config
echo "CONFIG_PACKAGE_smartmontools=y" >> .config
echo "CONFIG_PACKAGE_dnsmasq-full=y" >> .config
echo "CONFIG_PACKAGE_firewall4=y" >> .config
echo "CONFIG_PACKAGE_nftables-json=y" >> .config
echo "CONFIG_PACKAGE_ip-full=y" >> .config
echo "CONFIG_PACKAGE_tc=y" >> .config
echo "CONFIG_PACKAGE_resolveip=y" >> .config
echo "CONFIG_PACKAGE_ca-bundle=y" >> .config
echo "CONFIG_PACKAGE_ca-certificates=y" >> .config
echo "CONFIG_PACKAGE_luci-app-firewall=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-firewall-zh-cn=y" >> .config
echo "CONFIG_PACKAGE_luci-app-passwall=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-passwall-zh-cn=y" >> .config
echo "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Hysteria=y" >> .config
echo "CONFIG_PACKAGE_hysteria=y" >> .config
echo "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_SingBox=y" >> .config
echo "CONFIG_PACKAGE_sing-box=y" >> .config
echo "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Xray=y" >> .config
echo "CONFIG_PACKAGE_xray-core=y" >> .config
echo "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Trojan_Go=y" >> .config
echo "CONFIG_PACKAGE_trojan-go=y" >> .config
echo "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Trojan_Plus=y" >> .config
echo "CONFIG_PACKAGE_trojan-plus=y" >> .config
echo "CONFIG_PACKAGE_chinadns-ng=y" >> .config
echo "CONFIG_PACKAGE_dns2socks=y" >> .config
echo "CONFIG_PACKAGE_microsocks=y" >> .config
echo "CONFIG_PACKAGE_ipt2socks=y" >> .config
echo "CONFIG_PACKAGE_v2ray-geodata=y" >> .config
echo "CONFIG_PACKAGE_geoview=y" >> .config
echo "CONFIG_PACKAGE_tcping=y" >> .config
echo "# CONFIG_PACKAGE_luci-app-passwall2 is not set" >> .config
echo "# CONFIG_PACKAGE_luci-i18n-passwall2-zh-cn is not set" >> .config

# ---------- dae + 完整 Daed Web 界面 ----------
echo "CONFIG_PACKAGE_dae=y" >> .config
echo "CONFIG_PACKAGE_luci-app-dae=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-dae-zh-cn=y" >> .config

# ===== 修改处：完整启用 Daed 及其全部依赖 =====
echo "CONFIG_PACKAGE_luci-app-daed=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-daed-zh-cn=y" >> .config
echo "CONFIG_PACKAGE_daed=y" >> .config
echo "CONFIG_PACKAGE_daed-geoip=y" >> .config
echo "CONFIG_PACKAGE_daed-geosite=y" >> .config
# ===== 修改处结束 =====

echo "CONFIG_PACKAGE_luci-app-smartdns=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-smartdns-zh-cn=y" >> .config
echo "CONFIG_PACKAGE_smartdns=y" >> .config
echo "CONFIG_PACKAGE_luci-app-ddns-go=y" >> .config
echo "CONFIG_PACKAGE_luci-app-diskman=y" >> .config
echo "CONFIG_PACKAGE_luci-app-lucky=y" >> .config
echo "CONFIG_PACKAGE_luci-app-zerotier=y" >> .config
echo "CONFIG_PACKAGE_zerotier=y" >> .config
echo "CONFIG_PACKAGE_luci-app-ksmbd=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-ksmbd-zh-cn=y" >> .config
echo "CONFIG_PACKAGE_ksmbd-server=y" >> .config
echo "CONFIG_PACKAGE_wsdd2=y" >> .config
echo "CONFIG_PACKAGE_autosamba=y" >> .config
echo "CONFIG_PACKAGE_luci-app-ttyd=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-ttyd-zh-cn=y" >> .config
echo "CONFIG_PACKAGE_ttyd=y" >> .config
echo "CONFIG_PACKAGE_kmod-tcp-bbr=y" >> .config
echo "# CONFIG_PACKAGE_tailscale is not set" >> .config
echo "# CONFIG_PACKAGE_luci-app-tailscale is not set" >> .config
echo "# CONFIG_PACKAGE_luci-i18n-tailscale-zh-cn is not set" >> .config
echo "# CONFIG_PACKAGE_luci-app-samba4 is not set" >> .config
echo "# CONFIG_PACKAGE_luci-app-upnp is not set" >> .config
echo "# CONFIG_PACKAGE_luci-app-ddns is not set" >> .config
echo "# CONFIG_PACKAGE_luci-app-wol is not set" >> .config
echo "# CONFIG_PACKAGE_luci-app-nlbwmon is not set" >> .config
echo "# CONFIG_PACKAGE_luci-app-statistics is not set" >> .config
echo "# CONFIG_PACKAGE_luci-app-wireguard is not set" >> .config
echo "# CONFIG_PACKAGE_luci-app-openvpn is not set" >> .config
echo "# CONFIG_PACKAGE_luci-app-qos is not set" >> .config
echo "# CONFIG_PACKAGE_luci-theme-material is not set" >> .config
echo "# CONFIG_PACKAGE_luci-theme-openwrt is not set" >> .config
echo "# CONFIG_PACKAGE_kmod-usb-audio is not set" >> .config
echo "# CONFIG_PACKAGE_kmod-sound-core is not set" >> .config
echo "# CONFIG_PACKAGE_kmod-bluetooth is not set" >> .config
echo "# CONFIG_PACKAGE_kmod-ath is not set" >> .config
echo "# CONFIG_PACKAGE_kmod-mac80211 is not set" >> .config
echo "# CONFIG_PACKAGE_wpad-basic is not set" >> .config
echo "# CONFIG_PACKAGE_wpad-openssl is not set" >> .config
echo "# CONFIG_PACKAGE_hostapd is not set" >> .config
echo "# CONFIG_PACKAGE_ppp is not set" >> .config
echo "# CONFIG_PACKAGE_ppp-mod-pppoe is not set" >> .config
##############################################################################
# 8. 自动挂载与服务
##############################################################################
cat > package/base-files/files/etc/uci-defaults/99-auto-mount << 'EOF'
#!/bin/sh
uci -q delete fstab.sda3
uci set fstab.sda3="mount"
uci set fstab.sda3.device="/dev/sda3"
uci set fstab.sda3.target="/mnt/sda3"
uci set fstab.sda3.fstype="ext4"
uci set fstab.sda3.options="rw,relatime"
uci set fstab.sda3.enabled="1"
uci commit fstab
/etc/init.d/fstab enable
block mount
rm -f /etc/uci-defaults/99-auto-mount
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-auto-mount
cat > package/base-files/files/etc/uci-defaults/99-enable-services << 'EOF'
#!/bin/sh
uci -q set smartdns.@smartdns[0].enabled='1'
uci commit smartdns
/etc/init.d/smartdns enable || true
uci -q set passwall.@global[0].enabled='0'
uci commit passwall
/etc/init.d/passwall disable || true
rm -f /etc/uci-defaults/99-enable-services
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-enable-services
##############################################################################
# 9. 内核 BPF/BTF（dae 必需，防重复追加）
##############################################################################
for conf in target/linux/generic/config-* target/linux/x86/config-*; do
    [ -f "$conf" ] || continue
    grep -q "CONFIG_DEBUG_INFO_BTF=y" "$conf" 2>/dev/null && continue
    {
        echo "CONFIG_BPF=y"
        echo "CONFIG_BPF_SYSCALL=y"
        echo "CONFIG_BPF_JIT=y"
        echo "CONFIG_HAVE_EBPF_JIT=y"
        echo "CONFIG_BPF_EVENTS=y"
        echo "CONFIG_CGROUP_BPF=y"
        echo "CONFIG_DEBUG_INFO=y"
        echo "CONFIG_DEBUG_INFO_BTF=y"
        echo "# CONFIG_DEBUG_INFO_REDUCED is not set"
        echo "CONFIG_XDP_SOCKETS=y"
        echo "CONFIG_NET_SCH_BPF=y"
        echo "CONFIG_NET_ACT_BPF=y"
        echo "CONFIG_NET_CLS_BPF=y"
    } >> "$conf"
done
echo "=== diyyb1-part2.sh 执行完成（完整 Daed Web 界面版） ==="
echo "推荐后续命令："
echo "  make defconfig"
echo "  make download -j\$(nproc)"
echo "  make -j\$(nproc) V=s"
