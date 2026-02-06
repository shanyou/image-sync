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

**必需（镜像同步）**:
- `REGISTRY_USERNAME`: SWR 用户名 (格式: `区域@账号`)
- `REGISTRY_PASSWORD`: SWR 密码

**可选（自动设置 public）**:
- `IAM_ENDPOINT`: IAM 端点，如 `iam.myhuaweicloud.com`
- `SWR_API_ENDPOINT`: SWR API 端点，如 `swr-api.cn-north-1.myhuaweicloud.com`
- `IAM_DOMAIN`: IAM 账号名
- `IAM_USERNAME`: IAM 用户名
- `IAM_PASSWORD`: IAM 用户密码

> 注意：配置 IAM 相关变量后，镜像同步后会自动设置为 public。如果未配置，镜像将保持 private 状态。

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

# SWR API 配置（可选，用于自动设置 public）
export IAM_ENDPOINT="iam.myhuaweicloud.com"
export SWR_API_ENDPOINT="swr-api.cn-north-1.myhuaweicloud.com"
export IAM_DOMAIN="your-domain"
export IAM_USERNAME="your-iam-username"
export IAM_PASSWORD="your-iam-password"

# 运行同步脚本
./scripts/sync.sh
```

## 技术栈

- **GitHub Actions**: CI/CD 平台
- **Skopeo**: 镜像同步工具
- **jq**: JSON 处理工具
- **Bash**: 脚本语言
