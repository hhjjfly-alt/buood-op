#!/bin/bash
#  diy-part2.sh  
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

########### 1. 最新 PassWall（删-拉-覆盖法） ###########
# 1.1 删光 lean 老包（确保官方包优先级最高）
rm -rf feeds/packages/net/{chinadns-ng,dns2socks,geoview,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,sing-box,tcping,trojan-plus,tuic-client,v2ray-core,v2ray-geodata,v2ray-plugin,xray-core,xray-plugin}
rm -rf feeds/luci/applications/luci-app-passwall

# 1.2 拉官方仓库 → package/ 目录（HEAD 即最新）
clone_or_pull https://github.com/xiaorouji/openwrt-passwall-packages.git   package/pw-packages
clone_or_pull https://github.com/xiaorouji/openwrt-passwall.git                package/pw-luci

# 1.3 二进制包全部塞进 luci 目录，用完即扔
cp -rf package/pw-packages/* package/pw-luci/
rm -rf package/pw-packages

# 1.4 强制重新下载源码（保证每次编译都是最新 commit）
rm -rf feeds/chinadns_ng/* feeds/passwall_packages/* feeds/passwall_luci/*

########### 1.5 修复 geoview 二次编译 protobuf 缓存缺失 ###########
geoview_mk="package/pw-luci/geoview/Makefile"
if [ -f "$geoview_mk" ]; then
  sed -i '/^GO_MOD_DOWNLOAD_ARGS.*GO_MOD_CACHE_DIR/d' "$geoview_mk"
  echo "=== 已修补 $geoview_mk ，geoview 不再复用残缺缓存 ==="
fi

########### 6. 编译官方最新 sing-box（主仓 + 子模块） ###########
# 6.1 删除旧包
rm -rf feeds/packages/net/sing-box package/sing-box

########### 2. 默认 IP / 主机名 / 固件名 / 系统版本 ###########
# 2.1 默认 IP
sed -i 's/192.168.1.1/10.0.0.10/g' package/base-files/files/bin/config_generate

# 2.2 固件名加日期
sed -i 's/IMG_PREFIX:=.*/IMG_PREFIX:=full-$(shell date +%Y%m%d)-$(VERSION_DIST_SANITIZED)/g' include/image.mk

# 2. 版本加日期（替换你原来的 2.3 整块）
ds_path=$(find package/ -type d -name 'default-settings*' -print -quit)
if [ -n "$ds_path" ]; then
  pushd "$ds_path/files" >/dev/null
    sed -i '/http/d' zzz-default-settings
    orig_version="$(grep DISTRIB_REVISION= zzz-default-settings | awk -F"'" '{print $2}')"
    sed -i "s/${orig_version}/${orig_version} ($(date +%Y-%m-%d))/g" zzz-default-settings
    # sed -i "s/\(DISTRIB_DESCRIPTION=.*\)'/\1 ($(date +%Y%m%d))'/" zzz-default-settings
  popd >/dev/null
else
  echo "=== default-settings 未找到，跳过版本加日期 ==="
fi

########### 3. SmartDNS 版本 bump（可选） ###########
sed -i 's/1\.2024\.45/1.2024.46/g; s/9ee27e7ba2d9789b7e007410e76c06a957f85e98/b525170bfd627607ee5ac81f97ae0f1f4f087d6b/g; /^PKG_MIRROR_HASH/s/^/#/' \
       feeds/packages/net/smartdns/Makefile

########### 4. 额外插件（幂等克隆） ###########
clone_or_pull https://github.com/gdy666/luci-app-lucky.git   package/lucky
pushd package/lean
clone_or_pull https://github.com/lisaac/luci-app-dockerman.git  luci-app-dockerman
popd

########### 5. 系统调优 ###########
# 5.1 连接数上限
mkdir -p package/base-files/files/etc
echo 'net.netfilter.nf_conntrack_max=165535' >> package/base-files/files/etc/sysctl.conf
# 5.2 默认 shell 提示符颜色（可选）
echo 'export PS1="\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "' >> package/base-files/files/etc/profile

# 1. 追加 istore 源（替换你原来的 echo 两行）
grep -q '^src-git istore' feeds.conf.default || \
  echo 'src-git istore https://github.com/linkease/istore;main' >> feeds.conf.default
./scripts/feeds update istore
./scripts/feeds install -d y -p istore luci-app-store
