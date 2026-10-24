#!/bin/bash
# diyyb1-part2.sh
# 生产加固版（PassWall + openwrt-daede + OpenClash + eBPF/BTF）
# 适配最新 OpenWrt + N6000/PVE + I226（Jasper Lake 兼容内核）
# 已去掉：trojan-go/trojan-plus、强制 dns2socks/ipt2socks、istore 依赖、重复全量 feeds update
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

echo "=== 开始执行 diyyb1-part2.sh（N6000 兼容内核版） ==="

##############################################################################
# 1. 清理官方冲突包与历史废弃包
##############################################################################
rm -rf feeds/packages/net/{chinadns-ng,dns2socks,geoview,hysteria,ipt2socks,microsocks,naiveproxy,shadow-tls,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,sing-box,tcping,trojan-plus,tuic-client,v2ray-core,v2ray-geodata,v2ray-plugin,xray-core,xray-plugin,smartdns,dae,daed} 2>/dev/null || true
rm -rf feeds/luci/applications/{luci-app-passwall,luci-app-smartdns,luci-app-dae,luci-app-daed,luci-app-daede,luci-app-openclash} 2>/dev/null || true
rm -rf package/dae package/daed package/luci-app-dae package/luci-app-daed package/luci-app-daede package/openwrt-daede package/luci-app-openclash 2>/dev/null || true

##############################################################################
# 2. 拉取第三方源
##############################################################################
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git package/passwall-packages
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall.git package/passwall-luci
# 去掉 SSR；trojan 系不在 .config 启用（见第 7 节）
rm -rf package/passwall-packages/shadowsocksr-libev package/passwall2 2>/dev/null || true

clone_or_pull https://github.com/gdy666/luci-app-lucky.git package/lucky
clone_or_pull https://github.com/kenzok8/openwrt-daede.git package/openwrt-daede

rm -rf package/luci-app-openclash package/openclash-tmp
git clone --depth=1 https://github.com/vernesong/OpenClash.git package/openclash-tmp
if [ -d package/openclash-tmp/luci-app-openclash ]; then
    mv package/openclash-tmp/luci-app-openclash package/luci-app-openclash
fi
rm -rf package/openclash-tmp

# N6000：预置无 AVX 的 Mihomo compatible 核心
mkdir -p package/luci-app-openclash/root/etc/openclash/core
CLASH_META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-amd64-compatible.tar.gz"
echo "正在预置 OpenClash Mihomo 兼容版核心..."
if curl -sL --connect-timeout 15 --max-time 90 "$CLASH_META_URL" -o /tmp/clash_meta.tar.gz; then
    if tar -zxf /tmp/clash_meta.tar.gz -C /tmp/ 2>/dev/null && [ -f /tmp/clash ]; then
        # 简单 ELF 校验
        if head -c 4 /tmp/clash | grep -qa $'\x7fELF'; then
            mv /tmp/clash package/luci-app-openclash/root/etc/openclash/core/clash_meta
            chmod +x package/luci-app-openclash/root/etc/openclash/core/clash_meta
            echo "OpenClash 兼容版核心预置成功"
        else
            echo "警告：核心非 ELF，跳过预置"
            rm -f /tmp/clash
        fi
    else
        echo "警告：兼容版核心解压失败"
    fi
    rm -f /tmp/clash_meta.tar.gz /tmp/clash 2>/dev/null || true
else
    echo "警告：OpenClash 核心下载失败，跳过预置"
fi

clone_or_pull https://github.com/sbwml/v2ray-geodata package/v2ray-geodata
clone_or_pull https://github.com/sirpdboy/luci-app-ddns-go package/ddns-go
clone_or_pull https://github.com/lisaac/luci-app-diskman.git package/luci-app-diskman
clone_or_pull https://github.com/pymumu/openwrt-smartdns.git package/smartdns master
clone_or_pull https://github.com/pymumu/luci-app-smartdns.git package/luci-app-smartdns master

##############################################################################
# 3. 依赖与路径修复（定点，避免全局暴力 sed）
##############################################################################
if [ -f package/smartdns/Makefile ]; then
    sed -i 's|../../lang/rust/rust-package.mk|$(TOPDIR)/feeds/packages/lang/rust/rust-package.mk|g' package/smartdns/Makefile 2>/dev/null || true
    if ! grep -q 'DEPENDS.*zlib' package/smartdns/Makefile; then
        sed -i 's/^[[:space:]]*DEPENDS:=/& +zlib /' package/smartdns/Makefile
    fi
