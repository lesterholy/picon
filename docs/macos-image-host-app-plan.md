# Plan: macOS Image Host Menu Bar App

**Generated**: 2026-06-01  
**Estimated Complexity**: High

## Overview

Build a native Apple Silicon macOS menu bar app for image hosting workflows. The app watches or reads the system clipboard, detects copied screenshots/local images, shows them as pending thumbnails, and uploads only when the user clicks a pending image. After upload succeeds, the app copies a Markdown image link such as `![](https://images.example.com/ob/pontbl.png)` back to the clipboard. Clicking an already uploaded thumbnail copies the same Markdown link again.

Recommended stack: Swift + SwiftUI for views, AppKit interop for menu bar and pasteboard control, Swift Package Manager where possible, Keychain for secrets, and `Application Support` for cached thumbnails/history. Use `NSStatusItem + NSPopover`, not SwiftUI-only `MenuBarExtra`, because the deployment target is macOS 11.0.

## Prerequisites

- Xcode 15+ or current stable Xcode with macOS SDK.
- Target architecture: `arm64`; Intel/universal build is out of scope for the first release.
- Minimum macOS deployment target: `11.0` Big Sur, to cover all Apple Silicon Macs.
- Test cloud accounts/buckets for Qiniu, Tencent COS, and one S3-compatible target such as AWS S3, Cloudflare R2, or MinIO.
- Apple Developer Program membership and App Store Connect access for Mac App Store submission.

## Reference Findings

- Apple supports menu bar status items through AppKit `NSStatusBar`/`NSStatusItem`; status items can show text or icons and attach menus/actions/custom views.
- `NSPasteboard.general` is the macOS clipboard surface; clipboard reading should be user-visible and avoid silently uploading sensitive images.
- Apple Keychain should store access keys, secret keys, tokens, and optional session credentials.
- Mac App Store distribution requires App Sandbox; outgoing cloud uploads require the network client entitlement.
- `LSMinimumSystemVersion` is the Info.plist key that declares the minimum macOS version shown by the App Store.
- Qiniu Kodo Objective-C SDK `8.9.x` supports OS X 10.15+, Swift Package Manager, and `import QiniuSDK`; Qiniu recommends not hardcoding AK/SK in clients and prefers server-issued upload tokens.
- Tencent COS has iOS/macOS SDK artifacts; the official docs list macOS manual integration from the `osx` package output and require `QCloudCore.framework` plus `QCloudCOSXML.framework`.
- AWS SDK for Swift supports macOS, Swift Package Manager, async/await, S3 client configuration, and credential resolvers.

## Sprint 1: Native Shell and Clipboard MVP

**Goal**: A runnable menu bar app that detects images from the clipboard and shows pending thumbnails locally.

**Demo/Validation**:
- Run from Xcode.
- Copy a screenshot or image file in Finder.
- Open the menu bar popover and see it listed under `Pending`.

### Task 1.1: Create Xcode Project

- **Location**: `Picon.xcodeproj`, `Picon/`
- **Description**: Create a macOS app target with SwiftUI lifecycle and AppKit bridge.
- **Dependencies**: None
- **Acceptance Criteria**:
  - App runs on Apple Silicon.
  - App has no Dock icon if `LSUIElement` is enabled.
  - Menu bar icon opens/closes a popover.
- **Validation**: `xcodebuild -scheme Picon -destination 'platform=macOS' build`

### Task 1.2: Clipboard Image Detection

- **Location**: `Picon/Clipboard/`
- **Description**: Implement `ClipboardMonitor` using `NSPasteboard.changeCount`, supporting PNG/TIFF data and file URLs for local images.
- **Dependencies**: Task 1.1
- **Acceptance Criteria**:
  - Detects screenshots copied from macOS screenshot tools.
  - Detects image files copied from Finder.
  - Does not upload automatically.
  - Creates a stable pending item whose eventual object key can be previewed before upload.
- **Validation**: Unit tests with fixture image data and manual pasteboard smoke test.

### Task 1.3: Pending UI

- **Location**: `Picon/UI/MenuPopoverView.swift`
- **Description**: Build a compact popover with `Pending`, `Uploaded`, provider menu, and settings entry. A click on a pending thumbnail starts upload; a click on an uploaded thumbnail copies its Markdown link.
- **Dependencies**: Task 1.2
- **Acceptance Criteria**:
  - Shows thumbnail, filename, dimensions, and status.
  - Supports remove/retry actions.
  - Shows the planned Markdown URL before upload when enough settings are available.
  - UI stays usable at narrow popover width.
- **Validation**: Manual screenshot review on light and dark mode.

## Sprint 2: Upload Core and Local History

