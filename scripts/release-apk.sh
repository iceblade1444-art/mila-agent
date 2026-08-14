#!/usr/bin/env bash
# Publish the freshly built APK to the phones.
#
# CI building an APK is not a release. The repository is private, so phones
# cannot reach GitHub assets: they download from the backend's own
# /downloads/app-release.apk, and they only learn an update exists when the
# backend's update record says latestCode is higher than what they run. Five
# builds in a row once shipped without either step, and every phone answered
# "already up to date" — correctly.
#
# This script does the whole second half:
#   1. downloads mila-android.apk from the rolling GitHub release,
#   2. copies it to the server, versioned, and atomically replaces app-release.apk,
#   3. registers the version from pubspec.yaml on the backend,
#   4. proves a phone one code behind would now be offered the update.
#
# Run it after the "MILA app" workflow goes green:  bash scripts/release-apk.sh
set -euo pipefail

SERVER="${MILA_SERVER:-admilana@172.16.10.6}"
SSH_KEY="${MILA_SSH_KEY:-$HOME/.ssh/agentos_codex_deploy}"
SSH=(ssh -i "$SSH_KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no "$SERVER")
DOWNLOADS=/opt/mila/downloads
BASE_URL="https://agent.milanapremium.uz/mila"

cd "$(dirname "$0")/.."

# The version being released is whatever pubspec says — the same line the APK
# was built from, so the record and the binary cannot disagree.
VERSION=$(sed -n 's/^version: *\([0-9.]*\)+.*/\1/p' pubspec.yaml)
CODE=$(sed -n 's/^version: *[0-9.]*+\([0-9]*\).*/\1/p' pubspec.yaml)
[ -n "$VERSION" ] && [ -n "$CODE" ] || { echo "pubspec.yaml has no version: x.y.z+N line" >&2; exit 1; }

NOTES="${1:-MILA $VERSION}"
APK="${2:-}"
STAMPED="MILA-$VERSION-$CODE-release.apk"

if [ -n "$APK" ]; then
  # A locally built APK, passed in by hand — the path every real release has
  # taken so far, because only this machine holds key.properties.
  [ -f "$APK" ] || { echo "нет файла: $APK" >&2; exit 1; }
  echo "· беру локальную сборку $APK…"
else
  # Refuse to register a version the released APK does not carry. The exact
  # HEAD sha is the wrong invariant — commits that touch nothing inside the app
  # (this script, docs) do not trigger a build, so the release legitimately
  # lags them. What must agree is the version line: the APK in the release was
  # built from the pubspec of its commit, and that is the version we are about
  # to tell phones they will get.
  RELEASED_SHA=$(gh release view latest --json body -q .body | grep -oE '`[0-9a-f]{7}`' | tr -d '`' | head -1)
  git fetch -q origin main
  RELEASED_LINE=$(git show "$RELEASED_SHA:pubspec.yaml" 2>/dev/null | sed -n 's/^version: *//p')
  if [ "$RELEASED_LINE" != "$VERSION+$CODE" ]; then
    echo "The rolling release was built from \`$RELEASED_SHA\` with version '$RELEASED_LINE'," >&2
    echo "but pubspec here says '$VERSION+$CODE'. Registering that would promise phones" >&2
    echo "a version the APK does not carry. Wait for the 'MILA app' workflow, then rerun." >&2
    exit 1
  fi
  APK="mila-android.apk"
  echo "· скачиваю $APK из релиза latest ($RELEASED_SHA)…"
  rm -f "$APK"
  gh release download latest --pattern "$APK"
fi

# The certificate is the guard that matters most. Android will only install an
# update signed with the same key as the app it replaces, and it refuses
# silently: the phone downloads the APK, nothing happens, and the updater keeps
# offering the same version forever. That is exactly what happened when a
# CI-built APK reached the phones — CI has no key.properties, Gradle fell back
# to the runner's throwaway debug key, and every installed app rejected it.
RELEASE_CERT="206af37aef7e4490b19329f13f04b10e5a87f53929c7af60df013abcf40d1fef"
export JAVA_HOME="${JAVA_HOME:-C:\\Program Files\\Android\\Android Studio\\jbr}"
APKSIGNER=$(ls "$LOCALAPPDATA/Android/Sdk/build-tools/"*/apksigner.bat 2>/dev/null | sort -V | tail -1)
if [ -n "$APKSIGNER" ]; then
  CERT=$(PATH="$JAVA_HOME/bin:$PATH" "$APKSIGNER" verify --print-certs "$APK" 2>/dev/null | sed -n 's/.*certificate SHA-256 digest: //p' | head -1)
  if [ "$CERT" != "$RELEASE_CERT" ]; then
    echo "ОШИБКА: APK подписан не релизным ключом (CN=MILA AI)." >&2
    echo "  ожидалось: $RELEASE_CERT" >&2
    echo "  получено:  ${CERT:-ничего}" >&2
    echo "Такой APK телефоны скачают и молча не установят. Соберите локально:" >&2
    echo "  flutter build apk --release --dart-define=MILA_BACKEND_URL=$BASE_URL" >&2
    echo "и передайте файл вторым аргументом." >&2
    exit 1
  fi
  echo "· подпись верна: релизный ключ MILA AI"
else
  echo "ПРЕДУПРЕЖДЕНИЕ: apksigner не найден, подпись не проверена" >&2
fi

# And the binary must carry the version being registered. The signature guard
# alone once let a stale build through: gradle failed, the pipe swallowed the
# exit code, and build/…/app-release.apk was still the previous release — with
# a perfectly valid signature. Publishing it under the new record would have
# phones install "1.5.7", stay on the old code, and be offered the same update
# forever.
AAPT=$(ls "$LOCALAPPDATA/Android/Sdk/build-tools/"*/aapt2.exe 2>/dev/null | sort -V | tail -1)
if [ -n "$AAPT" ]; then
  BADGING=$("$AAPT" dump badging "$APK" 2>/dev/null | head -1)
  APK_CODE=$(printf '%s' "$BADGING" | sed -n "s/.*versionCode='\([0-9]*\)'.*/\1/p")
  APK_VERSION=$(printf '%s' "$BADGING" | sed -n "s/.*versionName='\([^']*\)'.*/\1/p")
  if [ "$APK_CODE" != "$CODE" ] || [ "$APK_VERSION" != "$VERSION" ]; then
    echo "ОШИБКА: внутри APK версия '$APK_VERSION' (код ${APK_CODE:-?}), а регистрируется '$VERSION' (код $CODE)." >&2
    echo "Это устаревший файл — вероятно, сборка упала, а на диске остался прошлый релиз." >&2
    exit 1
  fi
  echo "· внутри APK действительно $APK_VERSION ($APK_CODE)"
else
  echo "ПРЕДУПРЕЖДЕНИЕ: aapt2 не найден, версия внутри APK не проверена" >&2
fi

echo "· копирую на сервер как $STAMPED…"
scp -i "$SSH_KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no "$APK" "$SERVER:$DOWNLOADS/$STAMPED"
# Atomic swap: phones mid-download keep the old file, never a half-written one.
"${SSH[@]}" "cp $DOWNLOADS/$STAMPED $DOWNLOADS/app-release.apk.new && mv $DOWNLOADS/app-release.apk.new $DOWNLOADS/app-release.apk"

echo "· регистрирую $VERSION ($CODE) на бэкенде…"
# The admin token never leaves the server: the request is made from inside the
# backend container, which already holds it in its environment. The container
# image carries no curl or wget, so the backend's own Node makes the call.
"${SSH[@]}" "docker exec -e REL_VERSION='$VERSION' -e REL_CODE='$CODE' -e REL_URL='$BASE_URL/downloads/app-release.apk' -e REL_NOTES='$NOTES' mila-mila-backend-1 node -e '
const body = {
  platform: \"android\",
  latestVersion: process.env.REL_VERSION,
  latestCode: Number(process.env.REL_CODE),
  minSupportedVersion: \"1.5.0\",
  minSupportedCode: 20,
  apkUrl: process.env.REL_URL,
  notes: process.env.REL_NOTES,
};
fetch(\"http://127.0.0.1:8787/admin/app/update\", {
  method: \"POST\",
  headers: { \"Content-Type\": \"application/json\", \"x-admin-token\": process.env.ADMIN_TOKEN },
  body: JSON.stringify(body),
}).then(async (res) => {
  console.log(res.status, await res.text());
  if (!res.ok) process.exit(1);
});'"

echo "· проверяю, что телефон на прошлой версии получит предложение…"
PREVIOUS=$((CODE - 1))
ANSWER=$(curl -s "$BASE_URL/v1/app/update?platform=android&versionCode=$PREVIOUS")
echo "$ANSWER"
echo "$ANSWER" | grep -q '"updateAvailable": *true' || { echo "ОШИБКА: телефон на коде $PREVIOUS всё ещё не видит обновления" >&2; exit 1; }
echo "Готово: телефоны на коде <$CODE увидят $VERSION при следующей проверке."
