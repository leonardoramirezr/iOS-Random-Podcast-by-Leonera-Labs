#!/usr/bin/env bash
# Publish one build folder to the gh-pages branch.
#
# gh-pages is rewritten as a single orphan commit on every publish, so IPA files never
# accumulate in the git history. Each attempt rebuilds the site from the current remote
# state, so a concurrent publish from another build is kept. Only the push is retried.
#
# Usage: publish-pages.sh <tag> <build-dir>
set -euo pipefail

TAG="$1"
BUILD_DIR="$2"
BRANCH="gh-pages"
MAX_ATTEMPTS=5
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_DIR="$(git rev-parse --absolute-git-dir)"
export GIT_DIR

export GIT_AUTHOR_NAME="github-actions[bot]"
export GIT_AUTHOR_EMAIL="41898282+github-actions[bot]@users.noreply.github.com"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  # ls-remote must succeed: a network error must not be mistaken for a missing branch,
  # because that would overwrite the other builds with an empty site.
  remote_sha="$(git ls-remote --heads origin "$BRANCH" | cut -f1)"
  if [ -n "$remote_sha" ]; then
    git fetch --quiet origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH"
  fi

  stage="$(mktemp -d)"
  index_file="$(mktemp -u)"
  if [ -n "$remote_sha" ]; then
    git archive "refs/remotes/origin/$BRANCH" | tar -x -C "$stage"
  fi

  rm -rf "${stage:?}/$TAG"
  cp -R "$BUILD_DIR" "$stage/$TAG"
  python3 "$SCRIPT_DIR/site.py" prune "$stage" --keep-branch-builds 20
  python3 "$SCRIPT_DIR/site.py" index "$stage"

  # Build the single orphan commit in a temporary index, so the workspace index is untouched.
  (
    cd "$stage"
    GIT_INDEX_FILE="$index_file" git --work-tree=. add -A --force
    tree="$(GIT_INDEX_FILE="$index_file" git write-tree)"
    commit="$(git commit-tree "$tree" -m "Publish $TAG to $BRANCH")"
    echo "$commit" > "$stage.commit"
  )
  commit="$(cat "$stage.commit")"

  # --force-with-lease with an empty expected value means "the branch must not exist yet".
  if git push --quiet --force-with-lease="refs/heads/$BRANCH:$remote_sha" origin "$commit:refs/heads/$BRANCH"; then
    echo "Published $TAG to $BRANCH as $commit"
    rm -rf "$stage" "$stage.commit" "$index_file"
    exit 0
  fi

  echo "Push to $BRANCH was rejected (attempt $attempt of $MAX_ATTEMPTS). Rebuilding from the remote state..."
  rm -rf "$stage" "$stage.commit" "$index_file"
  sleep $((attempt * 3))
done

echo "::error::Could not publish $TAG to $BRANCH after $MAX_ATTEMPTS attempts"
exit 1
