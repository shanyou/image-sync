#!/bin/bash

# 镜像名转换: gcr.io/xxx/yyy -> swr.cn-north-1.myhuaweicloud.com/<组织名>/gcr-io-xxx-yyy
convert_image_name() {
    local source_image="$1"
    local namespace="$2"

    # 分离镜像名和 tag
    local image_part="${source_image%%:*}"
    local tag_part="${source_image#*:}"

    # 如果没有 tag，默认使用 latest
    if [ "$image_part" = "$tag_part" ]; then
        tag_part="latest"
    fi

    # 只替换镜像名部分的 / 和 . 为 -，保留 tag 部分的原样
    local converted_image_part=$(echo "$image_part" | sed 's/[\/.]/-/g')

    echo "${TARGET_REGISTRY}/${namespace}/${converted_image_part}:${tag_part}"
}

# 检查镜像是否已同步(从 mapping.json)
is_synced() {
    local source_image="$1"
    local mapping_file="$2"

    if [ ! -f "$mapping_file" ]; then
        return 1
    fi

    # 使用 jq 检查是否存在
    if command -v jq &> /dev/null; then
        if jq -e ".mappings[\"$source_image\"]" "$mapping_file" > /dev/null 2>&1; then
            return 0
        fi
    else
        # 没有 jq 时使用 grep 简单检查
        if grep -q "\"$source_image\"" "$mapping_file"; then
            return 0
        fi
    fi

    return 1
}

# 镜像去重
deduplicate_images() {
    local input_file="$1"
    sort -u "$input_file" | grep -v '^#' | grep -v '^$'
}

# 解析目标镜像名，提取 namespace 和 repository
# 输入: swr.cn-north-1.myhuaweicloud.com/shanyou/image-name:tag
# 输出: namespace|repository|tag
parse_target_image() {
    local target_image="$1"

    # 移除 registry 部分
    local without_registry="${target_image#*/}"

    # 分离 namespace 和 repository:tag
    local namespace="${without_registry%%/*}"
    local repo_with_tag="${without_registry#*/}"

    # 分离 repository 和 tag
    local repository="${repo_with_tag%:*}"
    local tag="${repo_with_tag##*:}"

    echo "${namespace}|${repository}|${tag}"
}
