#!/bin/bash
#  diy-part2.sh  （After Update feeds）
#  功能清单：
#  1. 万能克隆/更新函数
#  2. Go 模块预拉（防止编译时残缺）
#  3. 最新 PassWall（删-拉-覆盖法）
#  4. 默认 IP / 固件名 / 系统版本加日期
#  5. SmartDNS 版本 bump
#  6. 额外插件（lucky & dockerman）幂等
#  7. 系统调优

########### 万能函数：克隆或拉取最新 ###########
clone_or_pull() {
  local repo=$1 dir=$2
  if [[ -d "$dir/.git" ]]; then
    git -C "$dir" fetch --depth 1
    git -C "$dir" reset --hard origin/HEAD
  else
    git clone --depth 1 "$repo" "$dir"
  fi
}

########### 0. 预拉 Go 模块（防止编译时残缺） ###########
OWRT="$HOME/openwrt-build/openwrt"
export GOPROXY=https://goproxy.cn,direct
prefetch_sing_box_deps() {
  local tmp=$(mktemp -d)
  git clone --depth 1 https://github.com/sagernet/sing-box.git "$tmp"
  cd "$tmp"
  go mod download -x
  rsync -a "$HOME/go/pkg/mod/" "$OWRT/dl/go-mod-cache/"
  cd "$OWRT"
  rm -rf "$tmp"
}
prefetch_sing_box_deps

########### 1. 最新 PassWall（删-拉-覆盖法） ###########
# 1.1 删光 lean 老包（确保官方包优先级最高）
rm -rf feeds/packages/net/{chinadns-ng,dns2socks,geoview,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,sing-box,tcping,trojan-plus,tuic-client,v2ray-core,v2ray-geodata,v2ray-plugin,xray-core,xray-plugin}
rm -rf feeds/luci/applications/luci-app-passwall

# 1.2 拉官方仓库 → package/ 目录（HEAD 即最新）
clone_or_pull https://github.com/xiaorouji/openwrt-passwall-packages.git  package/pw-packages
clone_or_pull https://github.com/xiaorouji/openwrt-passwall.git               package/pw-luci

# 1.3 二进制包全部塞进 luci 目录，用完即扔
cp -rf package/pw-packages/* package/pw-luci/
rm -rf package/pw-packages

# 1.4 强制重新下载源码（保证每次编译都是最新 commit）
rm -rf feeds/chinadns_ng/* feeds/passwall_packages/* feeds/passwall_luci/*

########### 2. 默认 IP / 固件名 / 系统版本 ###########
# 2.1 默认 IP
sed -i 's/192.168.1.1/10.0.0.10/g' package/base-files/files/bin/config_generate
# 2.2 固件名加日期
sed -i 's/IMG_PREFIX:=.*/IMG_PREFIX:=full-$(shell date +%Y%m%d)-$(VERSION_DIST_SANITIZED)/g' include/image.mk
# 2.3 系统版本加日期
pushd package/lean/default-settings/files
sed -i '/http/d' zzz-default-settings
orig_version="$(grep DISTRIB_REVISION zzz-default-settings | awk -F"'" '{print $2}')"
sed -i "s/${orig_version}/${orig_version} ($(date +%Y-%m-%d))/g" zzz-default-settings
popd

########### 3. SmartDNS 版本 bump（可选） ###########
sed -i 's/1\.2024\.45/1.2024.46/g; s/9ee27e7ba2d9789b7e007410e76c06a957f85e98/b525170bfd627607ee5ac81f97ae0f1f4f087d6b/g; /^PKG_MIRROR_HASH/s/^/#/' \
       feeds/packages/net/smartdns/Makefile

########### 4. 额外插件（幂等克隆） ###########
clone_or_pull https://github.com/gdy666/luci-app-lucky.git  package/lucky
pushd package/lean
clone_or_pull https://github.com/lisaac/luci-app-dockerman.git luci-app-dockerman
popd

########### 5. 系统调优 ###########
# 连接数上限
mkdir -p package/base-files/files/etc
echo 'net.netfilter.nf_conntrack_max=165535' >> package/base-files/files/etc/sysctl.conf
# 可选：彩色提示符
echo 'export PS1="\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "' >> package/base-files/files/etc/profile
