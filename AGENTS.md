# Docker 镜像同步工具 - 项目指南

## 项目概述

这是一个用于将 Docker 镜像同步到华为云 SWR (SoftWare Repository for Container) 的 CI/CD 工具。通过 GitHub Actions 触发同步任务，使用 Skopeo 进行高效的 registry-to-registry 镜像传输，并自动将同步后的镜像仓库设置为 public。

### 核心功能

- 从 `data/images.txt` 读取待同步镜像列表
- 自动查重，跳过已同步的镜像（基于 `data/mapping.json`）
- 使用 Skopeo 进行无需中间存储的镜像传输
- 同步完成后自动调用华为云 API 设置镜像为 public
- 记录详细的同步映射关系到 JSON 文件
- 支持多种触发方式：文件变更、手动触发、定时触发

## 技术栈

| 组件 | 用途 | 版本要求 |
|------|------|----------|
| GitHub Actions | CI/CD 平台 | - |
| Skopeo | 镜像同步工具 | 最新 |
| jq | JSON 处理 | 1.6+ |
| Bash | 脚本语言 | 4.0+ |
| curl | HTTP 请求工具 | - |

## 项目结构

```
image-sync/
├── .github/
│   └── workflows/
│       ├── sync-images.yml        # GitHub Actions 工作流定义
│       └── deploy-pages.yml       # GitHub Pages 自动部署工作流
├── scripts/
│   ├── sync.sh                    # 主同步脚本（入口点）
│   ├── utils.sh                   # 工具函数（镜像名转换、查重等）
│   ├── swr-api.sh                 # 华为云 IAM/SWR API 封装
│   └── test-utils.sh              # 单元测试脚本
├── data/
│   ├── images.txt                 # 输入：待同步镜像列表
│   ├── mapping.json               # 输出：同步历史与映射记录
│   └── index.html                 # Web UI 状态页面（GitHub Pages 入口）
├── docs/
│   └── plans/                     # 设计文档与实现计划
├── .env                           # 本地环境变量配置（已 gitignore）
├── .gitignore                     # Git 忽略规则
└── README.md                      # 用户文档
```

## 模块说明

### 1. 主同步脚本 (scripts/sync.sh)

**职责**：协调整个同步流程

**关键函数**：
- `init_mapping()`: 初始化 mapping.json 文件
- `add_mapping()`: 添加同步记录到 mapping.json
- `sync_image()`: 同步单个镜像并设置 public
- `main()`: 主流程控制

**依赖**：utils.sh, swr-api.sh

### 2. 工具函数 (scripts/utils.sh)

**职责**：提供镜像处理工具函数

**函数列表**：
- `convert_image_name(source, namespace)`: 转换镜像名称
  - 输入: `gcr.io/kubernetes-release/pause:3.9`
  - 输出: `swr.cn-north-1.myhuaweicloud.com/shanyou/gcr-io-kubernetes-release-pause:3-9`
- `is_synced(image, mapping_file)`: 检查镜像是否已同步
- `deduplicate_images(input_file)`: 去重并过滤注释和空行
- `parse_target_image(target_image)`: 解析目标镜像名
  - 输出格式: `namespace|repository|tag`

### 3. SWR API 封装 (scripts/swr-api.sh)

**职责**：华为云认证与 API 调用

**函数列表**：
- `get_iam_token()`: 获取 IAM 认证 Token
  - 使用环境变量：IAM_ENDPOINT, IAM_USERNAME, IAM_PASSWORD, IAM_DOMAIN
  - 返回：X-Subject-Token
- `set_repo_public(namespace, repository, token)`: 设置镜像仓库为 public
  - 调用 SWR UpdateRepo API
  - 注意：repository 中的 `/` 需要替换为 `$`

### 4. 测试脚本 (scripts/test-utils.sh)

**职责**：单元测试 utils.sh 中的函数

**测试覆盖**：
- `convert_image_name` 基本转换
- `is_synced` 空文件检查
- `parse_target_image` 单层和多层路径解析

## 数据格式

### 输入文件 (data/images.txt)

```text
# Docker 镜像同步列表
# 每行一个镜像，格式: source-image[:tag]

# 示例镜像
gcr.io/kubernetes-release/pause:3.9
ghcr.io/prometheus/prometheus:v2.45.0
quay.io/coreos/etcd:v3.5.9
```

**规则**：
- 以 `#` 开头的行为注释
- 空行会被忽略
- 每行一个镜像，必须包含 tag

### 输出文件 (data/mapping.json)

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
    }
  }
}
```

**status 枚举值**：
- `success` - 同步成功
- `failed` - 同步失败

**is_public 枚举值**：
- `true` - 已设置为 public
- `false` - 未设置为 public（可能同步成功但未公开，或设置 public 失败）

## 环境变量

### 必需环境变量

| 变量名 | 用途 | 示例 |
|--------|------|------|
| `TARGET_REGISTRY` | 目标仓库地址 | `swr.cn-north-1.myhuaweicloud.com` |
| `REGISTRY_USERNAME` | SWR 登录用户名 | `cn-north-1@xxx` |
| `REGISTRY_PASSWORD` | SWR 登录密码 | - |

### 可选环境变量

| 变量名 | 用途 | 默认值 |
|--------|------|--------|
| `SWR_ORG_NAME` | SWR 命名空间/组织 | `shanyou` |
| `IAM_ENDPOINT` | IAM 认证端点 | `iam.myhuaweicloud.com` |
| `SWR_API_ENDPOINT` | SWR API 端点 | `swr-api.cn-north-1.myhuaweicloud.com` |
| `IAM_DOMAIN` | IAM 用户所属账号名 | - |
| `IAM_USERNAME` | IAM 用户名 | - |
| `IAM_PASSWORD` | IAM 用户密码 | - |

### 本地开发环境配置 (.env)

```bash
export TARGET_REGISTRY=swr.cn-north-1.myhuaweicloud.com
export REGISTRY_USERNAME=your-username
export REGISTRY_PASSWORD=your-password
export SWR_ORG_NAME=shanyou

