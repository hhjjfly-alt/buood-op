#!/bin/bash
# diyyb1-part2.sh
# 最终生产全量加固稳定版（PassWall + openwrt-daede + OpenClash + 完整 eBPF/BTF 链）
# 适配最新 OpenWrt + N6000/PVE 虚拟化 + I226 网卡 (适配 Jasper Lake 兼容架构内核)
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
        rm -rf "$dir" 2>/dev/null || true
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

echo "=== 开始执行 diyyb1-part2.sh（适配 N6000 兼容内核版） ==="

##############################################################################
# 1. 清理官方冲突包与历史废弃包
##############################################################################
rm -rf feeds/packages/net/{chinadns-ng,dns2socks,geoview,hysteria,ipt2socks,microsocks,naiveproxy,shadow-tls,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,sing-box,tcping,trojan-plus,tuic-client,v2ray-core,v2ray-geodata,v2ray-plugin,xray-core,xray-plugin,smartdns,dae,daed} 2>/dev/null || true
rm -rf feeds/luci/applications/{luci-app-passwall,luci-app-smartdns,luci-app-dae,luci-app-daed,luci-app-daede,luci-app-openclash} 2>/dev/null || true
rm -rf package/dae package/daed package/luci-app-dae package/luci-app-daed package/luci-app-daede package/openwrt-daede package/luci-app-openclash 2>/dev/null || true

##############################################################################
# 2. 拉取高质量第三方源
##############################################################################
# PassWall 源码
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git package/passwall-packages
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall.git package/passwall-luci
rm -rf package/passwall-packages/shadowsocksr-libev package/passwall2 2>/dev/null || true

# Lucky
clone_or_pull https://github.com/gdy666/luci-app-lucky.git package/lucky

# openwrt-daede 统一套件
clone_or_pull https://github.com/kenzok8/openwrt-daede.git package/openwrt-daede

# OpenClash 源码精准提取
rm -rf package/luci-app-openclash package/openclash-tmp
git clone --depth=1 https://github.com/vernesong/OpenClash.git package/openclash-tmp
if [ -d package/openclash-tmp/luci-app-openclash ]; then
    mv package/openclash-tmp/luci-app-openclash package/luci-app-openclash
fi
rm -rf package/openclash-tmp

# ===== 核心改动：预置专为 N6000 编译的 Compatible 兼容架构内核 =====
mkdir -p package/luci-app-openclash/root/etc/openclash/core
CLASH_META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-amd64-compatible.tar.gz"
echo "正在预置 OpenClash Mihomo 兼容版核心二进制（适配 N6000/无 AVX 平台）..."
if curl -sL --connect-timeout 15 --max-time 90 "$CLASH_META_URL" -o /tmp/clash_meta.tar.gz; then
    if tar -zxf /tmp/clash_meta.tar.gz -C /tmp/ 2>/dev/null && [ -f /tmp/clash ]; then
        mv /tmp/clash package/luci-app-openclash/root/etc/openclash/core/clash_meta
        chmod +x package/luci-app-openclash/root/etc/openclash/core/clash_meta
        echo "OpenClash 兼容版核心预置成功！"
    else
        echo "警告：OpenClash 兼容版核心解压失败，运行时需手动通过网络下载"
    fi
    rm -f /tmp/clash_meta.tar.gz /tmp/clash 2>/dev/null || true
else
    echo "警告：OpenClash 核心下载超时，跳过预置"
fi

# 常用组件源
clone_or_pull https://github.com/sbwml/v2ray-geodata package/v2ray-geodata
clone_or_pull https://github.com/sirpdboy/luci-app-ddns-go package/ddns-go
clone_or_pull https://github.com/lisaac/luci-app-diskman.git package/luci-app-diskman
clone_or_pull https://github.com/pymumu/openwrt-smartdns.git package/smartdns master
clone_or_pull https://github.com/pymumu/luci-app-smartdns.git package/luci-app-smartdns master

##############################################################################
# 3. 依赖、路径与哈希修复
##############################################################################
# SmartDNS 依赖修复
if [ -f package/smartdns/Makefile ]; then
    sed -i 's|../../lang/rust/rust-package.mk|$(TOPDIR)/feeds/packages/lang/rust/rust-package.mk|g' package/smartdns/Makefile 2>/dev/null || true
    if ! grep -q 'DEPENDS.*zlib' package/smartdns/Makefile; then
        sed -i 's/^[[:space:]]*DEPENDS:=/& +zlib /' package/smartdns/Makefile
    fi
