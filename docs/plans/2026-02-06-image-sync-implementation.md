# Docker 镜像同步工具实现计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 构建一个将 Docker 镜像同步到华为云 SWR 的 CI/CD 工具，支持从 txt 文件读取镜像列表、查重、记录映射关系。

**Architecture:** 使用 GitHub Actions 触发同步任务，Shell 脚本调用 Skopeo 进行镜像传输，JSON 文件记录同步历史。

**Tech Stack:** GitHub Actions, Skopeo, Bash, jq

---

### Task 1: 创建项目目录结构

**Files:**
- Create: `scripts/`
- Create: `data/`

**Step 1: 创建目录**

```bash
mkdir -p scripts data
```

**Step 2: 验证目录创建**

Run: `ls -la scripts data`
Expected: 输出两个空目录

**Step 3: 提交**

```bash
git add scripts data
git commit -m "chore: 创建项目目录结构"
```

---

### Task 2: 创建输入数据文件 images.txt

**Files:**
- Create: `data/images.txt`

**Step 1: 创建示例 images.txt**

```bash
cat > data/images.txt << 'EOF'
# Docker 镜像同步列表
# 每行一个镜像，格式: source-image[:tag]

# 示例镜像
# gcr.io/kubernetes-release/pause:3.9
# ghcr.io/prometheus/prometheus:v2.45.0
# quay.io/coreos/etcd:v3.5.9
EOF
```

**Step 2: 验证文件内容**

Run: `cat data/images.txt`
Expected: 显示包含注释的示例文件

**Step 3: 提交**

```bash
git add data/images.txt
git commit -m "chore: 创建镜像列表输入文件"
```

---

### Task 3: 创建输出数据文件 mapping.json

**Files:**
- Create: `data/mapping.json`

**Step 1: 创建初始 mapping.json**

```bash
cat > data/mapping.json << 'EOF'
{
  "lastUpdated": "",
  "mappings": {}
}
EOF
```

**Step 2: 验证 JSON 格式**

Run: `cat data/mapping.json`
Expected: 输出有效的空映射 JSON

**Step 3: 提交**

```bash
git add data/mapping.json
git commit -m "chore: 创建镜像映射输出文件"
```

---

### Task 4: 创建工具脚本 utils.sh

**Files:**
- Create: `scripts/utils.sh`

**Step 1: 创建 utils.sh**

```bash
cat > scripts/utils.sh << 'EOF'
#!/bin/bash

# 镜像名转换: gcr.io/xxx/yyy -> swr.cn-north-1.myhuaweicloud.com/<组织名>/gcr-io-xxx-yyy
convert_image_name() {
    local source_image="$1"
    local namespace="$2"

    # 提取镜像名部分( (去掉 registry)
    local image_path="${source_image#*/}"

    # 替换 / 和 . 为 -
    local converted_name=$(echo "$image_path" | sed 's/[\/.]/-/g')

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
EOF
```

**Step 2: 设置执行权限**

Run: `chmod +x scripts/utils.sh`
Expected: 无错误

**Step 3: 验证函数语法**

Run: `bash -n scripts/utils.sh`
Expected: 无语法错误

**Step 4: 提交**

```bash
git add scripts/utils.sh
git commit -m "chore: 创建工具函数脚本"
```

---

### Task 5: 创建主同步脚本 sync.sh

**Files:**
- Create: `scripts/sync.sh`

**Step 1: 创建 sync.sh**

```bash
cat > scripts/sync.sh << 'EOF'
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
        --src-creds docker:docker \
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
EOF
```

**Step 2: 设置执行权限**

Run: `chmod +x scripts/sync.sh`
Expected: 无错误

**Step 3: 验证脚本语法**

Run: `bash -n scripts/sync.sh`
Expected: 无语法错误

**Step 4: 提交**

```bash
git add scripts/sync.sh
git commit -m "chore: 创建主同步脚本"
```

---

### Task 6: 创建 GitHub Actions 工作流文件

**Files:**
- Create: `.github/workflows/sync-images.yml`

**Step 1: 创建目录和工作流**

```bash
mkdir -p .github/workflows

cat > .github/workflows/sync-images.yml << 'EOF'
name: Sync Docker Images

permissions:
  contents: write

on:
  push:
    paths:
      - 'data/images.txt'
  workflow_dispatch:
  schedule:
    - cron: '0 2 * * *'

jobs:
  sync:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
          token: ${{ github.token }}

      - name: Install Skopeo and jq
        run: |
          sudo apt-get update
          sudo apt-get install -y skopeo jq

      - name: Setup Git Config
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"

      - name: Sync Images
        env:
          TARGET_REGISTRY: swr.cn-north-1.myhuaweicloud.com
          REGISTRY_USERNAME: ${{ secrets.REGISTRY_USERNAME }}
          REGISTRY_PASSWORD: ${{ secrets.REGISTRY_PASSWORD }}
        run: ./scripts/sync.sh
EOF
```

**Step 2: 验证 YAML 格式**

Run: `cat .github/workflows/sync-images.yml`
Expected: 输出工作流配置

**Step 3: 提交**

```bash
git add .github/workflows/sync-images.yml
git commit -m "chore: 创建 GitHub Actions 工作流"
```