**Goal**: Provider-independent upload pipeline with mocked provider and durable local history.

**Demo/Validation**:
- Click a pending image and upload it through a mock provider.
- Confirm upload success copies `![](url)` to clipboard.
- Quit/reopen app and see upload history.

### Task 2.1: Upload Domain Model

- **Location**: `Picon/Upload/`
- **Description**: Add `ImageItem`, `UploadResult`, `UploadProvider`, `UploadJob`, and `UploadQueue`.
- **Dependencies**: Sprint 1
- **Acceptance Criteria**:
  - Upload states: pending, uploading, uploaded, failed.
  - Concurrency limit defaults to 2.
  - Failures keep retry metadata.
- **Validation**: Unit tests for state transitions and retry behavior.

### Task 2.2: Local Storage

- **Location**: `Picon/Storage/`
- **Description**: Store metadata as JSON or SQLite in Application Support; cache thumbnails separately.
- **Dependencies**: Task 2.1
- **Acceptance Criteria**:
  - Secrets are never stored in this metadata file.
  - History loads on app launch.
  - Cache cleanup keeps latest N uploaded items.
- **Validation**: Unit tests using temporary directories.

### Task 2.3: Link Formatting

- **Location**: `Picon/Formatting/`
- **Description**: Add output formatting with Markdown as the first-release default. Keep plain URL, HTML, and custom template as internal extension points, not first-release UI.
- **Dependencies**: Task 2.1
- **Acceptance Criteria**:
  - Default copy format is Markdown: `![](https://...)`.
  - Clicking a pending thumbnail uploads and then copies Markdown.
  - Clicking an uploaded thumbnail copies Markdown again.
  - Copy success is visible in the menu UI.
- **Validation**: Unit tests for formatter edge cases.

### Task 2.4: Object Key Naming Rules

- **Location**: `Picon/Formatting/`, `Picon/Settings/`
- **Description**: Add configurable image naming rules for the uploaded object key.
- **Dependencies**: Task 2.1
- **Acceptance Criteria**:
  - Supports automatic UUID names.
  - Supports date-based folders such as `yyyy/MM/dd/{uuid}.png`.
  - Supports original filename when available.
  - Supports custom templates such as `ob/{slug}.png`, `ob/{yyyy}{MM}{dd}-{hash}.{ext}`.
  - Handles collisions by appending a suffix or regenerating.
- **Validation**: Unit tests for template expansion, sanitization, extension inference, and collision handling.

## Sprint 3: Provider Integrations

**Goal**: Real upload support for Qiniu first, then S3-compatible, then Tencent COS after integration spike.

**Demo/Validation**:
- Configure each implemented provider.
- Validate credentials/bucket/domain.
- Upload a real image and open the generated public URL.

### Task 3.1: Credential and Provider Settings

- **Location**: `Picon/Settings/`, `Picon/Security/`
- **Description**: Build settings UI for provider profiles, public URL prefix, Markdown preview, and object key naming rules. Store secrets in Keychain.
- **Dependencies**: Sprint 2
- **Acceptance Criteria**:
  - Multiple profiles per provider.
  - Secret fields are redacted.
  - User can preview the final Markdown URL before upload.
  - Validation does not log secrets.
- **Validation**: Unit tests with Keychain mock and manual settings smoke test.

### Task 3.2: Qiniu Provider

- **Location**: `Picon/Providers/Qiniu/`
- **Description**: Integrate Qiniu SDK or a small upload-token/direct-upload adapter. Support bucket, region/upload domain, access key, secret key, and public HTTP prefix.
- **Dependencies**: Task 3.1
- **Acceptance Criteria**:
  - Uploads PNG/JPEG images.
  - Supports deterministic object keys such as `yyyy/MM/dd/uuid.ext`.
  - Validates public URL after upload.
- **Validation**: Real test bucket smoke test plus mocked response tests.

### Task 3.3: S3-Compatible Provider

- **Location**: `Picon/Providers/S3/`
- **Description**: Use direct S3 SigV4 PUT requests with custom region, endpoint, bucket, access key, secret key, path-style option, and public base URL.
- **Dependencies**: Task 3.1
- **Acceptance Criteria**:
  - Works with AWS S3 and one S3-compatible endpoint.
  - Handles content type and cache-control metadata.
  - Allows custom CDN/public URL prefix.
- **Validation**: MinIO/R2/AWS smoke test and signer/config checks through `PiconCheck`.

### Task 3.4: Tencent COS Provider Spike

