# Picon

[简体中文](README.zh-CN.md)

Picon is a local macOS menu bar helper for image hosting. It detects copied images, shows them as pending thumbnails, uploads only after you click a thumbnail, and copies a Markdown image link such as:

```md
![](https://images.example.com/ob/example.png)
```

## Features

- Menu bar app for Apple Silicon Macs running macOS 11 or later.
- Clipboard image detection with click-to-upload confirmation.
- Multiple storage profiles with one default profile.
- Local Folder, Qiniu, S3-compatible services, Cloudflare R2, MinIO, AWS S3, and Tencent COS support.
- Profile duplication, configuration testing, and launch-at-login.
- Batch folder upload with relative-path aware object keys.
- Credentials stored in macOS Keychain, not in the app settings JSON.

## Requirements

- Apple Silicon Mac
- macOS 11+
- Swift command line tools

This repository currently builds with Swift Package Manager. The generated app bundle is unsigned and not notarized.

## Run Locally

```sh
swift run Picon
```

Or:

```sh
./scripts/run-local.sh
```

After launch, use the menu bar icon. Copy a screenshot or image file, open Picon, then click the pending image row to upload with the default profile and copy the Markdown URL.

## Build an App Bundle

```sh
./scripts/package-local-app.sh
open build/Picon.app
```

This creates `build/Picon.app` from the release binary for local use.

## Storage Profiles

Open `Settings` to add profiles. Select a profile, configure its public URL prefix and naming template, save credentials, then click `Set Default`. Use `Duplicate` to copy an existing profile. Each profile has a `Test Configuration` button.

For Cloudflare R2, keep `Endpoint` as the bucket API endpoint and put folder prefixes in `Naming Template`, for example:

```text
blog/{uuid}.{ext}
avatar/{uuid}.{ext}
```

## Batch Upload

Click `Upload Folder...` in the popover to upload all images in a folder recursively. Batch templates can use:

```text
{relativePath}, {relativeDir}, {filename}, {hash}, {index}, {ext}
```

Example:

```text
ob/{relativePath}-{hash}.{ext}
```

## Verify

```sh
swift build
swift run PiconCheck
./scripts/package-local-app.sh
```

`PiconCheck` validates profile resolution, object-key templates, local upload writes, request signing, public URL generation, and Markdown formatting.

## Data and Security

Runtime data is stored under `~/Library/Application Support/Picon/`. Provider credentials are stored in macOS Keychain. Do not commit local build artifacts, app data, real bucket names, endpoints, access keys, or generated history files.

## Release

GitHub Actions publishes a release when a tag matching `v*` is pushed:

```sh
git tag v0.1.0
git push origin v0.1.0
```

The workflow builds, runs `PiconCheck`, packages `Picon.app`, creates a zip archive, and uploads checksums.

## License

MIT License. See [LICENSE](LICENSE).
