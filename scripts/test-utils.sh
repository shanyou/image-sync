#!/bin/bash
set -eo pipefail

source ./scripts/utils.sh

echo "=== 测试工具函数 ==="

# 测试镜像名转换
export TARGET_REGISTRY="swr.cn-north-1.myhuaweicloud.com"
result=$(convert_image_name "gcr.io/kubernetes-release/pause" "test-ns")
expected="swr.cn-north-1.myhuaweicloud.com/test-ns/gcr-io-kubernetes-release-pause:latest"

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

# 测试 parse_target_image
result=$(parse_target_image "swr.cn-north-1.myhuaweicloud.com/shanyou/gcr-io-kubernetes-release-pause:3.9")
expected="shanyou|gcr-io-kubernetes-release-pause|3.9"

if [ "$result" = "$expected" ]; then
    echo "✓ parse_target_image 测试通过"
else
    echo "✗ parse_target_image 测试失败"
    echo "  期望: $expected"
    echo "  实际: $result"
    exit 1
fi

# 测试带多层路径的镜像名
result=$(parse_target_image "swr.cn-north-1.myhuaweicloud.com/namespace/foo/bar:latest")
expected="namespace|foo/bar|latest"

if [ "$result" = "$expected" ]; then
    echo "✓ parse_target_image (多层路径) 测试通过"
else
    echo "✗ parse_target_image (多层路径) 测试失败"
    echo "  期望: $expected"
    echo "  实际: $result"
    exit 1
fi

# 测试 convert_image_name 处理 digest（目标不应带 digest）
result=$(convert_image_name "docker.io/busybox:stable@sha256:3fbc632167424a6d997e74f52b878d7cc478225cffac6bc977eedfe51c7f4e79" "test-ns")
expected="swr.cn-north-1.myhuaweicloud.com/test-ns/docker-io-busybox:stable"
if [ "$result" = "$expected" ]; then
    echo "✓ convert_image_name (digest) 测试通过"
else
    echo "✗ convert_image_name (digest) 测试失败"
    echo "  期望: $expected"
    echo "  实际: $result"
    exit 1
fi

# 测试 is_synced：status=failed 不应视为已同步（可重试）
echo '{"lastUpdated":"","mappings":{"foo/bar:1.0":{"source":"foo/bar:1.0","status":"failed"}}}' > /tmp/test-mapping.json
if is_synced "foo/bar:1.0" "/tmp/test-mapping.json"; then
    echo "✗ is_synced (failed status) 测试失败：失败的镜像不应被跳过"
    exit 1
else
    echo "✓ is_synced (failed status) 测试通过"
fi
# 反向：status=success 应视为已同步
echo '{"lastUpdated":"","mappings":{"foo/bar:2.0":{"source":"foo/bar:2.0","status":"success"}}}' > /tmp/test-mapping.json
if is_synced "foo/bar:2.0" "/tmp/test-mapping.json"; then
    echo "✓ is_synced (success status) 测试通过"
else
    echo "✗ is_synced (success status) 测试失败"
    exit 1
fi
rm -f /tmp/test-mapping.json

# 测试 is_rolling_tag
roll_cases=(
    "nginx:latest|0"
    "redis:8-alpine|1"
    "bitnami/postgresql|0"
    "minio/minio:RELEASE.2023-03-20T20-16-18Z|1"
    "docker.io/busybox:stable|0"
    "golang:1.26.1|1"
)
for case in "${roll_cases[@]}"; do
    IFS='|' read -r img expected <<< "$case"
    actual=0
    is_rolling_tag "$img" || actual=$?
    if [ "$actual" = "$expected" ]; then
        echo "✓ is_rolling_tag ($img) 测试通过"
    else
        echo "✗ is_rolling_tag ($img) 测试失败：期望 $expected，实际 $actual"
        exit 1
    fi
done
echo "=== 所有测试通过 ==="
