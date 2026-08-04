# 华为云 SWR 镜像替换指南

本文档指导各项目将 Docker Hub / 其他源 registry 的镜像替换为华为云 SWR 同步副本。

- 同步仓库：`shanyou/image-sync`
- 目标仓库：`swr.cn-north-1.myhuaweicloud.com/shanyou/`
- 同步状态：由 GitHub Actions 每日自动比对源 digest 增量同步；镜像列表见 `data/images.txt`
- 本表数据来源：`data/mapping.json`（同步成功即自动更新），生成时间 2026-08-04

## 使用方法

**1. 查表替换**：在下方映射表中找到你项目用的源镜像，直接替换为 SWR 地址。

```yaml
# 替换前
image: nginx:latest
# 替换后
image: swr.cn-north-1.myhuaweicloud.com/shanyou/nginx:latest
```

**2. 镜像不在表里**：向镜像维护人提需求，在 `data/images.txt` 加一行并 push，CI 自动同步（或手动触发 Actions），下次更新本文档即可见。

## 目标镜像命名规则

`源镜像名` 中的 `/` 和 `.` 统一替换为 `-`，tag 保持原样：

| 源镜像 | 目标镜像 |
|---|---|
| `nginx:latest` | `shanyou/nginx:latest` |
| `ghcr.io/kubelauncher/redis:8.6.1` | `shanyou/ghcr-io-kubelauncher-redis:8.6.1` |
| `docker.elastic.co/elasticsearch/elasticsearch:8.14.3` | `shanyou/docker-elastic-co-elasticsearch-elasticsearch:8.14.3` |

所有仓库均已设置为 public，无需认证即可 `docker pull`。

## 特殊说明

### bitnami 老镜像下架替换（2026-08）

Bitnami 已将老镜像从 Docker Hub 下架，以下镜像已替换为可用源后同步，**项目侧引用时请使用 SWR 地址，不受影响**；若你直接引用源仓库，需同步改为新源：

| 原源（已下架） | 新源 |
|---|---|
| `bitnami/mysql:8.0.37-debian-12-r2` | `bitnamilegacy/mysql:8.0.37-debian-12-r2` |
| `bitnami/redis:6.2.7-debian-11-r11` | `bitnamilegacy/redis:6.2.7-debian-11-r11` |
| `bitnami/rabbitmq:3.10.8-debian-11-r4` | `bitnamilegacy/rabbitmq:3.10.8-debian-11-r4` |
| `bitnami/elasticsearch:7.16.2-debian-10-r0` | `docker.elastic.co/elasticsearch/elasticsearch:7.16.2` |
| `bitnami/influxdb:1.8.3-debian-10-r88` | `influxdb:1.8.3`（官方） |
| `bitnami/mongodb:4.4.10-debian-10-r44` | `mongo:4.4.10`（官方） |
| `bitnami/nginx-ingress-controller:0.48.1-debian-10-r38` | `registry.k8s.io/ingress-nginx/controller:v0.48.1` |
| `bitnami/nginx:1.21.1-debian-10-r46` | `nginx:1.21.1`（官方） |

> 注意：换成官方源的镜像（mongo/nginx/influxdb/elasticsearch/ingress-controller）与 bitnami 版的文件布局、环境变量、启动方式不同（如 bitnami 的 `/opt/bitnami/...` 路径、`ALLOW_EMPTY_PASSWORD` 等专属变量）。配置挂载这些镜像的项目需相应调整。

### 多平台镜像说明

`mongo:4.4.10` 因 manifest list 含 Windows 巨型变体无法上传 SWR，已按 Linux 单平台同步（`linux/amd64` + `linux/arm64`）。K8s 使用不受影响。

## 完整镜像映射表

