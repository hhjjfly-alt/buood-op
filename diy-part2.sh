#!/bin/bash
#  diy-part2.sh  （After Update feeds）
#  功能清单：
#  1. 万能克隆函数
#  2. 最新 PassWall (独立分仓结构，遵循官方规范)
#  3. 默认 IP / 主机名 / 固件名 / 系统版本加日期
#  4. SmartDNS 稳健 Bump (规避硬编码失败)
#  5. 额外插件（lucky & dockerman）幂等克隆
#  6. 连接数优化 & 其它系统调优
#  7. 内建 Docker 编译崩溃修复补丁 (PR #30288)

########### 万能函数：克隆或拉取最新 ###########
clone_or_pull() {
  local repo=$1 dir=$2
  if [[ -d "$dir/.git" ]]; then
    echo "Update $dir ..."
    git -C "$dir" fetch --depth 1
    git -C "$dir" reset --hard origin/HEAD
  else
    echo "Clone $repo -> $dir ..."
    git clone --depth 1 "$repo" "$dir"
  fi
}

########### 0. 若 istore 已存在则跳过（避免重复） ###########
grep -q '^src-git istore' feeds.conf.default || {
  echo 'src-git istore https://github.com/linkease/istore;main' >> feeds.conf.default
  ./scripts/feeds update istore
  ./scripts/feeds install -d y -p istore luci-app-store
}

########### 1. 最新 PassWall（严格遵循官方规范） ###########
# 1.1 移除 OpenWrt feeds 自带的核心库，避免底层包冲突 
rm -rf feeds/packages/net/{chinadns-ng,dns2socks,geoview,hysteria,ipt2socks,microsocks,naiveproxy,shadow-tls,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,sing-box,tcping,trojan-plus,tuic-client,v2ray-core,v2ray-geodata,v2ray-plugin,xray-core,xray-plugin}
rm -rf feeds/luci/applications/luci-app-passwall

# 1.2 分别独立克隆 PassWall 界面和依赖包仓，切勿暴力覆盖合并
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git package/passwall-packages
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall.git package/passwall-luci

########### 2. 默认 IP / 主机名 / 固件名 / 系统版本 ###########
# 2.1 默认 IP
sed -i 's/192.168.1.1/10.0.0.10/g' package/base-files/files/bin/config_generate

# 2.2 固件名加日期
sed -i 's/IMG_PREFIX:=.*/IMG_PREFIX:=full-$(shell date +%Y%m%d)-$(VERSION_DIST_SANITIZED)/g' include/image.mk

# 2.3 系统版本加日期（保留原描述）
pushd package/lean/default-settings/files
sed -i '/http/d' zzz-default-settings

orig_version="$(grep DISTRIB_REVISION= zzz-default-settings | awk -F"'" '{print $2}')"
sed -i "s/${orig_version}/${orig_version} ($(date +%Y-%m-%d))/g" zzz-default-settings
# sed -i "s/\(DISTRIB_DESCRIPTION=.*\)'/\1 ($(date +%Y%m%d))'/" zzz-default-settings
popd

########### 3. SmartDNS 稳健版本 Bump ###########
# 使用动态正则锚定，防止官方版本号变更导致 sed 命令失效
if [ -f feeds/packages/net/smartdns/Makefile ]; then
  sed -i -E 's/^PKG_VERSION:=.*/PKG_VERSION:=1.2025.47/' feeds/packages/net/smartdns/Makefile
  sed -i -E 's/^PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=0f1912ab020ea9a60efac4732442f0bb7093f40b/' feeds/packages/net/smartdns/Makefile
  sed -i -E 's/^PKG_MIRROR_HASH:=/#PKG_MIRROR_HASH:=/' feeds/packages/net/smartdns/Makefile
  sed -i -E 's/^PKG_HASH:=.*/PKG_HASH:=skip/' feeds/packages/net/smartdns/Makefile
fi

########### 4. 额外插件（幂等克隆） ###########
clone_or_pull https://github.com/gdy666/luci-app-lucky.git package/lucky
mkdir -p package/lean
pushd package/lean
clone_or_pull https://github.com/lisaac/luci-app-dockerman.git luci-app-dockerman
popd

########### 5. 系统调优 ###########
mkdir -p package/base-files/files/etc
echo 'net.netfilter.nf_conntrack_max=165535' >> package/base-files/files/etc/sysctl.conf
echo 'export PS1="\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "' >> package/base-files/files/etc/profile

########### 6. 其它可选微调（按需打开） ###########
# 6.1 关闭无用服务
# sed -i '/dnsmasq/d' include/target.mk
# 6.2 默认开启 WiFi（无无线可忽略）
# sed -i 's/disabled=1/disabled=0/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh

########### 7. 修复 Docker 编译错误 (原 Issue 14107 / PR 30288) ###########
# 动态生成补丁文件，直接阻断 binary-daemon 脚本在构建机上盲目拷贝外部二进制文件
echo "为 dockerd 注入跳过嵌套二进制拷贝的官方修复补丁..."
mkdir -p feeds/packages/utils/dockerd/patches
cat << 'EOF' > feeds/packages/utils/dockerd/patches/001-skip-copy-nested-binaries.patch
--- a/hack/make/binary-daemon
+++ b/hack/make/binary-daemon
@@ -13,7 +13,6 @@
 hash_files "$DOCKER_BUILDTAGS" "$DEST/dockerd"
 
-	echo "Copying nested executables into $DEST"
-	for file in containerd containerd-shim-runc-v2 ctr runc docker-init rootlesskit dockerd-rootless.sh dockerd-rootless-setuptool.sh; do
-		cp -f $(command -v $file) "$DEST/"
-		hash_files "$DOCKER_BUILDTAGS" "$DEST/$file"
-	done
EOF

# 重新安装所有被修改或新增的组件
./scripts/feeds install -a