fi

# OpenClash 编译与 APK 打包规避修复
if [ -f package/luci-app-openclash/Makefile ]; then
    sed -i 's|../../luci.mk|$(TOPDIR)/feeds/luci/luci.mk|g' package/luci-app-openclash/Makefile 2>/dev/null || true
    sed -i 's/^PKG_RELEASE:=.*/PKG_RELEASE:=1/' package/luci-app-openclash/Makefile
fi

##############################################################################
# 4. Feeds 更新 + APK 包兼容性清洗
##############################################################################
rm -rf tmp/
./scripts/feeds update -i

THIRD_PARTY_DIRS="package/passwall-packages package/passwall-luci package/lucky package/openwrt-daede package/luci-app-openclash package/v2ray-geodata package/ddns-go package/luci-app-diskman package/smartdns package/luci-app-smartdns feeds/istore_packages"
for dir in $THIRD_PARTY_DIRS; do
    [ -d "$dir" ] || continue
    find "$dir" -type f -name "Makefile" -exec sed -i -E \
        -e 's/\([<=>]+[^)]+\)//g' \
        -e 's/^([[:space:]]*PKG_VERSION[[:space:]]*:?=[[:space:]]*)[vV]([0-9])/\1\2/g' \
        -e 's/^([[:space:]]*PKG_VERSION[[:space:]]*:?=[[:space:]]*[0-9]+(\.[0-9]+)*)[^0-9.].*/\1/g' \
        -e 's/^([[:space:]]*PKG_RELEASE[[:space:]]*:?=[[:space:]]*)[a-zA-Z].*/\11/g' \
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
# 5. 动态更新版本 + 跳过哈希
##############################################################################
# Sing-Box 最新稳定版动态抓取（保底 1.14.3）
SING_BOX_LATEST=$(get_latest_tag "SagerNet/sing-box")
SING_BOX_LATEST=${SING_BOX_LATEST#v}
[ -z "$SING_BOX_LATEST" ] && SING_BOX_LATEST="1.14.3"
if [ -f package/passwall-packages/sing-box/Makefile ]; then
    echo "动态设定 sing-box 稳定版为: $SING_BOX_LATEST"
    sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$SING_BOX_LATEST/" package/passwall-packages/sing-box/Makefile
    sed -i '/PKG_HASH/d;/PKG_MIRROR_HASH/d' package/passwall-packages/sing-box/Makefile
    sed -i "/^PKG_VERSION:=/a PKG_HASH:=skip\nPKG_MIRROR_HASH:=skip" package/passwall-packages/sing-box/Makefile
fi

# DDNS-GO 动态标签
DDNS_GO_LATEST=$(get_latest_tag "jeessy2/ddns-go")
DDNS_GO_LATEST=${DDNS_GO_LATEST#v}
if [ -n "$DDNS_GO_LATEST" ] && [ -f package/ddns-go/ddns-go/Makefile ]; then
    sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$DDNS_GO_LATEST/" package/ddns-go/ddns-go/Makefile
    sed -i "s/^PKG_HASH:=.*/PKG_HASH:=skip/" package/ddns-go/ddns-go/Makefile
fi

# SmartDNS 动态标签
SMARTDNS_TAG=$(get_latest_tag "pymumu/smartdns")
SMARTDNS_LATEST=$(echo "$SMARTDNS_TAG" | sed 's/^Release//')
[ -z "$SMARTDNS_LATEST" ] && SMARTDNS_LATEST="48.4" && SMARTDNS_TAG="Release48.4"
if [ -f package/smartdns/Makefile ]; then
    sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$SMARTDNS_LATEST/" package/smartdns/Makefile
    sed -i "s/^PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=$SMARTDNS_TAG/" package/smartdns/Makefile
    sed -i '/PKG_HASH/d;/PKG_MIRROR_HASH/d' package/smartdns/Makefile
    sed -i "/^PKG_SOURCE_VERSION:=/a PKG_HASH:=skip\nPKG_MIRROR_HASH:=skip" package/smartdns/Makefile
fi

for dir in package/passwall-packages package/ddns-go package/smartdns package/openwrt-daede package/luci-app-openclash; do
    [ -d "$dir" ] || continue
    find "$dir" -type f -name "Makefile" -exec sed -i -E \
        -e 's/^([[:space:]]*PKG_VERSION[[:space:]]*:?=[[:space:]]*[0-9]+(\.[0-9]+)*)[^0-9.].*/\1/g' \
        {} + || true
done

##############################################################################
# 6. 基础系统与网络参数优化
##############################################################################
# 默认 IP 调整为 10.0.0.10
sed -i 's/192.168.1.1/10.0.0.10/g' package/base-files/files/bin/config_generate

mkdir -p package/base-files/files/etc
echo 'net.netfilter.nf_conntrack_max=262144' >> package/base-files/files/etc/sysctl.conf
echo 'net.core.default_qdisc=fq' >> package/base-files/files/etc/sysctl.conf
echo 'net.ipv4.tcp_congestion_control=bbr' >> package/base-files/files/etc/sysctl.conf
echo 'export PS1="\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "' >> package/base-files/files/etc/profile

sed -i "s/IMG_PREFIX:=.*/IMG_PREFIX:=OpenWrt-PVE-N6000-$(date +%Y%m%d)/g" include/image.mk

# 默认中文界面
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
# 7. 生成 .config 编译配置
##############################################################################
touch .config
sed -i '/luci-app-transmission/d;/transmission-daemon/d' .config
sed -i '/luci-app-store/d;/luci-i18n-store/d' .config
sed -i '/dockerd/d;/docker/d;/dockerman/d' .config
sed -i '/CONFIG_PACKAGE_dnsmasq/d' .config
sed -i '/luci-app-dae/d;/CONFIG_PACKAGE_dae/d;/CONFIG_PACKAGE_daed/d' .config
sed -i '/luci-app-openclash/d;/luci-i18n-openclash/d' .config

echo "# CONFIG_PACKAGE_dnsmasq is not set" >> .config
echo "# CONFIG_PACKAGE_dockerd is not set" >> .config
echo "# CONFIG_PACKAGE_docker is not set" >> .config
echo "# CONFIG_PACKAGE_luci-app-dockerman is not set" >> .config
echo "# CONFIG_PACKAGE_containerd is not set" >> .config
echo "# CONFIG_PACKAGE_runc is not set" >> .config
echo "# CONFIG_PACKAGE_tini is not set" >> .config
echo "# CONFIG_PACKAGE_libnetwork is not set" >> .config

# 基础框架与目标平台
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

# PVE 专属 Agent 支持
echo "CONFIG_PACKAGE_qemu-ga=y" >> .config

# 硬件网卡驱动
echo "CONFIG_PACKAGE_kmod-igc=y" >> .config
echo "CONFIG_PACKAGE_kmod-igb=y" >> .config
echo "CONFIG_PACKAGE_kmod-e1000e=y" >> .config
echo "CONFIG_PACKAGE_kmod-r8169=y" >> .config
echo "CONFIG_PACKAGE_kmod-virtio-net=y" >> .config
echo "CONFIG_PACKAGE_kmod-virtio-blk=y" >> .config
echo "CONFIG_PACKAGE_kmod-virtio-scsi=y" >> .config

# 磁盘与文件系统
echo "CONFIG_PACKAGE_kmod-usb-storage=y" >> .config
echo "CONFIG_PACKAGE_kmod-usb-storage-uas=y" >> .config
echo "CONFIG_PACKAGE_kmod-fs-ext4=y" >> .config
echo "CONFIG_PACKAGE_kmod-fs-ntfs3=y" >> .config
echo "CONFIG_PACKAGE_kmod-vfat=y" >> .config
echo "CONFIG_PACKAGE_kmod-nls-utf8=y" >> .config
echo "CONFIG_PACKAGE_block-mount=y" >> .config
echo "CONFIG_PACKAGE_e2fsprogs=y" >> .config
echo "CONFIG_PACKAGE_blkid=y" >> .config
echo "CONFIG_PACKAGE_ntfs-3g=y" >> .config
echo "CONFIG_PACKAGE_fdisk=y" >> .config
echo "CONFIG_PACKAGE_parted=y" >> .config
echo "CONFIG_PACKAGE_lsblk=y" >> .config
echo "CONFIG_PACKAGE_smartmontools=y" >> .config

# 完整 eBPF/BTF 编译顶层工具链支持
echo "CONFIG_DEVEL=y" >> .config
echo "CONFIG_BPF_TOOLCHAIN_HOST=y" >> .config
echo "CONFIG_KERNEL_DEBUG_INFO=y" >> .config
echo "CONFIG_KERNEL_DEBUG_INFO_BTF=y" >> .config
echo "# CONFIG_KERNEL_DEBUG_INFO_REDUCED is not set" >> .config
echo "CONFIG_KERNEL_CGROUPS=y" >> .config
echo "CONFIG_KERNEL_CGROUP_BPF=y" >> .config
echo "CONFIG_KERNEL_BPF_EVENTS=y" >> .config
echo "CONFIG_KERNEL_XDP_SOCKETS=y" >> .config
echo "CONFIG_PACKAGE_kmod-xdp-sockets-diag=y" >> .config
echo "CONFIG_PACKAGE_kmod-sched-bpf=y" >> .config
echo "CONFIG_PACKAGE_kmod-sched-core=y" >> .config
echo "CONFIG_PACKAGE_kmod-veth=y" >> .config

# 核心路由转发环境
echo "CONFIG_PACKAGE_kmod-tun=y" >> .config
# [修复标注] 补充 PassWall 必备透明代理/NAT 关键内核依赖，解决无法启动的根本原因
echo "CONFIG_PACKAGE_kmod-nft-nat=y" >> .config
echo "CONFIG_PACKAGE_kmod-nft-tproxy=y" >> .config
echo "CONFIG_PACKAGE_kmod-nft-socket=y" >> .config
echo "CONFIG_PACKAGE_kmod-nft-bridge=y" >> .config
echo "CONFIG_PACKAGE_kmod-inet-diag=y" >> .config
echo "CONFIG_PACKAGE_kmod-crypto-hw-aesni=y" >> .config
echo "CONFIG_PACKAGE_kmod-crypto-xts=y" >> .config
echo "CONFIG_PACKAGE_kmod-crypto-gcm=y" >> .config
echo "CONFIG_PACKAGE_kmod-crypto-sha256=y" >> .config
echo "CONFIG_PACKAGE_kmod-crypto-sha512=y" >> .config
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
echo "CONFIG_PACKAGE_kmod-tcp-bbr=y" >> .config

# PassWall 全功能组件
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
# [修复标注] 补充 Shadowsocks-Rust 客户端支持，避免 SS 节点因找不到执行文件导致 PassWall 崩溃
echo "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Rust=y" >> .config
echo "CONFIG_PACKAGE_shadowsocks-rust=y" >> .config
echo "CONFIG_PACKAGE_chinadns-ng=y" >> .config
echo "CONFIG_PACKAGE_dns2socks=y" >> .config
echo "CONFIG_PACKAGE_microsocks=y" >> .config
echo "CONFIG_PACKAGE_ipt2socks=y" >> .config
echo "CONFIG_PACKAGE_v2ray-geodata=y" >> .config
echo "CONFIG_PACKAGE_geoview=y" >> .config
echo "CONFIG_PACKAGE_tcping=y" >> .config

# openwrt-daede 统一套件
echo "CONFIG_PACKAGE_luci-app-daede=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-daede-zh-cn=y" >> .config
echo "CONFIG_PACKAGE_daed=y" >> .config
echo "CONFIG_PACKAGE_dae=y" >> .config

# OpenClash 完整依赖链
echo "CONFIG_PACKAGE_luci-app-openclash=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-openclash-zh-cn=y" >> .config
echo "CONFIG_PACKAGE_luci-compat=y" >> .config
echo "CONFIG_PACKAGE_ruby=y" >> .config
echo "CONFIG_PACKAGE_ruby-yaml=y" >> .config
echo "CONFIG_PACKAGE_coreutils=y" >> .config
echo "CONFIG_PACKAGE_coreutils-nohup=y" >> .config
echo "CONFIG_PACKAGE_bash=y" >> .config
echo "CONFIG_PACKAGE_curl=y" >> .config
echo "CONFIG_PACKAGE_tar=y" >> .config
echo "CONFIG_PACKAGE_unzip=y" >> .config

# 扩展工具
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

# 禁用冗余无线协议
echo "# CONFIG_PACKAGE_tailscale is not set" >> .config
echo "# CONFIG_PACKAGE_luci-app-tailscale is not set" >> .config
echo "# CONFIG_PACKAGE_luci-app-samba4 is not set" >> .config
echo "# CONFIG_PACKAGE_luci-app-upnp is not set" >> .config
echo "# CONFIG_PACKAGE_luci-app-ddns is not set" >> .config
echo "# CONFIG_PACKAGE_luci-app-wol is not set" >> .config
echo "# CONFIG_PACKAGE_luci-app-wireguard is not set" >> .config
echo "# CONFIG_PACKAGE_luci-app-openvpn is not set" >> .config
echo "# CONFIG_PACKAGE_luci-app-qos is not set" >> .config
echo "# CONFIG_PACKAGE_wpad-basic is not set" >> .config
echo "# CONFIG_PACKAGE_wpad-openssl is not set" >> .config
echo "# CONFIG_PACKAGE_hostapd is not set" >> .config
echo "# CONFIG_PACKAGE_ppp is not set" >> .config
echo "# CONFIG_PACKAGE_ppp-mod-pppoe is not set" >> .config

##############################################################################
# 8. 磁盘挂载与多代理互斥自启管理
##############################################################################
cat > package/base-files/files/etc/uci-defaults/99-auto-mount << 'EOF'
#!/bin/sh
TARGET_DEV=""
if [ -b "/dev/sda3" ]; then
    TARGET_DEV="/dev/sda3"
elif [ -b "/dev/vda3" ]; then
    TARGET_DEV="/dev/vda3"
fi

if [ -n "$TARGET_DEV" ]; then
    uci -q delete fstab.data
    uci set fstab.data="mount"
    uci set fstab.data.device="$TARGET_DEV"
    uci set fstab.data.target="/mnt/sda3"
    uci set fstab.data.fstype="ext4"
    uci set fstab.data.options="rw,relatime"
    uci set fstab.data.enabled="1"
    uci commit fstab
    /etc/init.d/fstab enable
    block mount
fi
rm -f /etc/uci-defaults/99-auto-mount
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-auto-mount

cat > package/base-files/files/etc/uci-defaults/99-enable-services << 'EOF'
#!/bin/sh
# 启用 SmartDNS
uci -q set smartdns.@smartdns[0].enabled='1'
uci commit smartdns
/etc/init.d/smartdns enable || true

# [修复标注] 安全停用 PassWall 自启，防止配置文件不存在时产生脏写入导致配置结构损坏
if [ -f "/etc/config/passwall" ]; then
    uci -q set passwall.@global[0].enabled='0' 2>/dev/null || true
    uci commit passwall 2>/dev/null || true
fi
/etc/init.d/passwall disable || true

uci -q set openclash.config.enable='0'
uci commit openclash || true
/etc/init.d/openclash disable || true

/etc/init.d/daed disable 2>/dev/null || true
/etc/init.d/dae  disable 2>/dev/null || true
uci -q set daede.@global[0].enabled='0' 2>/dev/null || true
uci -q set daede.config.enabled='0' 2>/dev/null || true
uci commit daede 2>/dev/null || true

rm -f /etc/uci-defaults/99-enable-services
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-enable-services

##############################################################################
# 9. 内核 BPF/BTF 配置多层注入（幂等性操作）
##############################################################################
set_kconfig() {
    local opt="$1" file="$2"
    sed -i "/# ${opt} is not set/d" "$file"
    grep -q "^${opt}=y" "$file" || echo "${opt}=y" >> "$file"
}

for conf in target/linux/generic/config-* target/linux/x86/config-* target/linux/x86/64/config-*; do
    [ -f "$conf" ] || continue
    set_kconfig "CONFIG_BPF" "$conf"
    set_kconfig "CONFIG_BPF_SYSCALL" "$conf"
    set_kconfig "CONFIG_BPF_JIT" "$conf"
    set_kconfig "CONFIG_HAVE_EBPF_JIT" "$conf"
    set_kconfig "CONFIG_BPF_EVENTS" "$conf"
    set_kconfig "CONFIG_CGROUP_BPF" "$conf"
    set_kconfig "CONFIG_DEBUG_INFO" "$conf"
    set_kconfig "CONFIG_DEBUG_INFO_BTF" "$conf"
    set_kconfig "CONFIG_XDP_SOCKETS" "$conf"
    set_kconfig "CONFIG_NET_SCH_BPF" "$conf"
    set_kconfig "CONFIG_NET_ACT_BPF" "$conf"
    set_kconfig "CONFIG_NET_CLS_BPF" "$conf"
    sed -i '/CONFIG_DEBUG_INFO_REDUCED/d' "$conf"
    echo "# CONFIG_DEBUG_INFO_REDUCED is not set" >> "$conf"
done

echo "=== diyyb1-part2.sh 执行完成（已适配 N6000 兼容架构） ==="
