#!/bin/bash
set -eo pipefail

source ./scripts/utils.sh

# 配置
INPUT_FILE="data/images.txt"
MAPPING_FILE="data/mapping.json"
NAMESPACE="${SWR_ORG_NAME:-shanyou}"

# 检查必需的环境变量
: "${TARGET_REGISTRY:?TARGET_REGISTRY 环境变量未设置}"
: "${REGISTRY_USERNAME:?REGISTRY_USERNAME 环境变量未设置}"
: "${REGISTRY_PASSWORD:?REGISTRY_PASSWORD 环境变量未设置}"

# 初始化 mapping.json
init_mapping() {
    if [ ! -f "$MAPPING_FILE" ]; then
        echo '{"lastUpdated": "", "mappings": {}}' > "$MAPPING_FILE"
    fi
}

# 添加映射记录
add_mapping() {
    local source="$1"
    local target="$2"
    local status="$3"

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if command -v jq &> /dev/null; then
        jq --arg src "$source" \
           --arg tgt "$target" \
           --arg time "$timestamp" \
           --arg st "$status" \
           '.lastUpdated = $time | .mappings[$src] = {
               "source": $src,
               "target": $tgt,
               "syncedAt": $time,
               "status": $st
           }' "$MAPPING_FILE" > "${MAPPING_FILE}.tmp" \
           && mv "${MAPPING_FILE}.tmp" "$MAPPING_FILE"
    fi
}

# 同步单个镜像
sync_image() {
    local source_image="$1"
    local target_image="$2"

    echo "正在同步: $source_image -> $target_image"

    if skopeo copy \
        --dest-creds "${REGISTRY_USERNAME}:${REGISTRY_PASSWORD}" \
        "docker://${source_image}" \
        "docker://${target_image}"; then
        add_mapping "$source_image" "$target_image" "success"
        echo "✓ 同步成功: $source_image"
        return 0
    else
        add_mapping "$source_image" "$target_image" "failed"
        echo "✗ 同步失败: $source_image"
        return 1
    fi
}

# 主流程
main() {
    echo "=== 开始镜像同步 ==="

    init_mapping

    # 读取并去重镜像列表
    local sync_count=0
    local skip_count=0
    local error_count=0

    while IFS= read -r image; do
        # 跳过注释和空行
        [[ "$image" =~ ^#.*$ || -z "$image" ]] && continue

        # 检查是否已同步
        if is_synced "$image" "$MAPPING_FILE"; then
            echo "⊘ 跳过已同步: $image"
            ((skip_count++))
            continue
        fi

        # 转换目标镜像名
        target_image=$(convert_image_name "$image" "$NAMESPACE")

        # 同步镜像
        if sync_image "$image" "$target_image"; then
            ((sync_count++))
        else
            ((error_count++))
        fi

    done < <(deduplicate_images "$INPUT_FILE")

    echo "=== 同步完成 ==="
    echo "成功: $sync_count, 跳过: $skip_count, 失败: $error_count"

    # 提交 mapping.json 变更
    if git diff --quiet "$MAPPING_FILE"; then
        echo "没有变更需要提交"
    else
        git add "$MAPPING_FILE"
        git commit -m "chore: 更新镜像映射记录"
        git push
    fi
}

main