---

### Task 7: 更新 README 文档

**Files:**
- Modify: `README.md`

**Step 1: 更新 README**

```bash
cat > README.md << 'EOF'
# Docker 镜像同步工具

这是一个用于将 Docker 镜像同步到华为云 SWR 的工具，使用 GitHub Actions 进行 CI/CD。

## 功能

- 从 `data/images.txt` 文件读取需要同步的镜像列表
- 自动查重，跳过已同步的镜像
- 使用 Skopeo 进行高效的镜像传输
- 记录镜像映射关系到 `data/mapping.json`
- 支持手动触发、文件变化触发、定时触发

## 快速开始

### 1. 配置 GitHub Secrets

在仓库 Settings → Secrets and variables → Actions 中添加:

- `REGISTRY_USERNAME`: SWR 用户名
- `REGISTRY_PASSWORD`: SWR 密码

### 2. 添加需要同步的镜像

编辑 `data/images.txt`，添加需要同步的镜像:

```
gcr.io/kubernetes-release/pause:3.9
ghcr.io/prometheus/prometheus:v2.45.0
```

### 3. 触发同步

提交变更:

```bash
git add data/images.txt
git commit -m "add: 新增需要同步的镜像"
git push
```

同步将自动触发。

## 触发方式

- **文件变化触发**: 修改 `data/images.txt` 并提交
- **手动触发**: GitHub Actions 页面 → Sync Docker Images → Run workflow
- **定时触发**: 每天凌晨 2 点 (UTC) 自动运行

## 输出

同步完成后，`data/mapping.json` 文件会更新，包含所有镜像的映射关系:

```json
{
  "lastUpdated": "2026-02-06T10:30:00Z",
  "mappings": {
    "gcr.io/kubernetes-release/pause:3.9": {
      "source": "gcr.io/kubernetes-release/pause:3.9",
      "target": "swr.cn-north-1.myhuaweicloud.com/shanyou/gcr-io-kubernetes-release-pause:3.9",
      "syncedAt": "2026-02-06T10:25:00Z",
      "status": "success"
    }
  }
}
```

## 镜像命名规则

源镜像: `gcr.io/kubernetes-release/pause:3.9`

目标镜像: `swr.cn-north-1.myhuaweicloud.com/shanyou/gcr-io-kubernetes-release-pause:3.9`

- 去掉原始 registry 前缀
- 将 `/` 和 `.` 替换为 `-`
- 目标 registry: `swr.cn-north-1.myhuaweicloud.com`
- 命名空间: `shanyou` (可通过 `SWR_ORG_NAME` 环境变量修改)

## 本地测试

```bash
# 设置环境变量
export TARGET_REGISTRY="swr.cn-north-1.myhuaweicloud.com"
export REGISTRY_USERNAME="your-username"
export REGISTRY_PASSWORD="your-password"
export SWR_ORG_NAME="shanyou"

# 运行同步脚本
./scripts/sync.sh
```

## 技术栈

- **GitHub Actions**: CI/CD 平台
- **Skopeo**: 镜像同步工具
- **jq**: JSON 处理工具
- **Bash**: 脚本语言
EOF
```

**Step 2: 验证 README 内容**

Run: `head -20 README.md`
Expected: 显示更新后的 README 内容

**Step 3: 提交**

```bash
git add README.md
git commit -m "docs: 更新项目文档"
```

---

### Task 8: 创建 .gitignore

**Files:**
- Create: `.gitignore`

**Step 1: 创建 .gitignore**

```bash
cat > .gitignore << 'EOF'
# 临时文件
*.tmp

# 日志文件
*.log
EOF
```

**Step 2: 提交**

```bash
git add .gitignore
git commit -m "chore: 添加 .gitignore"
```

---

### Task 9: 创建测试脚本

**Files:**
- Create: `scripts/test-utils.sh`

**Step 1: 创建测试脚本**

```bash
cat > scripts/test-utils.sh << 'EOF'
#!/bin/bash
set -eo pipefail

source ./scripts/utils.sh

echo "=== 测试工具函数 ==="

# 测试镜像名转换
export TARGET_REGISTRY="swr.cn-north-1.myhuaweicloud.com"
result=$(convert_image_name "gcr.io/kubernetes-release/pause" "test-ns")
expected="swr.cn-north-1.myhuaweicloud.com/test-ns/gcr-io-kubernetes-release-pause"

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

echo "=== 所有测试通过 ==="
EOF
```

**Step 2: 设置执行权限**

Run: `chmod +x scripts/test-utils.sh`
Expected: 无错误

**Step 3: 运行测试**

Run: `./scripts/test-utils.sh`
Expected: 输出所有测试通过

**Step 4: 提交**

```bash
git add scripts/test-utils.sh
git commit -m "test: 添加工具函数测试"
```

---

### Task 10: 推送到远程仓库

**Step 1: 检查当前状态**

Run: `git status`
Expected: 显示所有更改已提交

**Step 2: 推送到远程**

```bash
git push origin main
```

**Step 3: 验证推送**

Run: `git log --oneline -5`
Expected: 显示最近的提交记录
EOF