- **Location**: `Picon/Providers/TencentCOS/`
- **Description**: Verify whether official macOS framework artifacts build cleanly for arm64 and whether the Lite/Beacon-free variant is usable.
- **Dependencies**: Task 3.1
- **Acceptance Criteria**:
  - Decision record: official SDK vs REST adapter.
  - Minimal upload succeeds against a test bucket.
  - Bundle size and privacy implications are documented.
- **Validation**: Build on M1/M2 Mac and real bucket smoke test.

## Sprint 4: Product Polish and Local Distribution

**Goal**: Locally runnable macOS app with reliable UX, logs, and a simple launch path on the user's computer. Mac App Store submission is out of scope.

**Demo/Validation**:
- Run the app locally with `swift run Picon` or a generated local `.app` wrapper.
- Copy image, upload, click thumbnail, paste Markdown into editor.
- Reboot and verify launch-at-login if enabled.

### Task 4.1: UX Completion

- **Location**: `Picon/UI/`
- **Description**: Add drag-and-drop image upload, progress indicators, search/history, keyboard shortcuts, and error detail popovers.
- **Dependencies**: Sprint 3
- **Acceptance Criteria**:
  - Manual upload works without clipboard.
  - Clipboard-detected images always require a click before upload.
  - Failed uploads expose actionable errors.
  - History groups pending/uploaded like the reference app.
- **Validation**: Manual QA checklist.

### Task 4.2: Security and Privacy Pass

- **Location**: `Picon/Security/`, `Picon/Logging/`
- **Description**: Redact secrets, avoid automatic upload surprises, add clear setting for clipboard monitoring, implement credential deletion, and keep behavior compatible with App Sandbox.
- **Dependencies**: Sprint 3
- **Acceptance Criteria**:
  - No secrets appear in logs.
  - User can disable clipboard monitoring.
  - User can delete provider profiles and Keychain items.
  - App has only necessary entitlements: App Sandbox and outgoing network client.
- **Validation**: Log inspection and manual privacy test.

### Task 4.3: Local Packaging

- **Location**: `scripts/`, Xcode build settings
- **Description**: Add a local launch/build workflow for the user's Mac. Do not prioritize Mac App Store, notarization, or DMG distribution in the first release.
- **Dependencies**: Task 4.2
- **Acceptance Criteria**:
  - `swift build` succeeds.
  - `swift run Picon` launches the menu bar app.
  - A helper script documents the local launch command.
  - Optional `.app` wrapper can be added later when full Xcode is available.
- **Validation**: Launch on the user's Apple Silicon Mac, copy an image, click it in the menu bar popover, and paste the generated Markdown.

## Testing Strategy

- Unit tests: clipboard parsing, filename generation, URL formatting, provider config validation, upload state machine.
- Mock integration tests: provider adapters using local HTTP fixtures.
- Real smoke tests: one sandbox bucket per provider, gated by environment variables so CI can skip them safely.
- UI/manual QA: light/dark mode, small menu bar popover, offline errors, invalid credentials, large image upload, repeated clipboard changes, click-to-upload behavior.
- Security checks: no secret logs, Keychain-only secret storage, redacted crash/error reports.
- Local runtime checks: menu bar icon appears, clipboard-detected images enter pending state, pending click uploads, Markdown is copied, history persists.

## Potential Risks & Gotchas

- Clipboard privacy: automatic upload is out of scope for the first release; clicking a pending thumbnail is the upload confirmation.
- App Sandbox is not required for local-only distribution, but clipboard file URLs should still be tested with screenshots, Finder-copied images, drag-and-drop, and user-selected files.
- Tencent COS macOS SDK may add Objective-C/CocoaPods/manual framework complexity; spike before committing the provider architecture.
- Qiniu recommends server-issued upload tokens; a local-only tool can store AK/SK in Keychain, but this should be documented as a self-managed risk.
- S3-compatible services differ in endpoint style, region requirements, signatures, and public URL generation.
- Menu bar-only apps need careful settings access because users cannot rely on a normal Dock/window workflow.
- If local distribution later becomes public distribution, revisit signing, notarization, sandboxing, and update delivery.

## Open Product Decisions

1. Confirm whether the first release supports Qiniu only, or Qiniu plus S3-compatible storage.
2. Decide whether custom Markdown templates are user-facing in v1 or deferred behind the fixed `![](url)` format.
3. Decide whether provider credentials are entered directly in the Mac app or obtained from a small token service later.

## Rollback Plan

- Keep provider integrations behind `UploadProvider` so a broken provider can be disabled without affecting clipboard/history.
- Store provider profiles separately so migration can remove only one provider’s config.
- Release MVP with Qiniu-only if S3/COS integration slips; the rest of the app remains usable.
- If a cloud provider SDK blocks local builds, replace that provider with a REST adapter or defer it from v1.
