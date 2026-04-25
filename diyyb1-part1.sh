#!/bin/bash
# diyyb1-part1.sh

add_feed() {
    local name=$1 url=$2
    if ! grep -q "^src-git $name " feeds.conf.default; then
        echo "src-git $name $url" >> feeds.conf.default
    fi
}

# 仅保留核心源，去除会导致 grep target pattern 错误的 smartdns_luci
# 回归官方源，依靠 part2 的终极 sed 脚本进行降维修复
add_feed istore 'https://github.com/linkease/istore;main'
add_feed istore_packages 'https://github.com/linkease/istore-packages;main'

# ==================== 新增：HomeProxy (下一代极简 Sing-box 前端) =================
add_feed homeproxy 'https://github.com/VIKINGYFY/homeproxy.git;main'
# ====================================================================================
