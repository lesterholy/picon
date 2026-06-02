# Picon

[English](README.md)

Picon 是一个本地 macOS 菜单栏图床工具。它会检测剪贴板中的图片，在菜单栏弹窗中显示待上传缩略图；只有点击缩略图后才会上传，并把 Markdown 图片链接复制到剪贴板，例如：

```md
![](https://images.example.com/ob/example.png)
```

## 功能

- 适配 Apple Silicon，支持 macOS 11 及以上版本。
- 检测剪贴板图片，但默认不自动上传，需要点击确认。
- 支持多个存储 profile，并设置一个默认 profile。
- 支持本地文件夹、七牛云、S3 兼容服务、Cloudflare R2、MinIO、AWS S3、腾讯 COS。
- 支持复制 profile、测试配置、开机自启动。
- 支持批量上传本地文件夹图片，并保留相对路径生成对象名。
- 凭据保存在 macOS Keychain，不写入应用配置 JSON。

## 环境要求

- Apple Silicon Mac
- macOS 11+
- Swift command line tools

当前仓库使用 Swift Package Manager 构建。生成的 app bundle 未签名，也未 notarize。

## 本地运行

```sh
swift run Picon
```

或：

```sh
./scripts/run-local.sh
```

启动后在菜单栏找到 Picon 图标。复制截图或图片文件，打开 Picon，点击待上传图片行，即可用默认 profile 上传并复制 Markdown URL。

## 构建 App Bundle

```sh
./scripts/package-local-app.sh
open build/Picon.app
```

该命令会把 release 二进制打包为 `build/Picon.app`，用于本机运行。

## 存储 Profile

打开 `Settings` 添加 profile。选择一个 profile 后配置公开 URL 前缀、命名模板和凭据，然后点击 `Set Default` 设为默认。`Duplicate` 可以复制现有 profile。每个 profile 都有 `Test Configuration` 按钮。

Cloudflare R2 的 `Endpoint` 应保持为 bucket API endpoint。不同文件夹通过 `Naming Template` 控制，例如：

```text
blog/{uuid}.{ext}
avatar/{uuid}.{ext}
```

## 批量上传

在弹窗中点击 `Upload Folder...`，可以递归上传文件夹内的图片。批量模板支持：

```text
{relativePath}, {relativeDir}, {filename}, {hash}, {index}, {ext}
```

示例：

```text
ob/{relativePath}-{hash}.{ext}
```

## 验证

```sh
swift build
swift run PiconCheck
./scripts/package-local-app.sh
```

`PiconCheck` 会验证默认 profile、对象名模板、本地上传写入、请求签名、公开 URL 生成和 Markdown 格式。

## 数据与安全

运行时数据位于 `~/Library/Application Support/Picon/`。云存储凭据保存在 macOS Keychain。不要提交本地构建产物、应用数据、真实 bucket、真实 endpoint、access key 或生成的 history 文件。

## 发布

推送符合 `v*` 的 tag 后，GitHub Actions 会自动创建 release：

```sh
git tag v0.1.0
git push origin v0.1.0
```

workflow 会构建、运行 `PiconCheck`、打包 `Picon.app`、生成 zip，并上传 checksum。

## 开源协议

MIT License。详见 [LICENSE](LICENSE)。
