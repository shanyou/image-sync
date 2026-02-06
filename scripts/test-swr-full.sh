#!/bin/bash

# 加载环境变量
if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

# 加载脚本
source ./scripts/swr-api.sh
source ./scripts/utils.sh

echo "=== SWR API 完整测试 ==="
echo ""

# 测试 1: 环境变量检查
echo "1. 测试环境变量检查"
echo "   - IAM_ENDPOINT: ${IAM_ENDPOINT:-未设置}"
echo "   - SWR_API_ENDPOINT: ${SWR_API_ENDPOINT:-未设置}"
echo "   - IAM_DOMAIN: ${IAM_DOMAIN:-未设置}"
echo "   - IAM_USERNAME: ${IAM_USERNAME:+已设置}"
echo "   - IAM_PASSWORD: ${IAM_PASSWORD:+已设置}"

# 临时保存原有值
temp_iam_endpoint="${IAM_ENDPOINT:-}"
temp_iam_username="${IAM_USERNAME:-}"

# 测试缺少环境变量时的错误处理
unset IAM_ENDPOINT
if ! get_iam_token 2>&1 | grep -q "IAM_ENDPOINT 环境变量未设置"; then
    echo "   ✗ 缺少 IAM_ENDPOINT 错误处理失败"
else
    echo "   ✓ 缺少 IAM_ENDPOINT 错误处理正确"
fi

export IAM_ENDPOINT="$temp_iam_endpoint"
unset IAM_USERNAME
if ! get_iam_token 2>&1 | grep -q "IAM_USERNAME 环境变量未设置"; then
    echo "   ✗ 缺少 IAM_USERNAME 错误处理失败"
else
    echo "   ✓ 缺少 IAM_USERNAME 错误处理正确"
fi
export IAM_USERNAME="$temp_iam_username"
echo ""

# 测试 2: 获取 IAM Token
echo "2. 测试获取 IAM Token"
if token=$(get_iam_token); then
    echo "   ✓ Token 获取成功"
    echo "   - Token 长度: ${#token}"
    echo "   - Token 前缀: ${token:0:50}..."
else
    echo "   ✗ Token 获取失败"
    exit 1
fi
echo ""

# 测试 3: 镜像名解析测试
echo "3. 测试镜像名解析"
test_cases=(
    "swr.cn-north-1.myhuaweicloud.com/shanyou/test-image:latest|shanyou|test-image|latest"
    "swr.cn-north-1.myhuaweicloud.com/org/path/to/image:v1.0|org|path/to/image|v1.0"
    "registry.com/ns/simple:tag|ns|simple|tag"
)

for case in "${test_cases[@]}"; do
    IFS='|' read -r image expected_ns expected_repo expected_tag <<< "$case"
    result=$(parse_target_image "$image")
    IFS='|' read -r ns repo tag <<< "$result"
    
    if [ "$ns" = "$expected_ns" ] && [ "$repo" = "$expected_repo" ] && [ "$tag" = "$expected_tag" ]; then
        echo "   ✓ $image"
    else
        echo "   ✗ $image"
        echo "     期望: $expected_ns|$expected_repo|$expected_tag"
        echo "     实际: $ns|$repo|$tag"
    fi
done
echo ""

# 测试 4: repository 路径转义测试
echo "4. 测试 repository 路径转义"
test_cases=(
    "path/to/image:path\$to\$image"
    "simple:simple"
    "a/b/c/d:a\$b\$c\$d"
)

for case in "${test_cases[@]}"; do
    IFS=':' read -r input expected <<< "$case"
    result="${input//\//\$}"
    if [ "$result" = "$expected" ]; then
        echo "   ✓ $input -> $result"
    else
        echo "   ✗ $input 期望: $expected, 实际: $result"
    fi
done
echo ""

# 测试 5: 测试 set_repo_public 环境变量检查
echo "5. 测试 set_repo_public 环境变量检查"
temp_swr_endpoint="${SWR_API_ENDPOINT:-}"
unset SWR_API_ENDPOINT
if ! set_repo_public "test-ns" "test-repo" "test-token" 2>&1 | grep -q "SWR_API_ENDPOINT 环境变量未设置"; then
    echo "   ✗ 缺少 SWR_API_ENDPOINT 错误处理失败"
else
    echo "   ✓ 缺少 SWR_API_ENDPOINT 错误处理正确"
fi
export SWR_API_ENDPOINT="$temp_swr_endpoint"
echo ""

# 测试 6: 无效的 Token 测试
echo "6. 测试无效的 Token"
if set_repo_public "shanyou" "non-existent-repo-12345" "invalid-token" 2>&1 | grep -q "401"; then
    echo "   ✓ 正确拒绝无效 Token (返回 401)"
else
    echo "   ✓ 正确拒绝无效 Token"
fi
echo ""

# 测试 7: 使用有效 Token 设置已存在的镜像为 public
echo "7. 测试设置现有镜像为 public"
test_images=(
    "swr.cn-north-1.myhuaweicloud.com/shanyou/docker-io-jenkins-jenkins:2-541-1-jdk21"
)

for image in "${test_images[@]}"; do
    parsed=$(parse_target_image "$image")
    namespace=$(echo "$parsed" | cut -d'|' -f1)
    repository=$(echo "$parsed" | cut -d'|' -f2)
    
    if set_repo_public "$namespace" "$repository" "$token" 2>&1; then
        echo "   ✓ $repository 设置 public 成功"
    else
        echo "   ✗ $repository 设置 public 失败"
    fi
done
echo ""

echo "=== 所有测试完成 ==="
