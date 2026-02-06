#!/bin/bash

# 镜像名转换: gcr.io/xxx/yyy -> swr.cn-north-1.myhuaweicloud.com/<组织名>/gcr-io-xxx-yyy
convert_image_name() {
    local source_image="$1"
    local namespace="$2"

    # 替换 / 和 . 为 -
    local converted_name=$(echo "$source_image" | sed 's/[\/.]/-/g')

    echo "${TARGET_REGISTRY}/${namespace}/${converted_name}"
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
