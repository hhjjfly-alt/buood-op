#!/bin/bash
# diy-part2.sh  （After Update feeds）
# 针对 coolsnowwolf/lede 最终加固版
# 保留原功能 + 严格错误控制 + 幂等 + Docker 安全修复（无 fragile patch / 无 Compile 注入）

set -eo pipefail

########### 万能函数：克隆或拉取最新 ###########
clone_or_pull() {
  local repo="$1"
  local dir="$2"
  local branch="${3:-}"

  if [[ -d "$dir/.git" ]]; then
    echo ">>> Update $dir ..."
    git -C "$dir" remote set-url origin "$repo" 2>/dev/null || true
    if [[ -n "$branch" ]]; then
      git -C "$dir" fetch --depth 1 origin "$branch"
      git -C "$dir" checkout -B "$branch" "origin/$branch" 2>/dev/null || \
        git -C "$dir" reset --hard "origin/$branch"
    else
      git -C "$dir" fetch --depth 1 origin
      local target
      target=$(git -C "$dir" symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@') || true
      if [[ -n "$target" ]]; then
        git -C "$dir" reset --hard "origin/$target"
      else
        git -C "$dir" reset --hard FETCH_HEAD
      fi
    fi
  else
    echo ">>> Clone $repo -> $dir ..."
    if [[ -n "$branch" ]]; then
      git clone --depth 1 -b "$branch" "$repo" "$dir"
    else
      git clone --depth 1 "$repo" "$dir"
    fi
  fi
}

# 幂等追加一行（已存在则跳过）
append_if_missing() {
  local line="$1"
  local file="$2"
  mkdir -p "$(dirname "$file")"
  grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}

########### 0. istore（避免重复添加） ###########
if ! grep -qE '^src-git[[:space:]]+istore[[:space:]]' feeds.conf.default 2>/dev/null; then
  echo 'src-git istore https://github.com/linkease/istore;main' >> feeds.conf.default
  ./scripts/feeds update istore
  ./scripts/feeds install -d y -p istore luci-app-store
fi

########### 1. 最新 PassWall（官方独立分仓规范） ###########
# 1.1 清理 feeds 自带冲突包
rm -rf feeds/packages/net/{chinadns-ng,dns2socks,geoview,hysteria,ipt2socks,microsocks,naiveproxy,shadow-tls,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,sing-box,tcping,trojan-plus,tuic-client,v2ray-core,v2ray-geodata,v2ray-plugin,xray-core,xray-plugin}
rm -rf feeds/luci/applications/luci-app-passwall

# 1.2 独立克隆（切勿合并覆盖）
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git package/passwall-packages
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall.git package/passwall-luci

########### 2. 默认 IP / 固件名 / 系统版本（lede） ###########
# 2.1 默认 IP
if [[ -f package/base-files/files/bin/config_generate ]]; then
  sed -i 's/192\.168\.1\.1/10.0.0.10/g' package/base-files/files/bin/config_generate
fi

# 2.2 固件名加日期
if [[ -f include/image.mk ]]; then
  sed -i 's/IMG_PREFIX:=.*/IMG_PREFIX:=full-$(shell date +%Y%m%d)-$(VERSION_DIST_SANITIZED)/g' include/image.mk
fi

# 2.3 系统版本加日期（lede default-settings）
if [[ -f package/lean/default-settings/files/zzz-default-settings ]]; then
  pushd package/lean/default-settings/files >/dev/null
  sed -i '/http/d' zzz-default-settings 2>/dev/null || true
  if grep -q "DISTRIB_REVISION=" zzz-default-settings; then
    orig_version="$(grep "DISTRIB_REVISION=" zzz-default-settings | awk -F"'" '{print $2}')"
    if [[ -n "$orig_version" ]] && ! echo "$orig_version" | grep -qE '\([0-9]{4}-[0-9]{2}-[0-9]{2}\)'; then
      sed -i "s/${orig_version}/${orig_version} ($(date +%Y-%m-%d))/g" zzz-default-settings
    fi
  fi
  popd >/dev/null
fi

########### 3. SmartDNS 版本 Bump ###########
# 强制版本 + skip hash（与原意图一致）。若 feeds 已足够新可整段注释。
SMARTDNS_MK="feeds/packages/net/smartdns/Makefile"
if [[ -f "$SMARTDNS_MK" ]]; then
  echo ">>> Bumping SmartDNS (hash check skipped)"
  sed -i -E 's/^PKG_VERSION:=.*/PKG_VERSION:=1.2025.47/' "$SMARTDNS_MK"
  sed -i -E 's/^PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=0f1912ab020ea9a60efac4732442f0bb7093f40b/' "$SMARTDNS_MK"
  sed -i -E 's/^PKG_MIRROR_HASH:=.*/# &/' "$SMARTDNS_MK"
  sed -i -E 's/^PKG_HASH:=.*/PKG_HASH:=skip/' "$SMARTDNS_MK"
fi

########### 4. 额外插件（幂等） ###########
clone_or_pull https://github.com/gdy666/luci-app-lucky.git package/lucky
mkdir -p package/lean
clone_or_pull https://github.com/lisaac/luci-app-dockerman.git package/lean/luci-app-dockerman

########### 5. 系统调优（幂等） ###########
mkdir -p package/base-files/files/etc
append_if_missing 'net.netfilter.nf_conntrack_max=165535' package/base-files/files/etc/sysctl.conf

PROFILE="package/base-files/files/etc/profile"
mkdir -p "$(dirname "$PROFILE")"
if ! grep -q 'PS1=.*\\u@\\h' "$PROFILE" 2>/dev/null; then
  echo 'export PS1="\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "' >> "$PROFILE"
fi

########### 6. 修复 dockerd 编译错误（lede Issue #14107） ###########
# 原因：Docker 29.x binary-daemon 在交叉编译环境中 command -v 为空，
#       cp 收到空参数直接失败。
# 策略：不写 fragile unified diff，不往 Compile 中间插行；
#       在 Build/Prepare 后对已解压源码做幂等 sed，最稳。

DOCKERD_MK=""
for candidate in \
  feeds/packages/utils/dockerd/Makefile \
  package/feeds/packages/utils/dockerd/Makefile
do
  [[ -f "$candidate" ]] && DOCKERD_MK="$candidate" && break
done

if [[ -n "$DOCKERD_MK" ]]; then
  if ! grep -q 'DIY_DOCKERD_SKIP_NESTED_COPY' "$DOCKERD_MK" 2>/dev/null; then
    echo ">>> 向 dockerd Makefile 注入 Prepare 阶段源码修复..."

    if grep -q 'define Build/Prepare' "$DOCKERD_MK"; then
      # 在第一个 Build/Prepare 的 endef 前插入，强制输出真实 Tab，避免 missing separator
      awk '
        /define Build\/Prepare/ { in_prep=1 }
        in_prep && /^endef/ && !done {
          print "\t# DIY_DOCKERD_SKIP_NESTED_COPY"
          print "\tsed -i \"/Copying nested executables/,+12d\" $(PKG_BUILD_DIR)/hack/make/binary-daemon 2>/dev/null || true"
          done=1
        }
        { print }
      ' "$DOCKERD_MK" > "${DOCKERD_MK}.tmp" && mv "${DOCKERD_MK}.tmp" "$DOCKERD_MK"
    else
      # 极少数 Makefile 无标准 Prepare：追加自定义 Prepare
      cat >> "$DOCKERD_MK" << 'MAKEEOF'

define Build/Prepare
	$(call Build/Prepare/Default)
	# DIY_DOCKERD_SKIP_NESTED_COPY
	sed -i "/Copying nested executables/,+12d" $(PKG_BUILD_DIR)/hack/make/binary-daemon 2>/dev/null || true
endef
MAKEEOF
    fi
  fi
  echo ">>> dockerd 修复已就绪（Prepare 阶段源码 sed，无外部 patch）"
else
  echo ">>> 未找到 dockerd Makefile，跳过 Docker 修复"
fi

########### 7. 重新安装组件 ###########
./scripts/feeds install -a 2>/dev/null || true

echo ">>> diy-part2.sh（lede 最终加固版）执行完成"
