#!/bin/bash
set -eo pipefail

# 获取 IAM Token
# 返回: token 字符串 (通过 stdout)
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

    local header_file=$(mktemp)
    local body_file=$(mktemp)
    
    # 使用 -D 将响应头保存到文件
    curl -sS -D "$header_file" -o "$body_file" -w "%{http_code}" \
        -X POST "https://${IAM_ENDPOINT}/v3/auth/tokens" \
        -H "Content-Type: application/json" \
        -d "$token_body" > /tmp/http_code.txt 2>&1
    
    local http_code=$(cat /tmp/http_code.txt)
    local token=$(grep -i "^x-subject-token:" "$header_file" | awk '{print $2}' | tr -d '\r')
    local body=$(cat "$body_file")
    
    rm -f "$header_file" "$body_file" /tmp/http_code.txt

    if [ "$http_code" = "201" ] && [ -n "$token" ]; then
        echo "$token"
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