| `1dev/server:latest` | `swr.cn-north-1.myhuaweicloud.com/shanyou/1dev-server:latest` |
| `adrianmusante/pocketbase` | `swr.cn-north-1.myhuaweicloud.com/shanyou/adrianmusante-pocketbase:latest` |
| `alpine/socat` | `swr.cn-north-1.myhuaweicloud.com/shanyou/alpine-socat:latest` |
| `bitnami/os-shell` | `swr.cn-north-1.myhuaweicloud.com/shanyou/bitnami-os-shell:latest` |
| `bitnami/postgres-exporter` | `swr.cn-north-1.myhuaweicloud.com/shanyou/bitnami-postgres-exporter:latest` |
| `bitnami/postgresql` | `swr.cn-north-1.myhuaweicloud.com/shanyou/bitnami-postgresql:latest` |
| `bitnamilegacy/mysql:8.0.37-debian-12-r2` | `swr.cn-north-1.myhuaweicloud.com/shanyou/bitnamilegacy-mysql:8.0.37-debian-12-r2` |
| `bitnamilegacy/rabbitmq:3.10.8-debian-11-r4` | `swr.cn-north-1.myhuaweicloud.com/shanyou/bitnamilegacy-rabbitmq:3.10.8-debian-11-r4` |
| `bitnamilegacy/redis:6.2.7-debian-11-r11` | `swr.cn-north-1.myhuaweicloud.com/shanyou/bitnamilegacy-redis:6.2.7-debian-11-r11` |
| `bkci/bkci-backend:v4.1.0` | `swr.cn-north-1.myhuaweicloud.com/shanyou/bkci-bkci-backend:v4.1.0` |
| `bkci/bkci-frontend:v4.1.0` | `swr.cn-north-1.myhuaweicloud.com/shanyou/bkci-bkci-frontend:v4.1.0` |
| `bkci/bkci-gateway:v4.1.0` | `swr.cn-north-1.myhuaweicloud.com/shanyou/bkci-bkci-gateway:v4.1.0` |
| `bkci/bkci-kubernetes-manager:0.0.33` | `swr.cn-north-1.myhuaweicloud.com/shanyou/bkci-bkci-kubernetes-manager:0.0.33` |
| `bkci/bkci-turbo:0.0.21` | `swr.cn-north-1.myhuaweicloud.com/shanyou/bkci-bkci-turbo:0.0.21` |
| `bkci/ci:jdk17` | `swr.cn-north-1.myhuaweicloud.com/shanyou/bkci-ci:jdk17` |
| `bkci/ci:latest` | `swr.cn-north-1.myhuaweicloud.com/shanyou/bkci-ci:latest` |
| `busybox:latest` | `swr.cn-north-1.myhuaweicloud.com/shanyou/busybox:latest` |
| `busybox:stable` | `swr.cn-north-1.myhuaweicloud.com/shanyou/busybox:stable` |
| `calciumion/new-api:latest` | `swr.cn-north-1.myhuaweicloud.com/shanyou/calciumion-new-api:latest` |
| `centos:7` | `swr.cn-north-1.myhuaweicloud.com/shanyou/centos:7` |
| `certbot/certbot:latest` | `swr.cn-north-1.myhuaweicloud.com/shanyou/certbot-certbot:latest` |
| `codeberg.org/forgejo/forgejo:14` | `swr.cn-north-1.myhuaweicloud.com/shanyou/codeberg-org-forgejo-forgejo:14` |
| `container-registry.oracle.com/database/free:latest` | `swr.cn-north-1.myhuaweicloud.com/shanyou/container-registry-oracle-com-database-free:latest` |
| `containers.intersystems.com/intersystems/iris-community:2025.3` | `swr.cn-north-1.myhuaweicloud.com/shanyou/containers-intersystems-com-intersystems-iris-community:2025.3` |
| `docker.elastic.co/elasticsearch/elasticsearch:7.16.2` | `swr.cn-north-1.myhuaweicloud.com/shanyou/docker-elastic-co-elasticsearch-elasticsearch:7.16.2` |
| `docker.elastic.co/elasticsearch/elasticsearch:8.14.3` | `swr.cn-north-1.myhuaweicloud.com/shanyou/docker-elastic-co-elasticsearch-elasticsearch:8.14.3` |
| `docker.elastic.co/kibana/kibana:8.14.3` | `swr.cn-north-1.myhuaweicloud.com/shanyou/docker-elastic-co-kibana-kibana:8.14.3` |
| `docker:28.3.1-dind` | `swr.cn-north-1.myhuaweicloud.com/shanyou/docker:28.3.1-dind` |
| `docker:dind` | `swr.cn-north-1.myhuaweicloud.com/shanyou/docker:dind` |
| `docker:latest` | `swr.cn-north-1.myhuaweicloud.com/shanyou/docker:latest` |
| `dockurr/windows:latest` | `swr.cn-north-1.myhuaweicloud.com/shanyou/dockurr-windows:latest` |
| `downloads.unstructured.io/unstructured-io/unstructured-api:latest` | `swr.cn-north-1.myhuaweicloud.com/shanyou/downloads-unstructured-io-unstructured-io-unstructured-api:latest` |
| `eceasy/cli-proxy-api:latest` | `swr.cn-north-1.myhuaweicloud.com/shanyou/eceasy-cli-proxy-api:latest` |
| `forgejo.ellis.link/continuwuation/continuwuity:latest` | `swr.cn-north-1.myhuaweicloud.com/shanyou/forgejo-ellis-link-continuwuation-continuwuity:latest` |
| `gcr.io/kaniko-project/executor:v1.9.0` | `swr.cn-north-1.myhuaweicloud.com/shanyou/gcr-io-kaniko-project-executor:v1.9.0` |
| `ghcr.io/chroma-core/chroma:0.5.20` | `swr.cn-north-1.myhuaweicloud.com/shanyou/ghcr-io-chroma-core-chroma:0.5.20` |
| `ghcr.io/kubelauncher/mysql:8.0.45` | `swr.cn-north-1.myhuaweicloud.com/shanyou/ghcr-io-kubelauncher-mysql:8.0.45` |
| `ghcr.io/kubelauncher/rabbitmq:4.2.4` | `swr.cn-north-1.myhuaweicloud.com/shanyou/ghcr-io-kubelauncher-rabbitmq:4.2.4` |
| `ghcr.io/kubelauncher/redis:8.6.1` | `swr.cn-north-1.myhuaweicloud.com/shanyou/ghcr-io-kubelauncher-redis:8.6.1` |
| `goacme/lego:latest` | `swr.cn-north-1.myhuaweicloud.com/shanyou/goacme-lego:latest` |
| `golang:1.26.1` | `swr.cn-north-1.myhuaweicloud.com/shanyou/golang:1.26.1` |
| `harness/harness:latest` | `swr.cn-north-1.myhuaweicloud.com/shanyou/harness-harness:latest` |
| `headscale/headscale:latest` | `swr.cn-north-1.myhuaweicloud.com/shanyou/headscale-headscale:latest` |
| `influxdb:1.8.3` | `swr.cn-north-1.myhuaweicloud.com/shanyou/influxdb:1.8.3` |
| `jenkins/inbound-agent:3355.v388858a_47b_33-9` | `swr.cn-north-1.myhuaweicloud.com/shanyou/jenkins-inbound-agent:3355.v388858a_47b_33-9` |
| `jenkins/jenkins:2.541.1-jdk21` | `swr.cn-north-1.myhuaweicloud.com/shanyou/jenkins-jenkins:2.541.1-jdk21` |
| `jenkinsci/blueocean:latest` | `swr.cn-north-1.myhuaweicloud.com/shanyou/jenkinsci-blueocean:latest` |
| `jevolk/tuwunel:latest` | `swr.cn-north-1.myhuaweicloud.com/shanyou/jevolk-tuwunel:latest` |
| `kasmweb/ubuntu-noble-desktop:1.18.0` | `swr.cn-north-1.myhuaweicloud.com/shanyou/kasmweb-ubuntu-noble-desktop:1.18.0` |
| `kasmweb/ubuntu-noble-desktop:1.18.0-rolling-daily` | `swr.cn-north-1.myhuaweicloud.com/shanyou/kasmweb-ubuntu-noble-desktop:1.18.0-rolling-daily` |
| `kindest/node:v1.35.0` | `swr.cn-north-1.myhuaweicloud.com/shanyou/kindest-node:v1.35.0` |
| `kiwigrid/k8s-sidecar:2.5.0` | `swr.cn-north-1.myhuaweicloud.com/shanyou/kiwigrid-k8s-sidecar:2.5.0` |
| `langgenius/dify-api:1.14.0` | `swr.cn-north-1.myhuaweicloud.com/shanyou/langgenius-dify-api:1.14.0` |
| `langgenius/dify-plugin-daemon:0.6.0-local` | `swr.cn-north-1.myhuaweicloud.com/shanyou/langgenius-dify-plugin-daemon:0.6.0-local` |
| `langgenius/dify-sandbox:0.2.15` | `swr.cn-north-1.myhuaweicloud.com/shanyou/langgenius-dify-sandbox:0.2.15` |
| `langgenius/dify-web:1.14.0` | `swr.cn-north-1.myhuaweicloud.com/shanyou/langgenius-dify-web:1.14.0` |
| `langgenius/qdrant:v1.8.3` | `swr.cn-north-1.myhuaweicloud.com/shanyou/langgenius-qdrant:v1.8.3` |
| `litellm/litellm:latest` | `swr.cn-north-1.myhuaweicloud.com/shanyou/litellm-litellm:latest` |
| `matrixorigin/matrixone:2.1.1` | `swr.cn-north-1.myhuaweicloud.com/shanyou/matrixorigin-matrixone:2.1.1` |
| `milvusdb/milvus:v2.6.3` | `swr.cn-north-1.myhuaweicloud.com/shanyou/milvusdb-milvus:v2.6.3` |
| `minio/minio:RELEASE.2023-03-20T20-16-18Z` | `swr.cn-north-1.myhuaweicloud.com/shanyou/minio-minio:RELEASE.2023-03-20T20-16-18Z` |
| `mongo:4.4.10` | `swr.cn-north-1.myhuaweicloud.com/shanyou/mongo:4.4.10` |
| `mysql:8.0` | `swr.cn-north-1.myhuaweicloud.com/shanyou/mysql:8.0` |
| `mysql:latest` | `swr.cn-north-1.myhuaweicloud.com/shanyou/mysql:latest` |
| `nginx:1.21.1` | `swr.cn-north-1.myhuaweicloud.com/shanyou/nginx:1.21.1` |
| `nginx:latest` | `swr.cn-north-1.myhuaweicloud.com/shanyou/nginx:latest` |
| `nginxinc/nginx-unprivileged:1.27` | `swr.cn-north-1.myhuaweicloud.com/shanyou/nginxinc-nginx-unprivileged:1.27` |
| `nginxinc/nginx-unprivileged:latest` | `swr.cn-north-1.myhuaweicloud.com/shanyou/nginxinc-nginx-unprivileged:latest` |
| `oceanbase/oceanbase-ce:4.3.5-lts` | `swr.cn-north-1.myhuaweicloud.com/shanyou/oceanbase-oceanbase-ce:4.3.5-lts` |
| `oceanbase/seekdb:latest` | `swr.cn-north-1.myhuaweicloud.com/shanyou/oceanbase-seekdb:latest` |
| `opengauss/opengauss:7.0.0-RC1` | `swr.cn-north-1.myhuaweicloud.com/shanyou/opengauss-opengauss:7.0.0-RC1` |
| `opensearchproject/opensearch-dashboards:latest` | `swr.cn-north-1.myhuaweicloud.com/shanyou/opensearchproject-opensearch-dashboards:latest` |
| `opensearchproject/opensearch:latest` | `swr.cn-north-1.myhuaweicloud.com/shanyou/opensearchproject-opensearch:latest` |
| `pgvector/pgvector:pg16` | `swr.cn-north-1.myhuaweicloud.com/shanyou/pgvector-pgvector:pg16` |
| `postgres:14` | `swr.cn-north-1.myhuaweicloud.com/shanyou/postgres:14` |
| `postgres:15-alpine` | `swr.cn-north-1.myhuaweicloud.com/shanyou/postgres:15-alpine` |
| `postgres:18-alpine` | `swr.cn-north-1.myhuaweicloud.com/shanyou/postgres:18-alpine` |
| `quay.io/coreos/etcd:v3.5.5` | `swr.cn-north-1.myhuaweicloud.com/shanyou/quay-io-coreos-etcd:v3.5.5` |
| `quay.io/minio/mc:RELEASE.2024-11-21T17-21-54Z` | `swr.cn-north-1.myhuaweicloud.com/shanyou/quay-io-minio-mc:RELEASE.2024-11-21T17-21-54Z` |
| `quay.io/minio/minio:RELEASE.2024-12-18T13-15-44Z` | `swr.cn-north-1.myhuaweicloud.com/shanyou/quay-io-minio-minio:RELEASE.2024-12-18T13-15-44Z` |
| `rancher/local-path-provisioner:v0.0.22` | `swr.cn-north-1.myhuaweicloud.com/shanyou/rancher-local-path-provisioner:v0.0.22` |
| `redis:6-alpine` | `swr.cn-north-1.myhuaweicloud.com/shanyou/redis:6-alpine` |
| `redis:8-alpine` | `swr.cn-north-1.myhuaweicloud.com/shanyou/redis:8-alpine` |
| `registry.k8s.io/ingress-nginx/controller:v0.48.1` | `swr.cn-north-1.myhuaweicloud.com/shanyou/registry-k8s-io-ingress-nginx-controller:v0.48.1` |
| `semitechnologies/weaviate:1.27.0` | `swr.cn-north-1.myhuaweicloud.com/shanyou/semitechnologies-weaviate:1.27.0` |
| `tensorchord/pgvecto-rs:pg16-v0.3.0` | `swr.cn-north-1.myhuaweicloud.com/shanyou/tensorchord-pgvecto-rs:pg16-v0.3.0` |
| `tmate/tmate-ssh-server:latest` | `swr.cn-north-1.myhuaweicloud.com/shanyou/tmate-tmate-ssh-server:latest` |
| `tomcat:9.0.118-jdk8-temurin-noble` | `swr.cn-north-1.myhuaweicloud.com/shanyou/tomcat:9.0.118-jdk8-temurin-noble` |
| `ubuntu/squid:latest` | `swr.cn-north-1.myhuaweicloud.com/shanyou/ubuntu-squid:latest` |
| `ubuntu:18.04` | `swr.cn-north-1.myhuaweicloud.com/shanyou/ubuntu:18.04` |
| `ubuntu:20.04` | `swr.cn-north-1.myhuaweicloud.com/shanyou/ubuntu:20.04` |
| `ubuntu:22.04` | `swr.cn-north-1.myhuaweicloud.com/shanyou/ubuntu:22.04` |
| `ubuntu:24.04` | `swr.cn-north-1.myhuaweicloud.com/shanyou/ubuntu:24.04` |
| `ubuntu:26.04` | `swr.cn-north-1.myhuaweicloud.com/shanyou/ubuntu:26.04` |
| `vectorim/element-web:latest` | `swr.cn-north-1.myhuaweicloud.com/shanyou/vectorim-element-web:latest` |
| `weishaw/sub2api:latest` | `swr.cn-north-1.myhuaweicloud.com/shanyou/weishaw-sub2api:latest` |
