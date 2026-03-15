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
clone_or_pull https://github.com/rufengsuixing/luci-app-adguardhome.git package/luci-app-adguardhome
clone_or_pull https://github.com/lisaac/luci-app-diskman.git package/luci-app-diskman

# SmartDNS
echo "处理 smartdns 和 luci-app-smartdns..."
sed -i 's/1.2024.45/1.2025.47/g; s/9ee27e7ba2d9789b7e007410e76c06a957f85e98/0f1912ab020ea9a60efac4732442f0bb7093f40b/g; /^PKG_MIRROR_HASH/s/^/#/' feeds/packages/net/smartdns/Makefile
rm -rf package/luci-app-smartdns
clone_or_pull https://github.com/pymumu/luci-app-smartdns.git package/luci-app-smartdns master

# =================================================================
# 3. 终极 apk 净化 (严格修复正则执行顺序)
# =================================================================
echo "正在对所有第三方包进行强力净化..."

THIRD_PARTY_DIRS="feeds/istore feeds/istore_packages package/pw-luci package/lucky package/luci-app-dockerman package/dae package/luci-app-dae package/v2ray-geodata package/ddns-go package/openwrt-fakehttp package/luci-app-fakehttp package/luci-app-smartdns package/luci-app-adguardhome package/luci-app-diskman"

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
# 5. 固件版本号与真实编译日期注入 (核弹级终极修复：全局变量直接夺权)
# =================================================================
echo "注入专属编译日期与版本号..."

COMPILE_DATE_SHORT="$(date +"%y.%m.%d")"
COMPILE_DATE_LONG="$(date +"%Y-%m-%d")"

# 1. 无视一切模板与格式变化，直接在全局 version.mk 最末尾强行覆盖底层变量！
echo "VERSION_DIST:=OpenWrt PVE-N6000" >> include/version.mk
echo "VERSION_NUMBER:=R${COMPILE_DATE_SHORT}" >> include/version.mk
echo "REVISION:=(${COMPILE_DATE_LONG})" >> include/version.mk

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

echo "=== diyyb1-part2.sh 执行完成，零警告护航模式就绪 ==="
