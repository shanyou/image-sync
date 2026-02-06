#!/bin/bash
set -eo pipefail

source ./scripts/utils.sh

echo "=== 测试工具函数 ==="

# 测试镜像名转换
export TARGET_REGISTRY="swr.cn-north-1.myhuaweicloud.com"
result=$(convert_image_name "gcr.io/kubernetes-release/pause" "test-ns")
expected="swr.cn-north-1.myhuaweicloud.com/test-ns/gcr-io-kubernetes-release-pause"

if [ "$result" = "$expected" ]; then
    echo "✓ convert_image_name 测试通过"
else
    echo "✗ convert_image_name 测试失败"
    echo "  期望: $expected"
    echo "  实际: $result"
    exit 1
fi

# 测试 is_synced (空文件)
echo '{"lastUpdated": "", "mappings": {}}' > /tmp/test-mapping.json

if is_synced "gcr.io/test/image:1.0" "/tmp/test-mapping.json"; then
    echo "✗ is_synced 测试失败"
    exit 1
else
    echo "✓ is_synced 测试通过"
fi

rm -f /tmp/test-mapping.json

echo "=== 所有测试通过 ==="
