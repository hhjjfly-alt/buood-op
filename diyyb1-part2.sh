#!/bin/bash
# diyyb1-part2.sh (无 Docker 极速纯净版)
# 适用：N6000/PVE + 中文 + PassWall/PassWall2 + dae + SmartDNS
# 已彻底删除所有 Docker / dockerd / luci-app-dockerman 相关代码
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
    tag=$(curl -sL --connect-timeout 15 --max-time 30 \
        "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
        | grep -oE '"tag_name":[[:space:]]*"[^"]+"' \
        | head -1 \
        | sed -E 's/.*"([^"]+)".*/\1/')
    echo "$tag"
}

echo "=== 开始执行 diyyb1-part2.sh (无 Docker 纯净版) ==="

# =================================================================
# 1. 清理冲突依赖包
# =================================================================
rm -rf feeds/packages/net/{chinadns-ng,dns2socks,geoview,hysteria,ipt2socks,microsocks,naiveproxy,shadow-tls,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,sing-box,tcping,trojan-plus,tuic-client,v2ray-core,v2ray-geodata,v2ray-plugin,xray-core,xray-plugin}
rm -rf feeds/luci/applications/luci-app-passwall

# =================================================================
# 2. 拉取第三方源码（已删除所有 Docker 相关）
# =================================================================
# PassWall 1
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git package/passwall-packages
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall.git package/passwall-luci
rm -rf package/passwall-packages/shadowsocksr-libev 2>/dev/null || true

# PassWall 2
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall2.git package/passwall2

# Lucky
clone_or_pull https://github.com/gdy666/luci-app-lucky.git package/lucky

# DAE
rm -rf package/dae package/luci-app-dae
git clone --depth=1 https://github.com/immortalwrt/packages package/immortalwrt-packages
if [ -d package/immortalwrt-packages/net/dae ]; then
    mv package/immortalwrt-packages/net/dae package/dae
fi
rm -rf package/immortalwrt-packages

git clone --depth=1 https://github.com/immortalwrt/luci package/immortalwrt-luci
if [ -d package/immortalwrt-luci/applications/luci-app-dae ]; then
    mv package/immortalwrt-luci/applications/luci-app-dae package/luci-app-dae
    rm -rf package/luci-app-dae/dae 2>/dev/null || true
fi
rm -rf package/immortalwrt-luci

# DDNS-GO, Geodata, Diskman
clone_or_pull https://github.com/sbwml/v2ray-geodata package/v2ray-geodata
clone_or_pull https://github.com/sirpdboy/luci-app-ddns-go package/ddns-go
clone_or_pull https://github.com/lisaac/luci-app-diskman.git package/luci-app-diskman

# SmartDNS
rm -rf feeds/packages/net/smartdns
clone_or_pull https://github.com/pymumu/openwrt-smartdns.git package/smartdns master
rm -rf package/luci-app-smartdns
clone_or_pull https://github.com/pymumu/luci-app-smartdns.git package/luci-app-smartdns master

# =================================================================
# 3. 源码调整与依赖修复
# =================================================================
if [ -f package/dae/Makefile ]; then
    sed -i 's|../../lang/golang/golang-package.mk|$(TOPDIR)/feeds/packages/lang/golang/golang-package.mk|g' package/dae/Makefile
    sed -i 's/PKG_HASH:=.*/PKG_HASH:=skip/g' package/dae/Makefile
    sed -i 's/^PKG_MIRROR_HASH:=.*/PKG_MIRROR_HASH:=skip/g' package/dae/Makefile
fi
if [ -f package/luci-app-dae/Makefile ]; then
    sed -i 's|../../luci.mk|$(TOPDIR)/feeds/luci/luci.mk|g' package/luci-app-dae/Makefile
fi
if [ -f package/smartdns/Makefile ]; then
    sed -i 's|../../lang/rust/rust-package.mk|$(TOPDIR)/feeds/packages/lang/rust/rust-package.mk|g' package/smartdns/Makefile
    sed -i 's/DEPENDS:=.*/& +zlib/g' package/smartdns/Makefile
fi

# =================================================================
# 4. 更新 Feeds 与环境净化 (适配 APK 严格版本规范)
# =================================================================
echo "更新 Feeds 源..."
rm -rf tmp/
./scripts/feeds update -i

echo "执行包名净化，修复 APK 版本号校验..."
THIRD_PARTY_DIRS="package/passwall-packages package/passwall-luci package/passwall2 package/lucky package/dae package/luci-app-dae package/v2ray-geodata package/ddns-go package/luci-app-diskman package/smartdns package/luci-app-smartdns feeds/istore_packages"

