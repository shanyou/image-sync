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

# 测试 needs_sync：无 mapping 文件 → 应需要同步
if needs_sync "img" "target" "/nonexistent/file" "false"; then
    echo "✓ needs_sync (无 mapping) 测试通过"
else
    echo "✗ needs_sync (无 mapping) 失败：应需要同步"
    exit 1
fi

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

# 测试 needs_sync：status=failed → 应需要同步（重试）
echo '{"lastUpdated":"","mappings":{"foo/bar:1.0":{"source":"foo/bar:1.0","status":"failed","sourceDigest":""}}}' > /tmp/test-mapping-ns.json
if needs_sync "foo/bar:1.0" "target/foo:1.0" "/tmp/test-mapping-ns.json" "false"; then
    echo "✓ needs_sync (failed 状态) 测试通过"
else
    echo "✗ needs_sync (failed 状态) 失败：应需要同步（重试）"
    exit 1
fi
# 反向：success 且 sourceDigest 非空，mock digest 相同 → 不需同步
echo '{"lastUpdated":"","mappings":{"foo/bar:2.0":{"source":"foo/bar:2.0","status":"success","sourceDigest":"sha256:abc"}}}' > /tmp/test-mapping-ns.json
get_source_digest() { echo "sha256:abc"; }
export -f get_source_digest
if needs_sync "foo/bar:2.0" "target/foo:2.0" "/tmp/test-mapping-ns.json" "false"; then
    echo "✗ needs_sync (digest 相同) 失败：不应需要同步"
    exit 1
else
    echo "✓ needs_sync (digest 相同) 测试通过"
fi
unset -f get_source_digest
rm -f /tmp/test-mapping-ns.json

# 测试 needs_sync：digest 不同 → 应需要同步
echo '{"lastUpdated":"","mappings":{"foo/bar:d":{"source":"foo/bar:d","status":"success","sourceDigest":"sha256:old"}}}' > /tmp/test-mapping-ns.json
get_source_digest() { echo "sha256:new"; }
export -f get_source_digest
if needs_sync "foo/bar:d" "target/foo:d" "/tmp/test-mapping-ns.json" "false"; then
    echo "✓ needs_sync (digest 不同) 测试通过"
else
    echo "✗ needs_sync (digest 不同) 失败：上游变了应需要同步"
    exit 1
fi
# 反向：digest 相同 → 不应同步
get_source_digest() { echo "sha256:old"; }
export -f get_source_digest
if needs_sync "foo/bar:d" "target/foo:d" "/tmp/test-mapping-ns.json" "false"; then
    echo "✗ needs_sync (digest 相同-反向) 失败：不应需要同步"
    exit 1
else
    echo "✓ needs_sync (digest 相同-反向) 测试通过"
fi
rm -f /tmp/test-mapping-ns.json

# 测试 needs_sync：drift 检测（目标 digest 与记录不一致）
echo '{"lastUpdated":"","mappings":{"drift/img":{"source":"drift/img","status":"success","sourceDigest":"sha256:rec"}}}' > /tmp/test-mapping-ns.json
get_source_digest() { echo "sha256:rec"; }
get_target_digest() { echo "sha256:wrong"; }
export -f get_source_digest get_target_digest
if needs_sync "drift/img" "tgt/drift" "/tmp/test-mapping-ns.json" "true"; then
    echo "✓ needs_sync (drift 不一致) 测试通过"
else
    echo "✗ needs_sync (drift 不一致) 失败：目标漂移应需要同步"
    exit 1
fi
# 反向：drift 检测关闭时，仅目标不一致不触发同步
get_target_digest() { echo "sha256:wrong"; }
export -f get_target_digest
if needs_sync "drift/img" "tgt/drift" "/tmp/test-mapping-ns.json" "false"; then
    echo "✗ needs_sync (drift 关闭) 失败：关了 drift 不应因目标不一致而同步"
    exit 1
else
    echo "✓ needs_sync (drift 关闭) 测试通过"
fi
unset -f get_source_digest get_target_digest
rm -f /tmp/test-mapping-ns.json

# 测试 get_source_creds_value（取代旧的 get_source_creds_args）
export DOCKERHUB_USERNAME="testuser"
export DOCKERHUB_TOKEN="testtoken"
creds_val=$(get_source_creds_value "docker.io/library/nginx:latest")
if [ "$creds_val" = "testuser:testtoken" ]; then
    echo "✓ get_source_creds_value (docker.io + 凭据) 测试通过"
else
    echo "✗ get_source_creds_value (docker.io + 凭据) 失败: [$creds_val]"
    exit 1
fi
creds_val=$(get_source_creds_value "nginx:latest")
if [ -n "$creds_val" ]; then
    echo "✓ get_source_creds_value (裸名 + 凭据) 测试通过"
else
    echo "✗ get_source_creds_value (裸名) 失败：裸名应视为 docker.io"
    exit 1
fi
creds_val=$(get_source_creds_value "quay.io/prom/node:v1")
if [ -z "$creds_val" ]; then
    echo "✓ get_source_creds_value (非 docker.io) 测试通过"
else
    echo "✗ get_source_creds_value (非 docker.io) 失败：不应注入"
    exit 1
fi
unset DOCKERHUB_USERNAME DOCKERHUB_TOKEN
creds_val=$(get_source_creds_value "docker.io/nginx:latest")
if [ -z "$creds_val" ]; then
    echo "✓ get_source_creds_value (无凭据降级) 测试通过"
else
    echo "✗ get_source_creds_value (无凭据降级) 失败：无凭据应空"
    exit 1
fi

# 测试 cleanup_stale_mappings：清理不在输入列表中的僵尸记录
cat > /tmp/test-input.txt <<EOF
foo/bar:1.0
baz/qux:2.0
EOF
cat > /tmp/test-mapping-cleanup.json <<'EOF'
{"lastUpdated":"","mappings":{
  "foo/bar:1.0":{"source":"foo/bar:1.0","status":"success"},
  "baz/qux:2.0":{"source":"baz/qux:2.0","status":"success"},
  "zombie/old:0.1":{"source":"zombie/old:0.1","status":"failed"}
}}
EOF
cleanup_stale_mappings "/tmp/test-input.txt" "/tmp/test-mapping-cleanup.json"
remaining=$(jq '.mappings | keys | length' /tmp/test-mapping-cleanup.json)
has_zombie=$(jq '.mappings | has("zombie/old:0.1")' /tmp/test-mapping-cleanup.json)
has_foo=$(jq '.mappings | has("foo/bar:1.0")' /tmp/test-mapping-cleanup.json)
if [ "$remaining" = "2" ] && [ "$has_zombie" = "false" ] && [ "$has_foo" = "true" ]; then
    echo "✓ cleanup_stale_mappings 测试通过（僵尸删除，有效保留）"
else
    echo "✗ cleanup_stale_mappings 测试失败：剩余 $remaining 条，僵尸存在=$has_zombie"
    exit 1
fi
rm -f /tmp/test-input.txt /tmp/test-mapping-cleanup.json
echo "=== 所有测试通过 ==="
