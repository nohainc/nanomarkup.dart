# Releasing

## One-time pub.dev bootstrap

This bootstrap was completed for `nanomarkup` before the stable `1.0.0`
release. Manual publishing is now disabled; stable releases use the protected
`pub.dev` GitHub environment and pub.dev OIDC trusted publishing.

Pub.dev only permits automated publishing for an existing package. Before the
first stable release:

1. From the reviewed release commit, create a temporary clean worktree and set
   `pubspec.yaml`, `lib/src/version.dart`, and `CHANGELOG.md` to
   `1.0.0-rc.1`. Do not merge those temporary version changes.
2. Run formatting, analysis, VM tests, browser tests, conformance, `dart doc`,
   the example, and `dart pub publish --dry-run`.
3. Publish the prerelease manually with maintainer authentication using
   `dart pub publish`. Verify it appears as `1.0.0-rc.1`.
4. In the package's pub.dev Admin tab, enable publishing from GitHub Actions for
   repository `nohainc/nanomarkup.dart` and tag pattern `v{{version}}`.
5. Protect the GitHub `pub.dev` environment with owner approval and protect
   release tags.

## Stable releases

1. Confirm `spec` points to the intended immutable specification tag and
   `specVersion` names that exact version.
2. Set `version` and `pubspec.yaml` to the same release and update the changelog.
3. Run every CI command locally, including conformance, Chrome, documentation,
   and the pub dry run.
4. Merge the reviewed release changes only after every required check passes.
5. Create and push an annotated `vX.Y.Z` tag on that exact commit. The tag must
   match both version sources.
6. Approve the protected `pub.dev` environment only after the workflow repeats
   all verification successfully.
7. Verify the pub.dev package, API docs, GitHub release, clean package install,
   validator, Dart web compile, and Flutter consumption.

Published tags and package versions are immutable. Correct defects with a new
version; never replace an existing artifact or tag.