# 如需自动设置 public，需配置以下变量
export IAM_ENDPOINT=iam.myhuaweicloud.com
export SWR_API_ENDPOINT=swr-api.cn-north-1.myhuaweicloud.com
export IAM_DOMAIN=your-domain
export IAM_USERNAME=your-iam-username
export IAM_PASSWORD=your-iam-password
```

## 构建与运行

### 本地运行

```bash
# 1. 加载环境变量
source .env

# 2. 运行同步脚本
./scripts/sync.sh
```

### 本地测试

```bash
# 运行单元测试
./scripts/test-utils.sh
```

### GitHub Actions 触发方式

**镜像同步工作流** (`sync-images.yml`):
1. **文件变更触发**：修改 `data/images.txt` 并 push
2. **手动触发**：GitHub Actions 页面 → Sync Docker Images → Run workflow
3. **定时触发**：每天 UTC 02:00 自动运行

**Pages 部署工作流** (`deploy-pages.yml`):
1. **文件变更触发**：修改 `data/**` 目录下的文件并 push 到 `main` 分支
2. **手动触发**：GitHub Actions 页面 → Deploy to GitHub Pages → Run workflow

## GitHub Pages 部署

### 部署流程

1. `main` 分支的 `data/` 目录包含源文件
2. `.github/workflows/deploy-pages.yml` 工作流自动将 `data/` 内容部署到 `gh-pages` 分支
3. GitHub Pages 从 `gh-pages` 分支提供服务

### Web UI

**入口文件**: `data/index.html`

**特性**:
- 动态加载 `mapping.json`（通过 `fetch()`），数据更新无需重新生成 HTML
- 赛博朋克风格界面
- 显示同步统计、镜像列表、时间线、注册源分布
- 一键复制目标镜像地址
- 响应式设计

**本地预览**:
```bash
cd data
python3 -m http.server 8080
# 访问 http://localhost:8080
```

## 开发规范

### 代码风格

- **Shell 脚本**：
  - 使用 `#!/bin/bash` shebang
  - 启用严格模式：`set -eo pipefail`
  - 函数使用小写下划线命名法
  - 局部变量使用 `local` 声明
  - 使用 `$()` 而非反引号进行命令替换

### Git 提交规范

- `chore:` - 构建过程或辅助工具的变动
- `docs:` - 文档更新
- `feat:` - 新功能
- `fix:` - 修复问题
- `test:` - 添加测试

### 文件权限

- 所有 `.sh` 脚本必须设置为可执行：`chmod +x scripts/*.sh`

## 测试策略

### 单元测试

- 测试文件：`scripts/test-utils.sh`
- 覆盖范围：utils.sh 中的所有工具函数
- 运行方式：直接执行 `./scripts/test-utils.sh`
- 断言方式：比较实际输出与预期输出，失败时 exit 1

### 集成测试

- 通过 GitHub Actions 在实际环境中运行
- 测试完整的同步流程
- 验证 mapping.json 更新

### Web UI 测试

- 本地使用 `python3 -m http.server` 或 `npx serve` 预览
- 验证 `mapping.json` 能正常加载
- 检查响应式布局

## 安全考虑

1. **密钥管理**：
   - 所有敏感信息通过 GitHub Secrets 注入
   - `.env` 文件已添加到 `.gitignore`，防止意外提交
   - 本地开发使用 `.env` 文件，但绝不提交到仓库

2. **API 安全**：
   - IAM Token 有效期 24 小时，每次同步时重新获取
   - 使用 HTTPS 进行所有 API 调用
   - 错误信息中不包含敏感凭证

3. **权限控制**：
   - GitHub Actions 使用最小权限原则（`contents: write`）
   - 仅允许修改 mapping.json 文件

## 故障排查

### 常见问题

1. **skopeo copy 失败**：
   - 检查源镜像是否存在
   - 检查目标仓库认证信息

2. **设置 public 失败**：
   - 检查 IAM 认证信息
   - 确认 IAM 用户有 SWR 管理权限
   - 查看 mapping.json 中的 error_msg 字段

3. **mapping.json 未更新**：
   - 检查 GitHub Actions 日志
   - 确认工作流有写权限

### 调试模式

在脚本中添加 `set -x` 启用详细输出：

```bash
#!/bin/bash
set -exo pipefail  # 添加 x 选项
```

## 参考文档

- [华为云 SWR UpdateRepo API](https://support.huaweicloud.com/api-swr/swr_02_0032.html)
- [华为云 IAM Token 获取](https://support.huaweicloud.com/api-iam/iam_30_0001.html)
- [Skopeo 官方文档](https://github.com/containers/skopeo)
