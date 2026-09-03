#!/usr/bin/env bash
# package_tags.sh — plan or create git tags for every package whose
# pubspec.yaml version has none yet.
#
# WHY THIS EXISTS SEPARATELY FROM tool/githooks/post-commit: every release
# commit on this repo's main so far is a GitHub squash-merge (one parent, a
# "(#N)" suffix) — created server-side when a PR merges, so no contributor's
# local hook ever ran for it. The hook only helps a direct local commit to
# main; this script is what the package-tag workflow runs on every push to
# main instead. It reads each package's CURRENT pubspec.yaml version rather
# than a commit subject, so it also covers a commit that bumps more than one
# package at once.
#
# It only ever ADDS a tag, never moves one — a moved tag would let one
# version number mean two different trees. A pubspec.yaml at or behind its
# package's newest existing tag is refused rather than guessed at: that
# means a reverted bump, not a new release.
#
# Usage: tool/package_tags.sh [--create]
#   (default)  print the plan, change nothing
#   --create   create the annotated tags at HEAD — does NOT push
# Writes `tags=<space separated>` to $GITHUB_OUTPUT when that's set.

set -uo pipefail
shopt -s nullglob

cd "$(git rev-parse --show-toplevel)" || exit 1

create=false
[ "${1:-}" = "--create" ] && create=true

# $1 <= $2, comparing dotted x.y.z numerically field by field.
ver_le() {
  [ "$1" = "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)" ]
}

errors=()
planned_tags=()
planned_meta=() # parallel to planned_tags: "package version"

for pubspec in packages/*/pubspec.yaml; do
  package=$(basename "$(dirname "$pubspec")")
  version=$(grep -m1 '^version:' "$pubspec" | sed 's/^version:[[:space:]]*//')

  # Only plain x.y.z. A pre-release would have to answer "does 1.0.0-rc.2
  # outrank 1.0.0?" and no package here has ever had one — refusing is
  # honest, guessing an order silently is not.
  if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    errors+=("$package: version \"$version\" is not x.y.z — refusing to guess how it orders")
    continue
  fi

  tag="${package}-v${version}"
  if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    echo "✔ $package $version — already tagged"
    continue
  fi

  newest=$(git tag -l "${package}-v*" | sed "s/^${package}-v//" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)

  if [ -n "$newest" ] && ver_le "$version" "$newest"; then
    errors+=("$package: pubspec.yaml is at $version, but ${package}-v${newest} is already tagged
      → bump packages/$package/pubspec.yaml above the newest tag")
    continue
  fi

  planned_tags+=("$tag")
  planned_meta+=("$package $version")
  echo "→ $package $version — ${newest:+newer than $newest, }will tag $tag"
done

if [ ${#errors[@]} -gt 0 ]; then
  echo
  echo "✘ ${#errors[@]} package(s) cannot be tagged:" >&2
  for e in "${errors[@]}"; do echo "  • $e" >&2; done
  exit 1
fi

if [ "$create" = true ]; then
  for i in "${!planned_tags[@]}"; do
    tag="${planned_tags[$i]}"
    read -r package version <<<"${planned_meta[$i]}"
    git tag -a "$tag" -m "$package $version

Created automatically by the package-tag workflow from pubspec.yaml."
    echo "  tagged $tag at $(git rev-parse --short HEAD)"
  done
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "tags=${planned_tags[*]}" >>"$GITHUB_OUTPUT"
fi

echo
if [ ${#planned_tags[@]} -gt 0 ]; then
  word=created
  [ "$create" = true ] || word="to create"
  echo "${#planned_tags[@]} tag(s) $word"
else
  echo "nothing to tag"
fi
