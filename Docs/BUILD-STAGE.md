# RootHide build stage

The user authorized publishing this source to the public repository
`Tsangbaby/NoticeDeleteAnimation` and building a RootHide package on 2026-11-14.
This supersedes the source-only stopping point in PLAN.md/README.md. No device
installation, SSH connection or respring is authorized by this stage.

## Success / failure criteria

- Publish only a NEW `build/roothide-alpha1` branch, leaving existing branches untouched.
- Build actual Swift/ObjC arm64 + arm64e with Apple toolchain, deployment iOS15.0.
- Use `roothide/theos` commit `958fea4f779943505b15b93c88bb4db8d97b346d`
  with its pinned submodules and `THEOS_PACKAGE_SCHEME=roothide`.
- Execute the production Core XCTest; compile all production sources. Build failure
  must not yield a deliverable success claim.
- Gate DEB on exact metadata, `iphoneos-arm64e`, RootHide layout and install name,
  real dual Mach-O slices, minOS15, no encryption, signature load command, substrate
  linkage and no `/var/jb` dependencies. Package structure/signature metadata is not
  device runtime validation.
- Download the artifact corresponding to the final exact commit/run, verify SHA256
  against builder evidence, and deliver DEB with remaining device limitations.

Public repository publication uses the user-specified EASYBACKFORWECHAT environment
variable only in authenticated request headers. No credentials enter repo, logs,
workflow files or artifacts. Actions uses only its normal read-only GITHUB_TOKEN;
the long-lived credential is never sent to the runner.

If git transport is unreachable, GitHub REST git/contents APIs provide equivalent
new-branch source publication. Do not replace an existing branch or force-push.

The original source manifest and ZIP describe the prior source delivery. A fresh
manifest is created for this stage; no native build success is inferred from it.
