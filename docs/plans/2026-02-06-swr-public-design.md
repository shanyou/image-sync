# 华为云 SWR 镜像设置为 Public 设计

## 概述

在镜像同步到华为云 SWR 后，自动调用 SWR API 将镜像仓库设置为 public。如果设置失败，在 mapping.json 中标记为 private 状态，但不影响整体同步流程。

## 环境

- **目标**: 所有同步到华为云的镜像都自动设置为 public
- **失败处理**: 非致命错误，即使设置 public 失败也不影响整体同步成功
- **记录**: 在 mapping.json 中标注是 public 或 private 仓库，并记录错误原因

## 架构设计

### 目录结构

```
scripts/
├── sync.sh          # 主同步脚本
├── utils.sh         # 工具函数
├── swr-api.sh       # 新增：华为云 IAM 和 SWR API 调用封装
└── test-utils.sh    # 单元测试

data/
├── images.txt       # 镜像列表
└── mapping.json     # 映射记录
```

### 环境变量

| 变量 | 用途 | 新增 |
|------|------|------|
| `IAM_ENDPOINT` | IAM 端点（iam.myhuaweicloud.com） | 是 |
| `SWR_API_ENDPOINT` | SWR API 端点（swr-api.cn-north-1.myhuaweicloud.com） | 是 |
| `IAM_USERNAME` | IAM 用户名 | 是 |
| `IAM_PASSWORD` | IAM 用户密码 | 是 |
| `IAM_DOMAIN` | IAM 用户所属账号名 | 是 |
| `TARGET_REGISTRY` | Docker 镜像仓库地址 | 已有 |
| `REGISTRY_USERNAME` | Docker 登录用户名 | 已有 |
| `REGISTRY_PASSWORD` | Docker 登录密码 | 已有 |
| `SWR_ORG_NAME` | SWR 组织/命名空间 | 已有 |

## 认证方式

### IAM Token 获取

调用 IAM API 获取 X-Auth-Token：

- **方法**: `POST`
- **路径**: `/v3/auth/tokens`
- **端点**: `https://iam.myhuaweicloud.com/v3/auth/tokens`

请求体：
```json
{
    "auth": {
        "identity": {
            "methods": ["password"],
            "password": {
                "user": {
                    "domain": {"name": "IAMDomain"},
                    "name": "IAMUser",
                    "password": "IAMPassword"
                }
            }
        },
        "scope": {
            "project": {
                "name": "cn-north-1"
            }
        }
    }
}
```

从响应头 `X-Subject-Token` 获取 Token，有效期 24 小时。

### UpdateRepo API

调用 SWR API 设置镜像为 public：

- **方法**: `PATCH`
- **路径**: `/v2/manage/namespaces/{namespace}/repos/{repository}`
- **端点**: `https://swr-api.cn-north-1.myhuaweicloud.com`
- **认证**: 使用 IAM Token (X-Auth-Token header)
- **请求体**: `{"is_public": true}`

注意：repository 参数中如果有 `/` 需要替换为 `$`

## 数据流程

```
开始同步镜像
    │
    ▼
skopeo copy (使用 REGISTRY_USERNAME/PASSWORD)
    │
    ├─ 成功 ──────────────────────┐
    │                              │
    ▼                              ▼
解析目标镜像名               记录失败到 mapping.json
(namespace, repository)        (status: failed)
    │
    ▼
获取 IAM Token
(使用 IAM_USERNAME/PASSWORD)
    │
    ├─ 成功 ──────────────────────┐
    │                              │
    ▼                              ▼
调用 UpdateRepo API     记录 success:private 到 mapping.json
(is_public: true)        (Token 获取失败)
    │
    ├─ 成功 ──────────────────────┐
    │                              │
    ▼                              ▼
记录 success:public    记录 success:private 到 mapping.json
到 mapping.json          (API 调用失败)
```

## mapping.json 数据结构

```json
{
  "lastUpdated": "2026-02-06T10:30:00Z",
  "mappings": {
    "gcr.io/kubernetes-release/pause:3.9": {
      "source": "gcr.io/kubernetes-release/pause:3.9",
      "target": "swr.cn-north-1.myhuaweicloud.com/shanyou/gcr-io-kubernetes-release-pause:3.9",
      "syncedAt": "2026-02-06T10:25:00Z",
      "status": "success",
      "is_public": "true",
      "error_msg": ""
    },
    "ghcr.io/prometheus/prometheus:v2.45.0": {
      "source": "ghcr.io/prometheus/prometheus:v2.45.0",
      "target": "swr.cn-north-1.myhuaweicloud.com/shanyou/ghcr-io-prometheus-prometheus:v2.45.0",
      "syncedAt": "2026-02-06T10:26:00Z",
      "status": "success",
      "is_public": "false",
      "error_msg": "设置 public 失败: API 返回 401 Unauthorized"
    },
    "gcr.io/failed/image:1.0": {
      "source": "gcr.io/failed/image:1.0",
      "target": "swr.cn-north-1.myhuaweicloud.com/shanyou/gcr-io-failed-image:1.0",
      "syncedAt": "2026-02-06T10:27:00Z",
      "status": "failed",
      "is_public": "false",
      "error_msg": "skopeo copy 失败: manifest unknown"
    }
  }
}
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `status` | string | 同步状态: `success` 或 `failed` |
| `is_public` | string | 是否公开: `"true"` 或 `"false"` |
| `error_msg` | string | 错误信息，成功时为空字符串 |

### 错误信息记录策略

| 场景 | status | is_public | error_msg |
|------|--------|-----------|-----------|
| 同步成功，public 成功 | `success` | `"true"` | `""` |
| 同步成功，public 失败 | `success` | `"false"` | `"设置 public 失败: <具体原因>"` |
| 同步失败 | `failed` | `"false"` | `"同步失败: <具体原因>"` |
| Token 获取失败 | `success` | `"false"` | `"获取 IAM Token 失败: <具体原因>"` |

## 实现细节

### scripts/swr-api.sh - 新文件

```bash
#!/bin/bash
set -eo pipefail

