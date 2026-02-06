#!/bin/bash

echo "====================================="
echo "    SWR API 功能测试报告"
echo "====================================="
echo ""

# 加载环境变量
if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

source ./scripts/swr-api.sh
source ./scripts/utils.sh

# 测试计数器
PASSED=0
FAILED=0

echo "1. 环境变量配置"
echo "   TARGET_REGISTRY: ${TARGET_REGISTRY:-未设置}"
echo "   IAM_ENDPOINT: ${IAM_ENDPOINT:-未设置}"
echo "   SWR_API_ENDPOINT: ${SWR_API_ENDPOINT:-未设置}"
echo "   IAM_DOMAIN: ${IAM_DOMAIN:-未设置}"
echo ""

echo "2. 核心功能测试"

# 测试 Token 获取
echo "   - 获取 IAM Token"
if token=$(get_iam_token 2>/dev/null); then
    echo "     ✓ Token 获取成功 (长度: ${#token})"
    ((PASSED++))
else
    echo "     ✗ Token 获取失败"
    ((FAILED++))
fi

# 测试镜像名解析
echo "   - 镜像名解析"
result=$(parse_target_image "swr.cn-north-1.myhuaweicloud.com/ns/repo:tag")
if [ "$result" = "ns|repo|tag" ]; then
    echo "     ✓ 解析正确"
    ((PASSED++))
else
    echo "     ✗ 解析失败: $result"
    ((FAILED++))
fi

# 测试路径转义
echo "   - 路径转义"
repo="path/to/image"
escaped="${repo//\//\$}"
if [ "$escaped" = "path\$to\$image" ]; then
    echo "     ✓ 转义正确"
    ((PASSED++))
else
    echo "     ✗ 转义失败"
    ((FAILED++))
fi

echo ""
echo "3. API 调用测试"

# 测试设置 public
echo "   - 设置镜像为 public"
set_repo_public "shanyou" "docker-io-jenkins-jenkins" "$token" > /dev/null 2>&1
exit_code=$?

if [ $exit_code -eq 0 ]; then
    echo "     ✓ docker-io-jenkins-jenkins 设置成功"
    ((PASSED++))
else
    echo "     ✗ 设置失败 (exit code: $exit_code)"
    ((FAILED++))
fi

echo ""
echo "====================================="
echo "   测试结果: $PASSED 通过, $FAILED 失败"
echo "====================================="

if [ $FAILED -eq 0 ]; then
    echo ""
    echo "🎉 所有测试通过！"
    exit 0
else
    echo ""
    echo "⚠️  部分测试失败，请检查配置"
    exit 1
fi
