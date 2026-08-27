# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## What this repo is

`kai-packages` — Dart and Flutter code shared across Kai's apps (NovelGlide,
CherishCRM, …), as a [pub workspace](https://dart.dev/tools/pub/workspaces):
one lockfile, one CI run, so two packages here can never disagree about a
dependency version. Renamed from `dart-packages` once it stopped being
exclusively pure-Dart packages — `connectivity_status` is a real federated
Flutter plugin with native iOS/Android code, not just Dart.

## Org identifier: `net.kaiwu`, not `com.kai_wu`

**`net.kaiwu` is the current org identifier for anything with an Android
namespace/applicationId or an iOS bundle identifier in this repo — a
package's native code, and any app consuming one.** This is a standing rule,
confirmed against CherishCRM-Flutter's own `net.kaiwu.cherishcrm` (both its
Android `namespace`/`applicationId` and its iOS `PRODUCT_BUNDLE_IDENTIFIER`).

`com.kai_wu` is legacy — NovelGlide's own naming (`com.kai_wu.novelglide`),
never a house standard. It should not be copied into new native code just
because it is what an extraction's source app happened to use.

This has no Dart-side equivalent to enforce automatically (Dart package
names and pub.dev don't have an org-identifier concept), so it is a
convention to apply by hand whenever a package in this repo grows Android or
iOS native code — `connectivity_status` is the only one that has, so far.
