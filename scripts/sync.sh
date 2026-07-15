#!/bin/bash
# 镜像同步脚本
# 使用方法: ./sync.sh [-f|--force] [--refresh-rolling]
#   -f, --force: 强制同步所有镜像，不管是否已同步过
#   --refresh-rolling: 重同步所有 rolling tag（可变 tag，如 :latest/:alpine）
#
# 功能: 将 Docker 镜像同步到华为云 SWR，并保留原始 tag 格式

set -eo pipefail

source ./scripts/utils.sh
source ./scripts/swr-api.sh

# 配置
INPUT_FILE="data/images.txt"
MAPPING_FILE="data/mapping.json"
NAMESPACE="${SWR_ORG_NAME:-shanyou}"
FORCE_SYNC=false
REFRESH_ROLLING=false

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE_SYNC=true
            shift
            ;;
        --refresh-rolling)
            REFRESH_ROLLING=true
            shift
            ;;
        *)
            echo "未知参数: $1"
            echo "使用方法: $0 [-f|--force] [--refresh-rolling]"
            exit 1
            ;;
    esac
done

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
    local is_public="$4"
    local error_msg="${5:-}"
    local source_digest="${6:-}"

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if command -v jq &> /dev/null; then
        jq --arg src "$source" \
           --arg tgt "$target" \
           --arg time "$timestamp" \
           --arg st "$status" \
           --arg pub "$is_public" \
           --arg err "$error_msg" \
           --arg dig "$source_digest" \
           '.lastUpdated = $time | .mappings[$src] = {
               "source": $src,
               "target": $tgt,
               "syncedAt": $time,
               "status": $st,
               "is_public": $pub,
               "error_msg": $err,
               "sourceDigest": $dig
           }' "$MAPPING_FILE" > "${MAPPING_FILE}.tmp" \
           && mv "${MAPPING_FILE}.tmp" "$MAPPING_FILE"
    fi
}

# 同步单个镜像
sync_image() {
    local source_image="$1"
    local target_image="$2"

    echo "正在同步: $source_image -> $target_image"

    # 源凭据（仅 docker.io 源且配置了 DOCKERHUB_USERNAME/TOKEN 时注入，规避匿名限流）
    local -a src_creds=()
    while IFS= read -r line; do src_creds+=("$line"); done < <(get_source_creds_args "$source_image")

    if skopeo copy --all \
        "${src_creds[@]}" \
        --dest-creds "${REGISTRY_USERNAME}:${REGISTRY_PASSWORD}" \
        "docker://${source_image}" \
        "docker://${target_image}"; then

        # 取源镜像 digest 用于追溯（非致命，失败留空；带源凭据避免 docker.io 限流）
        local source_digest=""
        source_digest=$(skopeo inspect --format '{{.Digest}}' "${src_creds[@]}" "docker://${source_image}" 2>/dev/null || echo "")

        # 2. 设置为 public
        local error_msg=""
        local status="success"
        local is_public="false"

        if [ -n "${IAM_ENDPOINT:-}" ]; then
            # 解析 namespace 和 repository
            local parsed=$(parse_target_image "$target_image")
            local namespace=$(echo "$parsed" | cut -d'|' -f1)
            local repository=$(echo "$parsed" | cut -d'|' -f2)

            # 获取 Token 并设置 public
            local token
            token=$(get_iam_token 2>&1)
            if [ $? -eq 0 ]; then
                local set_public_result
                set_public_result=$(set_repo_public "$namespace" "$repository" "$token" 2>&1)
                if [ $? -eq 0 ]; then
                    is_public="true"
                else
                    error_msg="$set_public_result"
                fi
            else
                error_msg="$token"
            fi
        fi

        add_mapping "$source_image" "$target_image" "$status" "$is_public" "$error_msg" "$source_digest"
        echo "✓ 同步成功: $source_image (is_public: ${is_public})"
        return 0
    else
        add_mapping "$source_image" "$target_image" "failed" "false" "skopeo copy 失败" ""
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

        # 跳过逻辑：--force 全量重同步；否则已成功同步的跳过，
        # 除非开启 --refresh-rolling 且该镜像为 rolling tag
        if [ "$FORCE_SYNC" = true ]; then
            : # 强制同步，不跳过
        elif is_synced "$image" "$MAPPING_FILE"; then
            if [ "$REFRESH_ROLLING" = true ] && is_rolling_tag "$image"; then
                echo "↻ 刷新 rolling tag: $image"
            else
                echo "⊘ 跳过已同步: $image"
                skip_count=$((skip_count + 1))
                continue
            fi
        fi

        # 转换目标镜像名
        target_image=$(convert_image_name "$image" "$NAMESPACE")

        # 同步镜像
        if sync_image "$image" "$target_image"; then
            sync_count=$((sync_count + 1))
        else
            error_count=$((error_count + 1))
        fi

    done < <(deduplicate_images "$INPUT_FILE")

    echo "=== 同步完成 ==="
    echo "成功: $sync_count, 跳过: $skip_count, 失败: $error_count"

    # 清理僵尸记录（images.txt 已移除但 mapping.json 仍残留的条目）
    cleanup_stale_mappings "$INPUT_FILE" "$MAPPING_FILE"

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