for dir in $THIRD_PARTY_DIRS; do
    if [ -d "$dir" ]; then
        find "$dir" -type f -name "Makefile" -exec sed -i -E 's/\([<=>]+[^)]+\)//g' {} + || true
        find "$dir" -type f -name "Makefile" -exec sed -i -E 's/^([[:space:]]*PKG_VERSION[[:space:]]*:?=[[:space:]]*)[vV]([0-9])/\1\2/g' {} + || true
        find "$dir" -type f -name "Makefile" -exec sed -i -E 's/^([[:space:]]*PKG_VERSION[[:space:]]*:?=[[:space:]]*[0-9]+(\.[0-9]+)*)[^0-9.].*/\1/g' {} + || true
        find "$dir" -type f -name "Makefile" -exec sed -i -E 's/^([[:space:]]*PKG_RELEASE[[:space:]]*:?=[[:space:]]*[0-9]+).*/\1/g' {} + || true
        find "$dir" -type f -name "Makefile" -exec sed -i -E 's/^([[:space:]]*PKG_RELEASE[[:space:]]*:?=)[[:space:]]*$/\11/g' {} + || true
    fi
done

# 双保险修复 luci-app-zerotier
ZT_MK="feeds/istore_packages/luci-app-zerotier/Makefile"
if [ -f "$ZT_MK" ]; then
    echo "修复 luci-app-zerotier 版本..."
    sed -i 's/^PKG_VERSION:=.*/PKG_VERSION:=1.3.0/' "$ZT_MK"
    sed -i 's/^PKG_RELEASE:=.*/PKG_RELEASE:=1/' "$ZT_MK"
    grep -q '^PKG_RELEASE:=' "$ZT_MK" || sed -i '/^PKG_VERSION:=/a PKG_RELEASE:=1' "$ZT_MK"
fi

./scripts/feeds install -a
./scripts/feeds install -p istore_packages luci-app-zerotier 2>/dev/null || true

