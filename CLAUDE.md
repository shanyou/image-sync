# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

Docker 镜像同步工具 - 将 Docker 镜像从公共 Registry 同步到华为云 SWR (SoftWare Repository)。

## 快速命令

### 本地测试同步
```bash
export TARGET_REGISTRY="swr.cn-north-1.myhuaweicloud.com"
export REGISTRY_USERNAME="your-username"
export REGISTRY_PASSWORD="your-password"
export SWR_ORG_NAME="shanyou"
./scripts/sync.sh
```

### 强制同步所有镜像
```bash
./scripts/sync.sh --force
```

### 测试 SWR API 功能
```bash
./scripts/test-swr-api.sh
./scripts/test-set-public.sh
```

## 架构概述

```
├── scripts/
│   ├── sync.sh          # 主同步脚本
│   ├── utils.sh         # 工具函数 (镜像名转换、去重)
│   └── swr-api.sh       # SWR API 交互 (获取 Token、设置 public)
├── data/
│   ├── images.txt       # 源镜像列表
│   ├── mapping.json     # 同步映射记录 (由脚本生成)
│   └── index.html       # GitHub Pages 状态页面
└── .github/workflows/
    ├── sync-images.yml      # 镜像同步 CI
    └── deploy-pages.yml     # 部署 Pages
```

## 核心流程

1. **读取镜像列表**: 从 `data/images.txt` 读取源镜像
2. **镜像名转换**: `gcr.io/xxx/yyy:tag` → `swr.cn-north-1.myhuaweicloud.com/<org>/gcr-io-xxx-yyy:tag`
3. **Skopeo 同步**: 使用 `skopeo copy` 传输镜像
4. **设置 Public**: 调用 SWR API 将镜像仓库设为公开 (可选)
5. **记录映射**: 更新 `data/mapping.json`

## 环境变量

### 必需
- `TARGET_REGISTRY`: 目标 Registry (如 `swr.cn-north-1.myhuaweicloud.com`)
- `REGISTRY_USERNAME`: SWR 认证用户名
- `REGISTRY_PASSWORD`: SWR 认证密码

### 可选 (用于自动设置 public)
- `IAM_ENDPOINT`: IAM 端点 (如 `iam.myhuaweicloud.com`)
- `SWR_API_ENDPOINT`: SWR API 端点
- `IAM_DOMAIN`: IAM 账号域
- `IAM_USERNAME`: IAM 用户名
- `IAM_PASSWORD`: IAM 密码

## GitHub Actions

### 触发方式
- **文件变化**: `data/images.txt` 修改后 push
- **手动触发**: Actions 页面选择 "Sync Docker Images"
- **定时触发**: 每天凌晨 2 点 (UTC)

### Secrets 配置
- `REGISTRY_USERNAME`, `REGISTRY_PASSWORD` (必需)
- `IAM_ENDPOINT`, `SWR_API_ENDPOINT`, `IAM_DOMAIN`, `IAM_USERNAME`, `IAM_PASSWORD` (可选)

## GitHub Pages

状态页面部署流程:
1. `data/` 目录内容自动部署到 `gh-pages` 分支
2. 访问 `https://shanyou.github.io/image-sync/` 查看状态
3. 配置：Settings → Pages → Branch: `gh-pages`

## 依赖工具

- **Skopeo**: 镜像传输
- **jq**: JSON 处理
- **Bash**: 脚本执行
- **Git**: 版本控制
