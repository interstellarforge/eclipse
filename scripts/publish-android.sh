#!/bin/sh
# Builds a signed Android release and publishes it as a GitHub release; installed apps offer it as an update.
#   scripts/publish-android.sh [versionName] "what changed"     e.g. scripts/publish-android.sh 2.0.1 "new transport bar"
# Needs: JDK 21, gh (logged in), ~/.eclipse/keystore.properties (see android/README.md). Run from a pushed commit.
set -e
cd "$(dirname "$0")/../android"
case "$1" in [0-9]*.[0-9]*) NAME="$1"; shift;; esac
NOTES="${1:-Android update}"
[ -f "$HOME/.eclipse/keystore.properties" ] || { echo "missing ~/.eclipse/keystore.properties (release key)"; exit 1; }
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home}"
CODE=$(( $(sed -n 's/^versionCode=//p' version.properties) + 1 ))
NAME="${NAME:-0.$CODE}"
printf 'versionCode=%s\nversionName=%s\n' "$CODE" "$NAME" > version.properties
./gradlew --no-daemon -q assembleRelease
APK=app/build/outputs/apk/release/app-release.apk
[ -f "$APK" ] || { echo "no signed release APK (is the key configured?)"; exit 1; }
cp "$APK" "../dist/Eclipse-$CODE.apk" 2>/dev/null || { mkdir -p ../dist; cp "$APK" "../dist/Eclipse-$CODE.apk"; }
gh release create "android-v$CODE" "../dist/Eclipse-$CODE.apk#Eclipse-$CODE.apk" --repo interstellarforge/eclipse --title "Eclipse $NAME" --notes "$NOTES"
echo "published android-v$CODE; commit android/version.properties"