# =================================================================
# 5. 动态最新版本注入
# =================================================================
SING_BOX_LATEST=$(get_latest_tag "SagerNet/sing-box")
SING_BOX_LATEST=${SING_BOX_LATEST#v}
if [ -n "$SING_BOX_LATEST" ] && [ -f "package/passwall-packages/sing-box/Makefile" ]; then
    echo "更新 sing-box 到 $SING_BOX_LATEST"
    sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$SING_BOX_LATEST/" package/passwall-packages/sing-box/Makefile
    sed -i "s/^PKG_HASH:=.*/PKG_HASH:=skip/" package/passwall-packages/sing-box/Makefile
    sed -i "s/^PKG_MIRROR_HASH:=.*/PKG_MIRROR_HASH:=skip/" package/passwall-packages/sing-box/Makefile 2>/dev/null || true
fi

DDNS_GO_LATEST=$(get_latest_tag "jeessy2/ddns-go")
DDNS_GO_LATEST=${DDNS_GO_LATEST#v}
if [ -n "$DDNS_GO_LATEST" ] && [ -f "package/ddns-go/ddns-go/Makefile" ]; then
    echo "更新 ddns-go 到 $DDNS_GO_LATEST"
    sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$DDNS_GO_LATEST/" package/ddns-go/ddns-go/Makefile
    sed -i "s/^PKG_HASH:=.*/PKG_HASH:=skip/" package/ddns-go/ddns-go/Makefile
fi

SMARTDNS_TAG=$(get_latest_tag "pymumu/smartdns")
SMARTDNS_LATEST=$(echo "$SMARTDNS_TAG" | sed 's/^Release//')
if [ -z "$SMARTDNS_LATEST" ]; then
    SMARTDNS_LATEST="48.4"
    SMARTDNS_TAG="Release48.4"
fi
if [ -f "package/smartdns/Makefile" ]; then
    echo "更新 smartdns 到 $SMARTDNS_LATEST ($SMARTDNS_TAG)"
    sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$SMARTDNS_LATEST/g" package/smartdns/Makefile
    sed -i "s/^PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=$SMARTDNS_TAG/g" package/smartdns/Makefile
    sed -i "s/^PKG_HASH:=.*/PKG_HASH:=skip/g" package/smartdns/Makefile
    sed -i "s/^PKG_MIRROR_HASH:=.*/PKG_MIRROR_HASH:=skip/g" package/smartdns/Makefile
fi

# =================================================================
# 6. 系统底层配置修改
# =================================================================
sed -i 's/192.168.1.1/10.0.0.10/g' package/base-files/files/bin/config_generate
mkdir -p package/base-files/files/etc
echo 'net.netfilter.nf_conntrack_max=165535' >> package/base-files/files/etc/sysctl.conf
echo 'export PS1="\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]$ "' >> package/base-files/files/etc/profile
sed -i "s/IMG_PREFIX:=.*/IMG_PREFIX:=OpenWrt-PVE-N6000-$(date +%Y%m%d)/g" include/image.mk

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
# 7. 写入 .config 编译标识（已彻底删除所有 Docker 相关）
# =================================================================
touch .config
sed -i '/luci-app-transmission/d' .config
sed -i '/luci-i18n-transmission/d' .config
sed -i '/transmission-daemon/d' .config
sed -i '/luci-app-store/d' .config
sed -i '/luci-i18n-store/d' .config
sed -i '/CONFIG_PACKAGE_qemu-ga/d' .config
# 强制删除可能残留的 Docker 配置
sed -i '/dockerd/d' .config
sed -i '/docker/d' .config
sed -i '/luci-app-dockerman/d' .config
sed -i '/luci-i18n-dockerman/d' .config

echo "CONFIG_LUCI_LANG_zh_Hans=y" >> .config
echo "CONFIG_LUCI_LANG_zh_cn=y" >> .config
echo "# CONFIG_PACKAGE_qemu-ga is not set" >> .config

COMPILE_DATE_SHORT="$(date +"%y.%m.%d")"
sed -i '/CONFIG_IMAGEOPT/d' .config
sed -i '/CONFIG_VERSIONOPT/d' .config
sed -i '/CONFIG_VERSION_NUMBER/d' .config
sed -i '/CONFIG_VERSION_CODE/d' .config
echo "CONFIG_IMAGEOPT=y" >> .config
echo "CONFIG_VERSIONOPT=y" >> .config
echo "CONFIG_VERSION_NUMBER=\"R${COMPILE_DATE_SHORT}\"" >> .config
echo "CONFIG_VERSION_CODE=\"\"" >> .config

# 文件系统
echo "CONFIG_PACKAGE_block-mount=y" >> .config
echo "CONFIG_PACKAGE_kmod-fs-ext4=y" >> .config
echo "CONFIG_PACKAGE_e2fsprogs=y" >> .config
echo "CONFIG_PACKAGE_blkid=y" >> .config
echo "CONFIG_PACKAGE_kmod-fs-ntfs3=y" >> .config
echo "CONFIG_PACKAGE_ntfs-3g=y" >> .config
echo "CONFIG_PACKAGE_kmod-nls-utf8=y" >> .config

# PassWall 1（补全主包）
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

# dae
echo "CONFIG_PACKAGE_dae=y" >> .config
echo "CONFIG_PACKAGE_luci-app-dae=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-dae-zh-cn=y" >> .config

# PassWall 2
echo "CONFIG_PACKAGE_luci-app-passwall2=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-passwall2-zh-cn=y" >> .config

# 其他插件
echo "CONFIG_PACKAGE_mihomo=y" >> .config
echo "CONFIG_PACKAGE_ksmbd-server=y" >> .config
echo "CONFIG_PACKAGE_luci-app-ksmbd=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-ksmbd-zh-cn=y" >> .config
echo "CONFIG_PACKAGE_wsdd2=y" >> .config
echo "CONFIG_PACKAGE_autosamba=y" >> .config
echo "CONFIG_PACKAGE_ttyd=y" >> .config
echo "CONFIG_PACKAGE_luci-app-ttyd=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-ttyd-zh-cn=y" >> .config
echo "CONFIG_PACKAGE_tailscale=y" >> .config
echo "CONFIG_PACKAGE_kmod-tun=y" >> .config

# =================================================================
# 8. 自动挂载与自启服务脚本（已删除 Docker 相关）
# =================================================================
cat > package/base-files/files/etc/uci-defaults/99-auto-mount <<'EOF'
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

cat > package/base-files/files/etc/uci-defaults/99-enable-services <<'EOF'
#!/bin/sh
uci -q set smartdns.@smartdns[0].enabled='1'
uci commit smartdns
/etc/init.d/smartdns enable || true
rm -f /etc/uci-defaults/99-enable-services
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-enable-services

# =================================================================
# 9. 内核 BPF / BTF / XDP 补丁（dae 需要）
# =================================================================
for conf in target/linux/generic/config-* target/linux/x86/config-*; do
    [ -f "$conf" ] || continue
    {
        echo "CONFIG_NET_SCH_BPF=y"
        echo "CONFIG_NET_ACT_BPF=y"
        echo "CONFIG_NET_CLS_BPF=y"
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
    } >> "$conf"
done

echo "=== diyyb1-part2.sh 执行完成（无 Docker 纯净版） ==="
