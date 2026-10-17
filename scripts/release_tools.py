#!/usr/bin/env python3
"""Prepare reviewed release files without including the local development tree."""
import argparse
import hashlib
from pathlib import Path
import plistlib
import re
import shutil
import stat
import tempfile
import zipfile


PUBLIC_DIRS = ("Sources", "Tests", "Resources", "scripts", "tools", "docs", ".github")
PUBLIC_FILES = ("Package.swift", "README.md", "LICENSE", "NOTICE.md", "CHANGELOG.md",
                "CONTRIBUTING.md", ".gitignore", ".gitattributes")
REQUIRED_FILES = ("Package.swift", "LICENSE", "README.md", "Resources/Info.plist",
                  "Sources/EncoBar/main.swift", "scripts/build.sh")
PRIVATE_PATTERNS = (
    re.compile(r"(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}"),
    re.compile(r"caseBatteryHistory\.[0-9a-fA-F]{64}"),
    re.compile(r"-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----"),
    re.compile(r"(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})"),
)


def version_for(root):
    with (root / "Resources/Info.plist").open("rb") as stream:
        version = plistlib.load(stream)["CFBundleShortVersionString"]
    if not isinstance(version, str) or not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Invalid product version")
    return version


def audit_text(content, name):
    homes = re.findall(re.escape("/" + "Users/") + r"([^/\"'\n]+)/", content)
    if any(home != "Example User" for home in homes) or any(
            pattern.search(content) for pattern in PRIVATE_PATTERNS):
        raise ValueError(f"Possible private data in {name}; inspect before publishing")


def source_files(root):
    found = []

    def visit(path):
        relative = path.relative_to(root)
        if path.is_symlink():
            raise ValueError(f"Public source contains symlink: {relative}")
        if path.name in (".DS_Store", "__pycache__") or path.suffix in (".log", ".pyc", ".pyo"):
            return
        if path.name.startswith(".env") or path.suffix.lower() in (
                ".p12", ".p8", ".pem", ".key", ".mobileprovision"):
            raise ValueError(f"Potential secret file: {relative}")
        if path.is_dir():
            for child in sorted(path.iterdir()):
                visit(child)
        elif path.is_file():
            if path.suffix.lower() not in (".icns", ".png"):
                try:
                    content = path.read_text(encoding="utf-8")
                except UnicodeDecodeError as error:
                    raise ValueError(f"Unexpected binary source: {relative}") from error
                audit_text(content, relative)
            found.append(relative)

    for name in PUBLIC_FILES + PUBLIC_DIRS:
        path = root / name
        if path.exists() or path.is_symlink():
            visit(path)
    missing = set(REQUIRED_FILES) - {str(path) for path in found}
    if missing:
        raise ValueError(f"Missing source files: {sorted(missing)}")
    return sorted(found)


def make_source_zip(root, destination, version):
    files = source_files(root)
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for relative in files:
            path = root / relative
            info = zipfile.ZipInfo(f"EncoBar-{version}/{relative}", (2020, 1, 1, 0, 0, 0))
            info.create_system = 3
            mode = 0o755 if path.stat().st_mode & stat.S_IXUSR else 0o644
            info.external_attr = (stat.S_IFREG | mode) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, path.read_bytes())


def payload_names(version):
    return {f"EncoBar-{version}-macos-arm64.pkg", f"EncoBar-{version}-source.zip",
            "RELEASE_NOTES.md", "INSTALL.txt"}


def digest(path):
    with path.open("rb") as stream:
        return hashlib.sha256(stream.read()).hexdigest()


