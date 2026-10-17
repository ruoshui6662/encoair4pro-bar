# GitHub 发布步骤

## 本地准备

1. 运行 `bash scripts/test.sh`，修改版本时只更新 `Resources/Info.plist` 的版本和构建号，并在 `docs/releases/版本号.md` 写本版说明。
2. 运行 `bash scripts/release.sh`，检查 `dist/releases/v版本号/`。
3. 发布文件包含 PKG、干净源码 ZIP、`SHA256SUMS.txt`、`INSTALL.txt` 和 `RELEASE_NOTES.md`。
4. 在发布目录运行 `shasum -a 256 -c SHA256SUMS.txt`，或运行 `python3 scripts/release_tools.py --verify`。

源码包采用明确的文件清单并检查本机路径、设备摘要及常见私钥文件。`.build/`、`dist/`、`.local/`、原始日志和历史截图不进入源码包。不要把整个工作目录连同隐藏缓存直接上传。

```text
dist/
  app/EncoBar.app
  packages/EncoBar-0.3.1.pkg
  releases/v0.3.1/
    EncoBar-0.3.1-macos-arm64.pkg
    EncoBar-0.3.1-source.zip
    SHA256SUMS.txt
    RELEASE_NOTES.md
    INSTALL.txt
```

源码 ZIP 解压后只有一个 `EncoBar-版本号/` 根目录，包含源码、资源、脚本、测试、文档及 `.github/`，没有安装包或编译缓存。`SHA256SUMS.txt` 覆盖同目录其余四个发布文件。App 资源中同时包含 MIT 许可证和参考资料声明。

## GitHub 仓库

源码仓库为 `https://github.com/ruoshui6662/encoair4pro-bar`。只提交源码、文档、测试和工作流；不要提交 `dist/` 中的本地构建产物、`.build/` 或 `.local/`。

## Releases

Release 标签必须与 `Resources/Info.plist` 中的应用版本一致，格式为 `v主版本.次版本.修订号`。例如当前应用版本 0.3.2 使用 `v0.3.2`。正文使用 `RELEASE_NOTES.md`，上传该版本目录中的安装包、源码 ZIP、安装说明和校验文件。先检查支持平台、签名状态、安装与卸载说明，再发布。

也可在远程仓库中先创建对应标签，再手动运行 **Release draft** 工作流，输入该标签。工作流检查标签与版本一致，运行测试及打包，生成草稿并上传产物；不会自动把草稿改成公开 Release。

**CI** 工作流在 main 的推送和 Pull Request 上运行测试、打包并保留构建产物，不发布 Release。远程工作流只有推送到自己的仓库后才能实际验证。

工作流采用 GitHub 提供的 [macos-26 arm64 runner](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)，要求 runner 的 SDK 包含 macOS 26 API。

## 分发签名

当前 App 为 ad-hoc 签名，PKG 未使用 Developer ID Installer 证书，尚未公证。校验和仅保证文件完整性，不能代替可信签名。当前工作流不包含证书、Apple ID 或公证凭据；正式面向更多用户分发前，应完成证书签名、公证和另一台 Mac 的安装验证。
