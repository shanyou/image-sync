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

echo "=== SWR 设置 Public 测试 ==="
echo ""

# 获取 IAM Token
echo "1. 获取 IAM Token"
token=$(get_iam_token)
echo "   ✓ Token 获取成功"
echo ""

# 测试镜像列表
images=(
    "swr.cn-north-1.myhuaweicloud.com/shanyou/docker-io-jenkins-jenkins:2-541-1-jdk21"
    "swr.cn-north-1.myhuaweicloud.com/shanyou/docker-io-kiwigrid-k8s-sidecar:2-5-0"
    "swr.cn-north-1.myhuaweicloud.com/shanyou/jenkins-inbound-agent:3355-v388858a_47b_33-9"
)

echo "2. 测试设置镜像为 public"
echo ""

for image in "${images[@]}"; do
    parsed=$(parse_target_image "$image")
    namespace=$(echo "$parsed" | cut -d'|' -f1)
    repository=$(echo "$parsed" | cut -d'|' -f2)
    
    echo "   镜像: $image"
    echo "   Namespace: $namespace"
    echo "   Repository: $repository"
    
    if set_repo_public "$namespace" "$repository" "$token" 2>&1; then
        echo "   ✓ 设置 public 成功"
    else
        echo "   ✗ 设置 public 失败"
    fi
    echo ""
done

echo "=== 测试完成 ==="