fi

if [ -f package/luci-app-openclash/Makefile ]; then
    sed -i 's|../../luci.mk|$(TOPDIR)/feeds/luci/luci.mk|g' package/luci-app-openclash/Makefile 2>/dev/null || true
    sed -i 's/^PKG_RELEASE:=.*/PKG_RELEASE:=1/' package/luci-app-openclash/Makefile
fi

##############################################################################
# 4. 轻量注册第三方包（YAML 已 feeds update/install，此处不再全量 update -a）
##############################################################################
rm -rf tmp/
# 仅安装/刷新依赖索引，避免重复拉全网 feeds
./scripts/feeds install -a 2>/dev/null || true

##############################################################################
# 5. 动态版本 + 跳过哈希（均带保底，防 API 限流）
##############################################################################
SING_BOX_LATEST=$(get_latest_tag "SagerNet/sing-box")
SING_BOX_LATEST=${SING_BOX_LATEST#v}
[ -z "$SING_BOX_LATEST" ] && SING_BOX_LATEST="1.14.3"
if [ -f package/passwall-packages/sing-box/Makefile ]; then
    echo "sing-box => $SING_BOX_LATEST"
    sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$SING_BOX_LATEST/" package/passwall-packages/sing-box/Makefile
    sed -i '/PKG_HASH/d;/PKG_MIRROR_HASH/d' package/passwall-packages/sing-box/Makefile
    sed -i "/^PKG_VERSION:=/a PKG_HASH:=skip\nPKG_MIRROR_HASH:=skip" package/passwall-packages/sing-box/Makefile
fi

DDNS_GO_LATEST=$(get_latest_tag "jeessy2/ddns-go")
DDNS_GO_LATEST=${DDNS_GO_LATEST#v}
[ -z "$DDNS_GO_LATEST" ] && DDNS_GO_LATEST="6.9.0"
if [ -f package/ddns-go/ddns-go/Makefile ]; then
    echo "ddns-go => $DDNS_GO_LATEST"
    sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$DDNS_GO_LATEST/" package/ddns-go/ddns-go/Makefile
    sed -i "s/^PKG_HASH:=.*/PKG_HASH:=skip/" package/ddns-go/ddns-go/Makefile
fi

SMARTDNS_TAG=$(get_latest_tag "pymumu/smartdns")
SMARTDNS_LATEST=$(echo "$SMARTDNS_TAG" | sed 's/^Release//')
[ -z "$SMARTDNS_LATEST" ] && SMARTDNS_LATEST="48.4" && SMARTDNS_TAG="Release48.4"
if [ -f package/smartdns/Makefile ]; then
    echo "smartdns => $SMARTDNS_LATEST ($SMARTDNS_TAG)"
    sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$SMARTDNS_LATEST/" package/smartdns/Makefile
    sed -i "s/^PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=$SMARTDNS_TAG/" package/smartdns/Makefile
    sed -i '/PKG_HASH/d;/PKG_MIRROR_HASH/d' package/smartdns/Makefile
    sed -i "/^PKG_SOURCE_VERSION:=/a PKG_HASH:=skip\nPKG_MIRROR_HASH:=skip" package/smartdns/Makefile
fi

##############################################################################
# 6. 基础系统与网络参数
##############################################################################
sed -i 's/192.168.1.1/10.0.0.10/g' package/base-files/files/bin/config_generate
mkdir -p package/base-files/files/etc
echo 'net.netfilter.nf_conntrack_max=262144' >> package/base-files/files/etc/sysctl.conf
echo 'net.core.default_qdisc=fq' >> package/base-files/files/etc/sysctl.conf
echo 'net.ipv4.tcp_congestion_control=bbr' >> package/base-files/files/etc/sysctl.conf
echo 'export PS1="\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "' >> package/base-files/files/etc/profile
sed -i "s/IMG_PREFIX:=.*/IMG_PREFIX:=OpenWrt-PVE-N6000-$(date +%Y%m%d)/g" include/image.mk

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
# 7. 生成 .config
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

echo "CONFIG_PACKAGE_qemu-ga=y" >> .config
echo "CONFIG_PACKAGE_kmod-igc=y" >> .config
echo "CONFIG_PACKAGE_kmod-igb=y" >> .config
echo "CONFIG_PACKAGE_kmod-e1000e=y" >> .config
echo "CONFIG_PACKAGE_kmod-r8169=y" >> .config
echo "CONFIG_PACKAGE_kmod-virtio-net=y" >> .config
echo "CONFIG_PACKAGE_kmod-virtio-blk=y" >> .config
echo "CONFIG_PACKAGE_kmod-virtio-scsi=y" >> .config

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

echo "CONFIG_PACKAGE_kmod-tun=y" >> .config
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

# PassWall（无 Trojan-Go / Trojan-Plus）
echo "CONFIG_PACKAGE_luci-app-passwall=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-passwall-zh-cn=y" >> .config
echo "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Hysteria=y" >> .config
echo "CONFIG_PACKAGE_hysteria=y" >> .config
echo "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_SingBox=y" >> .config
echo "CONFIG_PACKAGE_sing-box=y" >> .config
echo "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Xray=y" >> .config
echo "CONFIG_PACKAGE_xray-core=y" >> .config
echo "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Rust=y" >> .config
echo "CONFIG_PACKAGE_shadowsocks-rust=y" >> .config
echo "# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Trojan_Go is not set" >> .config
echo "# CONFIG_PACKAGE_trojan-go is not set" >> .config
echo "# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Trojan_Plus is not set" >> .config
echo "# CONFIG_PACKAGE_trojan-plus is not set" >> .config
echo "CONFIG_PACKAGE_chinadns-ng=y" >> .config
echo "CONFIG_PACKAGE_microsocks=y" >> .config
echo "CONFIG_PACKAGE_v2ray-geodata=y" >> .config
echo "CONFIG_PACKAGE_geoview=y" >> .config
echo "CONFIG_PACKAGE_tcping=y" >> .config
# 不再强制：dns2socks / ipt2socks（PassWall 若强依赖会自行选中）

echo "CONFIG_PACKAGE_luci-app-daede=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-daede-zh-cn=y" >> .config
echo "CONFIG_PACKAGE_daed=y" >> .config
echo "CONFIG_PACKAGE_dae=y" >> .config

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

echo "CONFIG_PACKAGE_luci-app-smartdns=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-smartdns-zh-cn=y" >> .config
echo "CONFIG_PACKAGE_smartdns=y" >> .config
echo "CONFIG_PACKAGE_luci-app-ddns-go=y" >> .config
echo "CONFIG_PACKAGE_luci-app-diskman=y" >> .config
echo "CONFIG_PACKAGE_luci-app-lucky=y" >> .config

# 官方 feeds zerotier（不再用 istore 旧 luci）
echo "CONFIG_PACKAGE_luci-app-zerotier=y" >> .config
echo "CONFIG_PACKAGE_zerotier=y" >> .config

echo "CONFIG_PACKAGE_luci-app-ksmbd=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-ksmbd-zh-cn=y" >> .config
echo "CONFIG_PACKAGE_ksmbd-server=y" >> .config
echo "CONFIG_PACKAGE_wsdd2=y" >> .config
echo "CONFIG_PACKAGE_luci-app-ttyd=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-ttyd-zh-cn=y" >> .config
echo "CONFIG_PACKAGE_ttyd=y" >> .config

echo "# CONFIG_PACKAGE_autosamba is not set" >> .config
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
# 8. 磁盘挂载与服务默认（自动挂载仍只认 sda3/vda3）
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
uci -q set smartdns.@smartdns[0].enabled='1'
uci commit smartdns
/etc/init.d/smartdns enable || true

if [ -f "/etc/config/passwall" ]; then
    uci -q set passwall.@global[0].enabled='0' 2>/dev/null || true
    uci commit passwall 2>/dev/null || true
fi
/etc/init.d/passwall disable || true

uci -q set openclash.config.enable='0'
uci commit openclash || true
/etc/init.d/openclash disable || true

/etc/init.d/daed disable 2>/dev/null || true
/etc/init.d/dae disable 2>/dev/null || true
uci -q set daede.@global[0].enabled='0' 2>/dev/null || true
uci -q set daede.config.enabled='0' 2>/dev/null || true
uci commit daede 2>/dev/null || true

rm -f /etc/uci-defaults/99-enable-services
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-enable-services

##############################################################################
# 9. 内核 BPF/BTF 注入
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

echo "=== diyyb1-part2.sh 执行完成 ==="
