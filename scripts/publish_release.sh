#!/bin/bash
# Appends a new <item> to appcast.xml and pushes it, for the version currently sitting in
# Reprise.zip (built + zipped by install.sh / ditto beforehand, same as every release before
# Sparkle). Split out from the rest of the release flow because signing itself has to happen
# in a real interactive Terminal session — sign_update prompts Keychain for the private key
# (by design: a compromised script should never be able to silently sign a malicious update),
# and that prompt doesn't reliably surface outside a normal Terminal.app session. So the
# release flow is, every time:
#
#   1. Build + install as usual (install.sh), bump Resources/VERSION first.
#   2. ditto -c -k --keepParent /Applications/Reprise.app Reprise.zip
#   3. In Terminal.app, by hand:
#        ./.build/artifacts/sparkle/Sparkle/bin/sign_update Reprise.zip
#      Approve the Keychain prompt (first time only — "Always Allow" sticks after that).
#   4. ./scripts/publish_release.sh <version> <edSignature> <length> "<release notes>"
#   5. gh release create <version> Reprise.zip --title ... --notes ... (unchanged, still
#      doesn't need the Keychain so it stays scriptable same as before).
set -e
cd "$(dirname "$0")/.."

VERSION="$1"
ED_SIGNATURE="$2"
LENGTH="$3"
NOTES="$4"

if [ -z "$VERSION" ] || [ -z "$ED_SIGNATURE" ] || [ -z "$LENGTH" ]; then
    echo "Usage: $0 <version, e.g. 1.6.26> <edSignature> <length> [release notes]"
    exit 1
fi

PUB_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
# Sparkle's own convention (see SampleAppcast.xml): newest item first, so a plain top-to-
# bottom read of the file already shows history newest-to-oldest.
NEW_ITEM="        <item>
            <title>Version $VERSION</title>
            <sparkle:version>$VERSION</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <description><![CDATA[$NOTES]]></description>
            <pubDate>$PUB_DATE</pubDate>
            <enclosure url=\"https://github.com/reprise-labs/reprise/releases/download/$VERSION/Reprise.zip\" length=\"$LENGTH\" type=\"application/octet-stream\" sparkle:edSignature=\"$ED_SIGNATURE\" />
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
        </item>"

# Insert right after <language>...</language> — i.e. as the new first item, ahead of
# whatever was already there.
python3 - "$NEW_ITEM" << 'PYEOF'
import sys, re
new_item = sys.argv[1]
with open("appcast.xml") as f:
    content = f.read()
content = re.sub(r"(<language>.*?</language>\n)", r"\1" + new_item.replace("\\", "\\\\") + "\n", content, count=1)
with open("appcast.xml", "w") as f:
    f.write(content)
PYEOF

echo "appcast.xml updated with $VERSION. Diff:"
git diff appcast.xml

git add appcast.xml
git commit -m "Add $VERSION to appcast.xml"
git push
echo "Pushed. SUFeedURL will pick this up on the next check (raw.githubusercontent.com caches briefly)."
