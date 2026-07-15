Docker 镜像同步工具
===================

将 Docker 镜像同步到华为云 SWR 的 CI/CD 工具，基于 GitHub Actions + Skopeo 实现 registry-to-registry 高效传输。

[![Sync Status](https://img.shields.io/badge/Sync-Status-green?style=flat-square&logo=github)](https://shanyou.github.io/image-sync/)
[![GitHub Pages](https://img.shields.io/badge/GitHub-Pages-blue?style=flat-square&logo=github)](https://shanyou.github.io/image-sync/)

📊 **同步状态页**: [https://shanyou.github.io/image-sync/](https://shanyou.github.io/image-sync/)

## 功能

- 从 `data/images.txt` 读取待同步镜像列表
- **Manifest digest 比对**: 默认根据源镜像 manifest digest 判定是否需要同步，避免无效传输
- **多 arch 支持**: `skopeo copy --all` 同步所有平台变体
- **自动设置 public**: 同步后调用华为云 SWR API 将仓库设为公开
- **僵尸记录清理**: 自动清理 `mapping.json` 中已从 `images.txt` 移除的镜像记录
- **输入去重**: 自动去重和过滤注释/空行
- **Docker Hub 限流规避**: 支持 Docker Hub 认证凭据，规避匿名 100 pulls/6h 限制
- **Drift 检测**: `--check-drift` 探测 SWR 端是否被外部改动
- 记录同步历史到 `data/mapping.json`（含源 manifest digest）
- 支持手动触发、文件变更触发、定时触发

## 快速开始

### 1. 配置 GitHub Secrets

仓库 Settings → Secrets and variables → Actions：

**必需**:
| Secret | 说明 |
|---|---|
| `REGISTRY_USERNAME` | SWR 用户名（格式：`区域@账号`） |
| `REGISTRY_PASSWORD` | SWR 密码 |

**Docker Hub 源凭据（强烈推荐）**:
| Secret | 说明 |
|---|---|
| `DOCKERHUB_USERNAME` | Docker Hub 账号 |
| `DOCKERHUB_TOKEN` | Docker Hub Access Token（hub.docker.com → Settings → Security） |

> 未配置 Docker Hub 凭据时，对 docker.io 源的拉取使用匿名模式（100 pulls/6h），镜像较多时可能触发限流。

**自动设置 public（可选）**:
| Secret | 说明 |
|---|---|
| `IAM_ENDPOINT` | IAM 端点，如 `iam.myhuaweicloud.com` |
| `SWR_API_ENDPOINT` | SWR API 端点 |
| `IAM_DOMAIN` | IAM 账号名 |
| `IAM_USERNAME` | IAM 用户名 |
| `IAM_PASSWORD` | IAM 用户密码 |

> 未配置 IAM 相关变量时同步仍正常运行，仅跳过设置 public。

### 2. 添加待同步镜像

编辑 `data/images.txt`（每行一个镜像，`#` 开头为注释，空行忽略）：

```
gcr.io/kubernetes-release/pause:3.9
ghcr.io/prometheus/prometheus:v2.45.0
```

### 3. 触发同步

```bash
git add data/images.txt
git commit -m "add: 新增待同步镜像"
git push
```

文件变更自动触发同步。默认仅同步源 digest 发生变化的镜像（rolling tag 更新自动追踪）。

## 触发方式

| 方式 | 触发条件 | 行为 |
|---|---|---|
| 文件变更 | 修改 `data/images.txt` 并 push | Digest 比对，仅变更的镜像同步 |
| 手动触发 | Actions → Sync Docker Images → Run workflow | 可选 `force_sync`（全量）或 `check_drift`（额外校验 SWR 端） |
| 定时触发 | 每天 UTC 02:00 | Digest 比对，追踪 rolling tag 更新 |

## 同步模式

```bash
./scripts/sync.sh                 # 默认：比对源 digest，仅变更的同步
./scripts/sync.sh --force          # 强制全量同步，忽略 digest
./scripts/sync.sh --check-drift    # 额外校验 SWR 端是否被外部改动
```

## 输出

同步完成后 `data/mapping.json` 更新：

```json
{
  "lastUpdated": "2026-07-15T06:03:32Z",
  "mappings": {
    "gcr.io/kubernetes-release/pause:3.9": {
      "source": "gcr.io/kubernetes-release/pause:3.9",
      "target": "swr.cn-north-1.myhuaweicloud.com/shanyou/gcr-io-kubernetes-release-pause:3.9",
      "syncedAt": "2026-07-15T06:00:00Z",
      "status": "success",
      "is_public": "true",
      "error_msg": "",
      "sourceDigest": "sha256:3fbc632167424a6d997e74f52b878d7cc478225cffac6bc977eedfe51c7f4e79"
    }
  }
}
```

字段说明：
- `status`: `success` | `failed`
- `is_public`: `true` | `false`（仅在 IAM 变量配置时可能为 `true`）
- `sourceDigest`: 同步成功时记录的源镜像 manifest digest（`sha256:...`），失败/未取到时为空。用于追踪 rolling tag 对应的上游版本

## 镜像命名规则

源: `gcr.io/kubernetes-release/pause:3.9`

目标: `swr.cn-north-1.myhuaweicloud.com/shanyou/gcr-io-kubernetes-release-pause:3.9`

- 去掉原始 registry 前缀
- 镜像名中的 `/` 和 `.` → `-`
- 目标 registry: `swr.cn-north-1.myhuaweicloud.com`
- 命名空间: `shanyou`（通过 `SWR_ORG_NAME` 修改）
- 源镜像带 digest（`@sha256:...`）时自动剥离，目标仅保留 tag

## 本地开发

```bash
# 加载环境变量
source .env

# .env 示例
export TARGET_REGISTRY=swr.cn-north-1.myhuaweicloud.com
export REGISTRY_USERNAME=your-username
export REGISTRY_PASSWORD=your-password
export SWR_ORG_NAME=shanyou

# Docker Hub 源凭据（规避限流）
export DOCKERHUB_USERNAME=your-dockerhub-username
export DOCKERHUB_TOKEN=dckr_pat_xxx

# SWR API 配置（可选，用于自动设置 public）
export IAM_ENDPOINT=iam.myhuaweicloud.com
export SWR_API_ENDPOINT=swr-api.cn-north-1.myhuaweicloud.com
export IAM_DOMAIN=your-domain
export IAM_USERNAME=your-iam-username
export IAM_PASSWORD=your-iam-password

# 运行
./scripts/sync.sh                 # 默认 digest 比对
./scripts/sync.sh --force          # 强制全量同步
./scripts/sync.sh --check-drift    # 额外校验 SWR 端是否被改动

# 单元测试
./scripts/test-utils.sh
```

## 测试

`scripts/test-utils.sh` 覆盖：
- `convert_image_name` — 基本转换、无 tag 默认 latest、digest 剥离
- `needs_sync` — 无 mapping 文件、failed 重试、digest 相同跳过、digest 不同触发、drift 检测
- `parse_target_image` — 单层/多层路径解析
- `get_source_creds_value` — docker.io 凭据、短镜像名、非 docker.io 源
- `cleanup_stale_mappings` — 僵尸记录清理

## GitHub Pages 状态页

入口: [https://shanyou.github.io/image-sync/](https://shanyou.github.io/image-sync/)

自动部署：`.github/workflows/deploy-pages.yml` 在 `data/` 目录变更时触发，将内容部署到 `gh-pages` 分支。

特性：
- 动态加载 `mapping.json`，数据更新无需重新生成 HTML
- 同步统计（总数/成功/Public/失败）、搜索、状态筛选
- 一键复制目标镜像地址
- 响应式设计

### 配置

仓库 Settings → Pages：
- Source: `Deploy from a branch`
- Branch: `gh-pages` + `/ (root)`

## 技术栈

| 组件 | 用途 |
|---|---|
| GitHub Actions | CI/CD 平台 |
| Skopeo | 镜像 registry-to-registry 传输 |
| jq | JSON 处理 |
| Bash 4.0+ | 脚本语言 |
| GitHub Pages | 静态页面托管 |
