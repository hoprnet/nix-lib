#!/usr/bin/env bash
#
# Create a release tag for the commits pushed to main:
#
#   vX.Y.Z   immutable release tag
#   vX       moving alias to the latest release of that major
#
# The bump level is derived from the conventional commit messages in the
# range: feat! / BREAKING CHANGE -> major, feat -> minor, anything else
# -> patch.
#
# Usage: release-tags.sh <base_sha> <head_sha> [--dry-run]

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

BASE_SHA="${1:?usage: release-tags.sh <base_sha> <head_sha> [--dry-run]}"
HEAD_SHA="${2:?usage: release-tags.sh <base_sha> <head_sha> [--dry-run]}"
DRY_RUN="${3:-}"

# On the first push to a branch (or a force push) the "before" commit is
# unknown; fall back to the head commit's parent.
if ! git cat-file -e "${BASE_SHA}^{commit}" 2>/dev/null; then
  BASE_SHA="$(git rev-parse "${HEAD_SHA}~1")"
fi

# A workflow re-run for an already-released merge must not mint a
# duplicate release at the same commit.
if git tag --points-at "$HEAD_SHA" -l 'v*.*.*' | grep -q .; then
  echo "Already released at ${HEAD_SHA}, skipping"
  exit 0
fi

current="$(git tag -l 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1 || true)"
current="${current#v}"

bump="patch"
while read -r sha; do
  subject="$(git log -1 --format=%s "$sha")"
  body="$(git log -1 --format=%b "$sha")"
  if [[ $subject =~ ^([a-z]+)(\(([^\)]+)\))?(!)?: ]]; then
    type="${BASH_REMATCH[1]}"
    bang="${BASH_REMATCH[4]}"
  else
    continue
  fi
  if [[ -n $bang || $body == *"BREAKING CHANGE"* ]]; then
    bump="major"
  elif [[ $type == "feat" && $bump != "major" ]]; then
    bump="minor"
  fi
done < <(git log --format=%H "${BASE_SHA}..${HEAD_SHA}")

if [[ -z $current ]]; then
  version="1.0.0"
else
  IFS=. read -r major minor patch <<<"$current"
  case "$bump" in
  major) version="$((major + 1)).0.0" ;;
  minor) version="${major}.$((minor + 1)).0" ;;
  patch) version="${major}.${minor}.$((patch + 1))" ;;
  esac
fi

release_tag="v${version}"
alias_tag="v${version%%.*}"

if [[ $DRY_RUN == "--dry-run" ]]; then
  echo "[dry-run] would create ${release_tag} (${bump}) and move ${alias_tag} to ${HEAD_SHA}"
  exit 0
fi

echo "Creating ${release_tag} and moving ${alias_tag} to ${HEAD_SHA}"
git tag -a "$release_tag" -m "$release_tag" "$HEAD_SHA"
git tag -f "$alias_tag" "$HEAD_SHA"
# Atomic so a failed push cannot publish the release tag while leaving
# the alias on the previous release.
git push --atomic origin "refs/tags/${release_tag}" "+refs/tags/${alias_tag}"