# 获取 IAM Token
# 返回: token 字符串
# 环境变量: IAM_ENDPOINT, IAM_USERNAME, IAM_PASSWORD, IAM_DOMAIN
get_iam_token() {
    : "${IAM_ENDPOINT:?IAM_ENDPOINT 环境变量未设置}"
    : "${IAM_USERNAME:?IAM_USERNAME 环境变量未设置}"
    : "${IAM_PASSWORD:?IAM_PASSWORD 环境变量未设置}"
    : "${IAM_DOMAIN:?IAM_DOMAIN 环境变量未设置}"

    local token_body=$(cat <<EOF
{
    "auth": {
        "identity": {
            "methods": ["password"],
            "password": {
                "user": {
                    "domain": {"name": "$IAM_DOMAIN"},
                    "name": "$IAM_USERNAME",
                    "password": "$IAM_PASSWORD"
                }
            }
        },
        "scope": {
            "domain": {
                "name": "$IAM_DOMAIN"
            }
        }
    }
}
EOF
)

    local response
    response=$(curl -sS -w "\n%{http_code}" \
        -X POST "https://${IAM_ENDPOINT}/v3/auth/tokens" \
        -H "Content-Type: application/json" \
        -d "$token_body")

    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | head -n -1)

    if [ "$http_code" = "201" ]; then
        echo "$body" | jq -r '.token.expires_at' 2>/dev/null
        return 0
    else
        local error_msg=$(echo "$body" | jq -r '.error.message // "未知错误"' 2>/dev/null || echo "HTTP $http_code")
        echo "IAM 认证失败 (HTTP $http_code): $error_msg" >&2
        return 1
    fi
}

# 设置镜像仓库为 public
# 参数: namespace, repository, token
# 返回: 0 成功, 1 失败
set_repo_public() {
    local namespace="$1"
    local repository="$2"
    local token="$3"

    : "${SWR_API_ENDPOINT:?SWR_API_ENDPOINT 环境变量未设置}"

    # repository 中如果有 / 需要替换为 $
    local repo_escaped="${repository//\//\$}"

    local response
    response=$(curl -sS -w "\n%{http_code}" \
        -X PATCH "https://${SWR_API_ENDPOINT}/v2/manage/namespaces/${namespace}/repos/${repo_escaped}" \
        -H "X-Auth-Token: $token" \
        -H "Content-Type: application/json" \
        -d '{"is_public": true}')

    local http_code=$(echo "$response" | tail -n1)

    if [ "$http_code" = "201" ]; then
        return 0
    else
        local body=$(echo "$response" | head -n -1)
        local error_msg=$(echo "$body" | jq -r '.error.message // "未知错误"' 2>/dev/null || echo "HTTP $http_code")
        echo "设置 public 失败 (HTTP $http_code): $error_msg" >&2
        return 1
    fi
}
```

### scripts/utils.sh - 新增函数

```bash
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
```

### scripts/sync.sh - 修改 sync_image 函数

```bash
# 同步单个镜像
sync_image() {
    local source_image="$1"
    local target_image="$2"

    echo "正在同步: $source_image -> $target_image"

    # 1. 同步镜像
    if skopeo copy \
        --dest-creds "${REGISTRY_USERNAME}:${REGISTRY_PASSWORD}" \
        "docker://${source_image}" \
        "docker://${target_image}"; then

        # 2. 设置为 public
        local error_msg=""
        local status="success:private"

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
                    status="success:public"
                else
                    error_msg="$set_public_result"
                fi
            else
                error_msg="$token"
            fi
        fi

        add_mapping "$source_image" "$target_image" "$status" "$error_msg"
        echo "✓ 同步成功: $source_image (${status})"
        return 0
    else
        add_mapping "$1" "$2" "failed" "skopeo copy 失败"
        echo "✗ 同步失败: $source_image"
        return 1
    fi
}
```

### scripts/sync.sh - 修改 add_mapping 函数

```bash
# 添加映射记录
add_mapping() {
    local source="$1"
    local target="$2"
    local status="$3"
    local error_msg="${4:-}"

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if command -v jq &> /dev/null; then
        jq --arg src "$source" \
           --arg tgt "$target" \
           --arg time "$timestamp" \
           --arg st "$status" \
           --arg err "$error_msg" \
           '.lastUpdated = $time | .mappings[$src] = {
               "source": $src,
               "target": $tgt,
               "syncedAt": $time,
               "status": $st,
               "error_msg_msg": $err
           }' "$MAPPING_FILE" > "${MAPPING_FILE}.tmp" \
           && mv "${MAPPING_FILE}.tmp" "$MAPPING_FILE"
    fi
}
```

## 参考文档

- [更新镜像仓库的概要信息 - UpdateRepo](https://support.huaweicloud.com/api-swr/swr_02_0032.html)
- [获取IAM用户Token（使用密码）](https://support.huaweicloud.com/api-iam/iam_30_0001.html)
