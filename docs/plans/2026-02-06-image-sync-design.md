# Docker 镜像同步工具设计文档

## 概述

这是一个用于将 Docker 镜像同步到华为云 SWR 的工具，使用 GitHub Actions 进行 CI/CD。

## 整体架构

```
image-sync/
├── .github/
│   └── workflows/
│       └── sync-images.yml        # GitHub Action 工作流
├── scripts/
│   ├── sync.sh                    # 主同步脚本
│   └── utils.sh                   # 工具函数
├── data/
│   ├── images.txt                 # 输入:待同步的镜像列表
│   └── mapping.json               # 输出:镜像映射元数据
└── README.md
```

## 工作流程

```
用户修改 data/images.txt 并提交
    ↓
GitHub Action 检测到变化(或定时触发)
    ↓
读取 data/images.txt 中需要同步的镜像
    ↓
读取 data/mapping.json 检查历史记录(查重)
    ↓
使用 Skopeo 同步未存在的镜像
    ↓
更新 data/mapping.json 添加新映射
    ↓
提交 mapping.json 到仓库
```

## 数据格式

### data/images.txt (输入文件)

每行一个镜像，格式: `source-image[:tag]`

```
# 每行一个镜像,格式: source-image[:tag]
gcr.io/kubernetes-release/pause:3.9
ghcr.io/prometheus/prometheus:v2.45.0
quay.io/coreos/etcd:v3.5.9
k8s.gcr.io/ingress-nginx/controller:v1.9.4
```

### data/mapping.json (输出文件)

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

## GitHub Action 配置

触发方式:
- `data/images.txt` 文件变化时触发
- 手动触发 (`workflow_dispatch`)
- 每天定时触发 (UTC 时间 02:00)

目标 Registry: `swr.cn-north-1.myhuaweicloud.com`

默认命名空间: `shanyou`

## 工具函数 (scripts/utils.sh)

- `convert_image_name()`: 镜像名转换
  - 输入: `gcr.io/xxx/yyy`
  - 输出: `swr.cn-north-1.myhuaweicloud.com/shanyou/gcr-io-xxx-yyy`

- `is_synced()`: 检查镜像是否已同步
  - 从 `mapping.json` 中查找历史记录

- `deduplicate_images()`: 镜像去重
  - 去除注释、空行和重复项

## 主同步脚本 (scripts/sync.sh)

功能:
1. 读取 `images.txt` 并去重
2. 检查 `mapping.json` 历史记录进行查重
3. 使用 Skopeo 同步未同步的镜像
4. 更新 `mapping.json`
5. 提交变更到仓库

## 使用说明

### GitHub Secrets 配置

在仓库 Settings → Secrets and variables → Actions 中添加:
- `REGISTRY_USERNAME`: SWR 用户名
- `REGISTRY_PASSWORD`: SWR 密码

### 可选环境变量

- `SWR_ORG_NAME`: 组织名称 (默认: shanyou)

## 技术栈

- **Skopeo**: 镜像同步工具，支持直接 registry-to-registry 传输
- **jq**: JSON 处理工具
- **Bash**: 脚本语言
- **GitHub Actions**: CI/CD 平台
