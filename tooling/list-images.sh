#!/usr/bin/env bash
set -euo pipefail

ORG="${1:-CommunityMaintained}"
IMAGE="${2:-tubeless}"
ORG_LOWER=$(echo "$ORG" | tr '[:upper:]' '[:lower:]')
TOKEN=$(gh auth token)

echo "Fetching versions for ${ORG}/${IMAGE}..."
VERSIONS=$(gh api --paginate /orgs/$ORG/packages/container/$IMAGE/versions)

echo "$VERSIONS" | jq -c '.[] | select(.metadata.container.tags | length > 0)' | while read -r version; do
  TAG=$(echo "$version" | jq -r '.metadata.container.tags[0]')
  PARENT_ID=$(echo "$version" | jq -r '.id')
  PARENT_DIGEST=$(echo "$version" | jq -r '.name')
  UPDATED=$(echo "$version" | jq -r '.updated_at')

  echo ""
  echo "┌─ $TAG"
  echo "│  id:      $PARENT_ID"
  echo "│  digest:  $PARENT_DIGEST"
  echo "│  updated: $UPDATED"

  MANIFEST=$(curl -sf \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/vnd.oci.image.index.v1+json" \
    "https://ghcr.io/v2/${ORG_LOWER}/${IMAGE}/manifests/${TAG}" || echo "{}")

  if echo "$MANIFEST" | jq -e '.manifests' > /dev/null 2>&1; then
    echo "$MANIFEST" | jq -c '.manifests[]' | while read -r child; do
      CHILD_DIGEST=$(echo "$child" | jq -r '.digest')
      PLATFORM=$(echo "$child" | jq -r '.platform | "\(.os)/\(.architecture)\(if .variant then "/"+.variant else "" end)"')
      CHILD_ID=$(echo "$VERSIONS" | jq -r --arg d "$CHILD_DIGEST" '.[] | select(.name == $d) | .id')
      SIZE=$(echo "$child" | jq -r '.size // "unknown"')

      echo "│"
      echo "├── $PLATFORM"
      echo "│   id:     ${CHILD_ID:-<not in package list>}"
      echo "│   digest: $CHILD_DIGEST"
      echo "│   size:   $SIZE bytes"
    done
  else
    echo "│  (single-arch — no manifest index)"
  fi
done

echo ""
