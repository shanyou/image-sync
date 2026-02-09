#!/bin/bash
# 镜像同步脚本
# 使用方法: ./sync.sh [-f|--force]
#   -f, --force: 强制同步所有镜像，不管是否已同步过
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

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE_SYNC=true
            shift
            ;;
        *)
            echo "未知参数: $1"
            echo "使用方法: $0 [-f|--force]"
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

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if command -v jq &> /dev/null; then
        jq --arg src "$source" \
           --arg tgt "$target" \
           --arg time "$timestamp" \
           --arg st "$status" \
           --arg pub "$is_public" \
           --arg err "$error_msg" \
           '.lastUpdated = $time | .mappings[$src] = {
               "source": $src,
               "target": $tgt,
               "syncedAt": $time,
               "status": $st,
               "is_public": $pub,
               "error_msg": $err
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

        add_mapping "$source_image" "$target_image" "$status" "$is_public" "$error_msg"
        echo "✓ 同步成功: $source_image (is_public: ${is_public})"
        return 0
    else
        add_mapping "$source_image" "$target_image" "failed" "false" "skopeo copy 失败"
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

        # 检查是否已同步，除非使用 --force 选项
        if [ "$FORCE_SYNC" = false ] && is_synced "$image" "$MAPPING_FILE"; then
            echo "⊘ 跳过已同步: $image"
            skip_count=$((skip_count + 1))
            continue
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