def prepare(root):
    version = version_for(root)
    # The packaged executables should not embed the build machine's home path.
    app = root / "dist/app/EncoBar.app/Contents"
    for relative in ("MacOS/EncoBar", "Helpers/EncoBar Uninstaller.app/Contents/MacOS/EncoBarUninstaller"):
        executable = app / relative
        if executable.exists() and b"/Users/" in executable.read_bytes():
            raise ValueError(f"Possible private build path in {relative}")
    parent = root / "dist/releases"
    parent.mkdir(parents=True, exist_ok=True)
    destination = parent / f"v{version}"
    with tempfile.TemporaryDirectory(prefix=".prepare-", dir=parent) as temporary:
        stage = Path(temporary)
        make_source_zip(root, stage / f"EncoBar-{version}-source.zip", version)
        shutil.copyfile(root / f"dist/packages/EncoBar-{version}.pkg",
                        stage / f"EncoBar-{version}-macos-arm64.pkg")
        notes = (root / f"docs/releases/{version}.md").read_text(encoding="utf-8")
        audit_text(notes, "release notes")
        (stage / "RELEASE_NOTES.md").write_text(notes, encoding="utf-8")
        (stage / "INSTALL.txt").write_text(
            "EncoBar " + version + " — Apple Silicon / macOS 13+\n\n"
            "安装：双击 PKG，安装到当前用户的 Applications 目录。首次启动允许蓝牙。\n"
            "卸载：菜单栏面板的更多菜单 → 卸载 EncoBar，然后确认。\n"
            "App 使用 ad-hoc 签名；PKG 未签名、未公证。其他 Mac 可能被 Gatekeeper 阻止。\n"
            "公开分发前请完成 Developer ID 签名、公证和另一台 Mac 的验证。\n"
            "完整说明见源码中的 docs/user-guide.md。\n"
            "校验：在本目录执行 shasum -a 256 -c SHA256SUMS.txt。\n",
            encoding="utf-8")
        manifest = "".join(f"{digest(stage / name)}  {name}\n" for name in sorted(payload_names(version)))
        (stage / "SHA256SUMS.txt").write_text(manifest, encoding="utf-8")
        verify_directory(stage, version)
        if destination.exists():
            shutil.rmtree(destination)
        shutil.copytree(stage, destination)
    return destination


def verify_directory(directory, version):
    expected = payload_names(version)
    if {p.name for p in directory.iterdir()} != expected | {"SHA256SUMS.txt"}:
        raise ValueError("Unexpected release file set")
    entries = {}
    for line in (directory / "SHA256SUMS.txt").read_text(encoding="utf-8").splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  ([^/\\]+)", line)
        if not match or match[2] in entries:
            raise ValueError("Invalid checksum manifest")
        entries[match[2]] = match[1]
    if set(entries) != expected:
        raise ValueError("Unexpected checksum file set")
    for name, checksum in entries.items():
        path = directory / name
        if path.is_symlink() or not path.is_file() or digest(path) != checksum:
            raise ValueError(f"Release checksum mismatch: {name}")
    with zipfile.ZipFile(directory / f"EncoBar-{version}-source.zip") as archive:
        names = archive.namelist()
        if len(names) != len(set(names)) or archive.testzip():
            raise ValueError("Invalid source ZIP")
        prefix = f"EncoBar-{version}/"
        for info in archive.infolist():
            name = info.filename
            if (not name.startswith(prefix) or ".." in Path(name).parts or "\\" in name
                    or stat.S_ISLNK(info.external_attr >> 16)):
                raise ValueError("Unsafe source ZIP path")
        # Reapply the allowlist and privacy scan to the distributed bytes.
        with tempfile.TemporaryDirectory(prefix="EncoBar verify ") as temporary:
            archive.extractall(temporary)
            extracted = Path(temporary) / f"EncoBar-{version}"
            actual = {name[len(prefix):] for name in names}
            if actual != {str(p) for p in source_files(extracted)}:
                raise ValueError("Unexpected files in source ZIP")


def verify(root):
    version = version_for(root)
    verify_directory(root / f"dist/releases/v{version}", version)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify", action="store_true", help="verify the current version's release")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    if args.verify:
        verify(root)
        print("Release checksums and source archive verified")
    else:
        print(prepare(root))


if __name__ == "__main__":
    main()
