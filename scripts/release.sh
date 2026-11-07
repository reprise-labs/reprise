#!/bin/bash
# One-command release, no manual steps:
#
#   scripts/release.sh <version> "<release notes>"            # real release
#   scripts/release.sh --dry-run <version> "<release notes>"   # every check + a test signature,
#                                                              # but no install, push or release
#
# Bumps Resources/VERSION, builds + installs via install.sh, zips, signs with Sparkle's
# sign_update, creates the GitHub release with the zip, and only then adds the appcast item
# (publish_release.sh) — in that order, so the appcast never points at a zip that isn't
# there yet.
#
# Signing runs unattended: the Sparkle key's Keychain item on the Mac mini was set to
# "Always Allow" for sign_update on 7-11-2026. Should that ever be reset, sign_update waits
# on a Keychain prompt; this script gives up after 60 s instead of hanging forever.
#
# Pushing and releasing go through the gh account "reprise-labs" (the active gh account on
# this Mac has no write access to reprise-labs/reprise), without switching the active
# account. Release commits are authored as reprise-labs' no-reply address, same as the
# appcast commits before the move to the Mac mini.
set -euo pipefail
cd "$(dirname "$0")/.."

DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then DRY_RUN=1; shift; fi
VERSION="${1:-}"
NOTES="${2:-}"
if [ -z "$VERSION" ] || [ -z "$NOTES" ]; then
    echo "Usage: $0 [--dry-run] <version, e.g. 1.6.76> \"<release notes>\""
    exit 1
fi

REPO="reprise-labs/reprise"
SIGN_UPDATE="./.build/artifacts/sparkle/Sparkle/bin/sign_update"
fail() { echo "❌ $*"; exit 1; }

# --- checks: everything that can fail is checked before anything is changed ---
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Version must look like 1.6.76, got '$VERSION'."
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || fail "Not on main."
git diff --quiet && git diff --cached --quiet || fail "Uncommitted changes — commit them first."

TOKEN=$(gh auth token --user reprise-labs 2>/dev/null) || fail "gh has no login for reprise-labs (gh auth login)."
export GH_TOKEN="$TOKEN"
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0=
export GIT_CONFIG_KEY_1=credential.helper
export GIT_CONFIG_VALUE_1='!f(){ echo username=x-access-token; echo "password=$GH_TOKEN"; }; f'
export GIT_AUTHOR_NAME="reprise-labs" GIT_COMMITTER_NAME="reprise-labs"
export GIT_AUTHOR_EMAIL="334611916+reprise-labs@users.noreply.github.com"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

[ "$(gh api "repos/$REPO" -q .permissions.push)" = "true" ] || fail "reprise-labs has no push access to $REPO."
git fetch -q origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] \
    || git merge-base --is-ancestor origin/main HEAD || fail "main is behind origin/main — pull first."
gh release view "$VERSION" --repo "$REPO" >/dev/null 2>&1 && fail "Release $VERSION already exists."
grep -q "<sparkle:version>$VERSION</sparkle:version>" appcast.xml && fail "appcast.xml already has $VERSION."

# install.sh restarts Reprise; never in the middle of a recording. Metadata checks
# (--skip-download) are harmless, a real download is not.
if pgrep -fl yt-dlp | grep -v -- "--skip-download" | grep -q yt-dlp; then
    fail "A download is running right now — try again when it's done."
fi

# Sign a throwaway file first: proves the Keychain lets sign_update in unattended.
sign_with_timeout() {
    local out; out=$(mktemp)
    "$SIGN_UPDATE" "$1" >"$out" 2>&1 & local pid=$!
    for _ in $(seq 1 60); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid"; rm -f "$out"
        fail "sign_update is waiting for a Keychain prompt. Run it once in Terminal.app and choose Always Allow."
    fi
    wait "$pid" || { cat "$out"; rm -f "$out"; fail "sign_update failed."; }
    cat "$out"; rm -f "$out"
}
PROBE=$(mktemp); echo probe >"$PROBE"
sign_with_timeout "$PROBE" | grep -q 'sparkle:edSignature=' || fail "Test signature failed."
rm -f "$PROBE"
echo "✅ Checks passed (account, push access, version $VERSION free, no download running, unattended signing)."

if [ "$DRY_RUN" = 1 ]; then
    echo "Dry run: stopping here. Nothing was installed, pushed or released."
    exit 0
fi

# --- release ---
echo "$VERSION" > Resources/VERSION
if ! git diff --quiet Resources/VERSION; then
    git commit -q -m "$VERSION" Resources/VERSION
fi
./install.sh

rm -f Reprise.zip
ditto -c -k --keepParent /Applications/Reprise.app Reprise.zip
SIG_LINE=$(sign_with_timeout Reprise.zip)
ED_SIGNATURE=$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<<"$SIG_LINE")
LENGTH=$(sed -n 's/.*length="\([0-9]*\)".*/\1/p' <<<"$SIG_LINE")
[ -n "$ED_SIGNATURE" ] && [ -n "$LENGTH" ] || fail "Could not read sign_update output: $SIG_LINE"
"$SIGN_UPDATE" --verify Reprise.zip "$ED_SIGNATURE" || fail "Signature does not verify."

git push -q origin main
gh release create "$VERSION" Reprise.zip --repo "$REPO" --title "Reprise $VERSION" --notes "$NOTES"
STATUS=$(curl -sIL -o /dev/null -w "%{http_code}" "https://github.com/$REPO/releases/download/$VERSION/Reprise.zip")
[ "$STATUS" = "200" ] || fail "Release zip not downloadable (HTTP $STATUS) — appcast NOT updated."

./scripts/publish_release.sh "$VERSION" "$ED_SIGNATURE" "$LENGTH" "$NOTES"
echo "✅ Reprise $VERSION released."
