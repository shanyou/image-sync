#!/bin/bash

# 镜像名转换: gcr.io/xxx/yyy -> swr.cn-north-1.myhuaweicloud.com/<组织名>/gcr-io-xxx-yyy
convert_image_name() {
    local source_image="$1"
    local namespace="$2"

    # 去掉 digest 部分（@sha256:...），digest 是源镜像特定的，不带 到目标
    local ref="${source_image%%@*}"

    # 分离镜像名和 tag
    local image_part="${ref%%:*}"
    local tag_part="${ref#*:}"

    # 如果没有 tag，默认使用 latest
    if [ "$image_part" = "$tag_part" ]; then
        tag_part="latest"
    fi

    # 只替换镜像名部分的 / 和 . 为 -，保留 tag 部分的原样
    local converted_image_part=$(echo "$image_part" | sed 's/[\/.]/-/g')

    echo "${TARGET_REGISTRY}/${namespace}/${converted_image_part}:${tag_part}"
}

# 返回源镜像的凭据值（user:pass），仅 docker.io 源且配置了凭据时返回
# 用于 skopeo inspect --creds / skopeo copy --src-creds
get_source_creds_value() {
    local source_image="$1"
    local registry="${source_image%%/*}"
    # docker.io 引用形式: "nginx:tag"（裸名）/ "docker.io/..." / "library/..."
    if [ "$registry" = "$source_image" ] || [ "$registry" = "docker.io" ] || [ "$registry" = "library" ]; then
        if [ -n "${DOCKERHUB_USERNAME:-}" ] && [ -n "${DOCKERHUB_TOKEN:-}" ]; then
            echo "${DOCKERHUB_USERNAME}:${DOCKERHUB_TOKEN}"
        fi
    fi
}

# 取源镜像的 manifest digest（带源凭据规避 docker.io 限流）
# 失败返回空字符串
get_source_digest() {
    local source_image="$1"
    local creds; creds=$(get_source_creds_value "$source_image")
    if [ -n "$creds" ]; then
        skopeo inspect --format '{{.Digest}}' --creds "$creds" "docker://${source_image}" 2>/dev/null
    else
        skopeo inspect --format '{{.Digest}}' "docker://${source_image}" 2>/dev/null
    fi
}

# 取目标镜像的 manifest digest（带 SWR 目标凭据）
# 失败返回空字符串
get_target_digest() {
    local target_image="$1"
    skopeo inspect --format '{{.Digest}}' \
        --creds "${REGISTRY_USERNAME}:${REGISTRY_PASSWORD}" \
        "docker://${target_image}" 2>/dev/null
}

# 判定是否需要同步（基于 manifest digest 比对）
# 返回: 0 = 需要同步, 1 = 不需要（已是最新）
# 参数: source_image target_image mapping_file [check_drift]
needs_sync() {
    local source_image="$1"
    local target_image="$2"
    local mapping_file="$3"
    local check_drift="${4:-false}"

    # 无 mapping 文件或无 jq → 无法判断，默认需要同步
    if [ ! -f "$mapping_file" ] || ! command -v jq &> /dev/null; then
        return 0
    fi

    local recorded_status recorded_digest
    recorded_status=$(jq -r --arg k "$source_image" '.mappings[$k].status // ""' "$mapping_file" 2>/dev/null)
    recorded_digest=$(jq -r --arg k "$source_image" '.mappings[$k].sourceDigest // ""' "$mapping_file" 2>/dev/null)

    # 失败记录或无记录 → 需要同步（重试失败 / 新镜像）
    if [ "$recorded_status" != "success" ]; then
        return 0
    fi

    # 记录的 digest 为空（旧记录或曾取 digest 失败）→ 需要同步
    if [ -z "$recorded_digest" ]; then
        return 0
    fi

    # 比对源 digest：上游变了 → 需要同步
    local src_digest; src_digest=$(get_source_digest "$source_image")
    if [ -z "$src_digest" ]; then
        return 0  # 取不到源 digest（网络问题等）→ 尝试同步
    fi
    if [ "$src_digest" != "$recorded_digest" ]; then
        return 0
    fi

    # drift 检测：SWR 端实际内容与记录不一致（被删/被改）→ 需要同步
    if [ "$check_drift" = true ]; then
        local dst_digest; dst_digest=$(get_target_digest "$target_image")
        if [ "$dst_digest" != "$recorded_digest" ]; then
            return 0
        fi
    fi

    return 1  # 源（及目标）digest 均与记录一致，不需要同步
}

# 镜像去重
deduplicate_images() {
    local input_file="$1"
    sort -u "$input_file" | grep -v '^#' | grep -v '^$'
}

# 清理僵尸映射记录：删除 mapping.json 中不在输入列表里的镜像条目
# 镜像从 images.txt 移除后，mapping.json 的对应记录成为僵尸（永久显示失败、虚高统计）
# 用法: cleanup_stale_mappings "$INPUT_FILE" "$MAPPING_FILE"
cleanup_stale_mappings() {
    local input_file="$1"
    local mapping_file="$2"

    if ! command -v jq &> /dev/null; then
        return 0  # 无 jq 时跳过（降级，不清理）
    fi

    if [ ! -f "$mapping_file" ] || [ ! -f "$input_file" ]; then
        return 0
    fi

    # 构造有效镜像名 JSON 数组（经去重去注释处理）
    local valid_json
    valid_json=$(deduplicate_images "$input_file" | jq -R . | jq -s .)

    # 保留 key 在有效列表中的条目，删除僵尸记录
    jq --argjson valid "$valid_json" \
       '.mappings |= with_entries(select(.key as $k | $valid | index($k)))' \
       "$mapping_file" > "${mapping_file}.tmp" \
       && mv "${mapping_file}.tmp" "$mapping_file"
}

# 解析目标镜像名，提取 namespace 和 repository
# 输入: swr.cn-north-1.myhuaweicloud.com/shanyou/image-name:tag
# 输出: namespace|repository|tag
parse_target_image() {
    local target_image="$1"

    # 防御性去掉 digest
    local ref="${target_image%%@*}"

    # 移除 registry 部分
    local without_registry="${ref#*/}"

    # 分离 namespace 和 repository:tag
    local namespace="${without_registry%%/*}"
    local repo_with_tag="${without_registry#*/}"

    # 分离 repository 和 tag
    local repository="${repo_with_tag%:*}"
    local tag="${repo_with_tag##*:}"

    echo "${namespace}|${repository}|${tag}"
}
