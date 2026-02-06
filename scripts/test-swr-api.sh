#!/bin/bash
set -eo pipefail

# 加载环境变量
if [ -f .env ]; then
    echo "加载环境变量..."
    set -a
    source .env
    set +a
fi

# 加载脚本
source ./scripts/swr-api.sh
source ./scripts/utils.sh

echo "=== SWR API 测试 ==="
echo ""

# 检查必要的环境变量
echo "1. 检查环境变量"
echo "   IAM_ENDPOINT: ${IAM_ENDPOINT:-未设置}"
echo "   SWR_API_ENDPOINT: ${SWR_API_ENDPOINT:-未设置}"
echo "   IAM_DOMAIN: ${IAM_DOMAIN:-未设置}"
echo "   IAM_USERNAME: ${IAM_USERNAME:+已设置 (长度: ${#IAM_USERNAME})}"
echo "   IAM_PASSWORD: ${IAM_PASSWORD:+已设置 (长度: ${#IAM_PASSWORD})}"
echo ""

# 测试 1: 获取 IAM Token
echo "2. 测试获取 IAM Token"
token=""
if token=$(get_iam_token 2>&1); then
    echo "   ✓ IAM Token 获取成功"
    echo "   Token: ${token:0:50}..."
    echo "   Token 长度: ${#token}"
else
    echo "   ✗ IAM Token 获取失败"
    echo "   错误: $token"
    exit 1
fi
echo ""

# 测试 2: 解析镜像名
echo "3. 测试解析目标镜像名"
test_image="swr.cn-north-1.myhuaweicloud.com/shanyou/test-image:latest"
parsed=$(parse_target_image "$test_image")
echo "   镜像: $test_image"
echo "   解析结果: $parsed"

namespace=$(echo "$parsed" | cut -d'|' -f1)
repository=$(echo "$parsed" | cut -d'|' -f2)
tag=$(echo "$parsed" | cut -d'|' -f3)

echo "   Namespace: $namespace"
echo "   Repository: $repository"
echo "   Tag: $tag"
echo ""

# 测试 3: 设置镜像仓库为 public
echo "4. 测试设置镜像为 public"
echo "   注意: 此测试需要一个已存在的镜像仓库"
echo "   Namespace: $namespace"
echo "   Repository: $repository"
echo ""

# 先尝试设置一个已存在的镜像为 public
# 为了测试，我们可以先尝试获取仓库信息看看是否存在
read -p "   是否继续测试 set_repo_public? (y/n): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    if set_repo_public "$namespace" "$repository" "$token" 2>&1; then
        echo "   ✓ 设置 public 成功"
    else
        echo "   ✗ 设置 public 失败 (这是正常的，如果镜像不存在的话)"
    fi
else
    echo "   跳过 set_repo_public 测试"
fi

echo ""
echo "=== 测试完成 ==="
