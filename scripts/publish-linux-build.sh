#!/usr/bin/env bash
#
# Publish a Linux ffmpeg static build as a GitHub Release on this fork so CI does
# not depend on johnvansickle.com at runtime. Requires `gh` authenticated with
# write access to suno-ai/setup-ffmpeg.
#
# Usage:
#   scripts/publish-linux-build.sh            # publish current upstream release
#   scripts/publish-linux-build.sh 7.0.2      # publish a specific version
#   ARCHES="amd64 arm64" scripts/publish-linux-build.sh
#
set -euo pipefail

REPO="${REPO:-suno-ai/setup-ffmpeg}"
ARCHES="${ARCHES:-amd64}"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

VERSION="${1:-}"
PINNED=1
if [[ -z "$VERSION" ]]; then
  PINNED=0
  echo "Resolving current upstream release version..."
  VERSION="$(curl -fsSL https://johnvansickle.com/ffmpeg/release-readme.txt \
    | sed -n 's/^ *version: *//p' | head -1)"
fi
if [[ -z "$VERSION" ]]; then
  echo "ERROR: could not determine ffmpeg version" >&2
  exit 1
fi

TAG="ffmpeg-${VERSION}"
echo "Publishing ${TAG} to ${REPO} for arch(es): ${ARCHES}"

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "ERROR: release ${TAG} already exists on ${REPO}." >&2
  echo "Delete it first (gh release delete ${TAG} --repo ${REPO}) or bump the version." >&2
  exit 1
fi

ASSETS=()
for ARCH in $ARCHES; do
  # johnvansickle only labels the *latest* release as "release-<arch>". A pinned
  # version has a versioned filename under releases/ while it is current and
  # under old-releases/ after that. Never fall back to "release-<arch>" for a
  # pinned version: that is whatever is current, not the requested build.
  OUT="${WORKDIR}/ffmpeg-${VERSION}-${ARCH}-static.tar.xz"
  NAME="ffmpeg-${VERSION}-${ARCH}-static.tar.xz"
  if [[ "$PINNED" == 1 ]]; then
    URLS=(
      "https://johnvansickle.com/ffmpeg/releases/${NAME}"
      "https://johnvansickle.com/ffmpeg/old-releases/${NAME}"
    )
  else
    URLS=("https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-${ARCH}-static.tar.xz")
  fi
  echo "Downloading ${ARCH} build..."
  DOWNLOADED=0
  for URL in "${URLS[@]}"; do
    if curl -fL -o "$OUT" "$URL"; then
      DOWNLOADED=1
      break
    fi
  done
  if [[ "$DOWNLOADED" != 1 ]]; then
    echo "ERROR: no ${ARCH} build of ffmpeg ${VERSION} found on johnvansickle.com" >&2
    exit 1
  fi
  # Sanity check: johnvansickle tarballs unpack into ffmpeg-<version>-<arch>-static/,
  # so the top-level directory must match the version we are about to tag.
  # (awk reads the whole listing, so tar never gets SIGPIPE under pipefail.)
  TOP="$(tar -tf "$OUT" | awk 'NR == 1')"
  if [[ "${TOP%%/*}" != "ffmpeg-${VERSION}-${ARCH}-static" ]]; then
    echo "ERROR: ${ARCH} archive contains ${TOP%%/*}, expected ffmpeg-${VERSION}-${ARCH}-static" >&2
    exit 1
  fi
  ASSETS+=("$OUT")
done

echo "Creating release ${TAG}..."
gh release create "$TAG" \
  --repo "$REPO" \
  --title "ffmpeg ${VERSION}" \
  --notes "Static ffmpeg ${VERSION} (re-hosted johnvansickle.com build) for CI use by setup-ffmpeg." \
  "${ASSETS[@]}"

echo "Done. ${TAG} published with: ${ASSETS[*]##*/}"
