# syntax=docker/dockerfile:1

# Important: base toolchain image is provided from script as full registry path + version
ARG TOOLCHAIN_IMAGE=registry.invalid/placeholder:latest
FROM ${TOOLCHAIN_IMAGE} AS flutter-builder

# Re-declare ARGs after FROM to make them available in this build stage
ARG CACHE_PREFIX
ARG CACHE_SUFFIX

WORKDIR /app

ENV GRADLE_USER_HOME=/root/.gradle
ENV GRADLE_OPTS="-Dorg.gradle.caching=true -Dorg.gradle.daemon=false"
ENV PUB_CACHE=/root/.pub-cache

COPY pubspec.yaml pubspec.lock ./

COPY packages/ ./packages/

RUN --mount=type=cache,id=${CACHE_PREFIX}-pub-cache-${CACHE_SUFFIX},target=/root/.pub-cache \
    --mount=type=cache,id=${CACHE_PREFIX}-flutter-cache-${CACHE_SUFFIX},target=/root/.cache/flutter \
    flutter pub get --no-example

COPY . .

# Build args
ARG VERSION
ARG FLAVOR
ARG REVISION
ARG BRANCH_OR_TAG
ARG IS_TAG
ARG BUILD_AAB

# Environment variables for Makefile
ENV BUILD_NUMBER=$VERSION \
    FLAVOR=$FLAVOR \
    REVISION=$REVISION \
    BRANCH_OR_TAG=$BRANCH_OR_TAG \
    IS_TAG=$IS_TAG \
    BUILD_AAB=$BUILD_AAB

RUN --mount=type=cache,id=${CACHE_PREFIX}-gradle-cache-${CACHE_SUFFIX},target=/root/.gradle,sharing=locked \
    --mount=type=cache,id=${CACHE_PREFIX}-android-cache-${CACHE_SUFFIX},target=/root/.android,sharing=locked \
    --mount=type=cache,id=${CACHE_PREFIX}-pub-cache-${CACHE_SUFFIX},target=/root/.pub-cache \
    --mount=type=cache,id=${CACHE_PREFIX}-flutter-cache-${CACHE_SUFFIX},target=/root/.cache/flutter \
    --mount=type=secret,id=keystore_b64,env=KEYSTORE_B64 \
    --mount=type=secret,id=keystore_password,env=KEYSTORE_PASSWORD \
    --mount=type=secret,id=key_alias,env=KEY_ALIAS \
    --mount=type=secret,id=key_password,env=KEY_PASSWORD \
    bash -Eeuo pipefail <<'BASH'
cleanup() {
    # delete key even if build failed
    rm -f /app/example/android/app/release.keystore || true
}
trap cleanup EXIT

: "${KEYSTORE_B64:?KEYSTORE_B64 is empty (missing Android keystore base64)}"
: "${KEYSTORE_PASSWORD:?KEYSTORE_PASSWORD is empty}"
: "${KEY_ALIAS:?KEY_ALIAS is empty}"
: "${KEY_PASSWORD:?KEY_PASSWORD is empty}"

install -d /app/example/android/app
printf "%s" "$KEYSTORE_B64" | base64 -d > /app/example/android/app/release.keystore
chmod 600 /app/example/android/app/release.keystore
test -s /app/example/android/app/release.keystore

export KEYSTORE_PASSWORD KEY_ALIAS KEY_PASSWORD

# protecting from fails when calling COPY
install -d /app/example/build/app/outputs/bundle/release
install -d /app/example/build/app/outputs/symbols/{apk,aab}
touch /app/example/build/app/outputs/symbols/apk/.keep
touch /app/example/build/app/outputs/symbols/aab/.keep

make release-android

cd /app/example/build
rm -f mapping-bundle.zip
if [ -d app/example/outputs/mapping ]; then
  (cd app/example/outputs && zip -rq /app/example/build/mapping-bundle.zip mapping)
else
  : > mapping-bundle.zip
fi
# Adding .proguard-uuid (created by make)
if [ -f .proguard-uuid ]; then
  zip -qj mapping-bundle.zip /app/example/build/.proguard-uuid
fi
rm -rf app/example/outputs/mapping /app/example/build/.proguard-uuid

shred -u /app/example/android/app/release.keystore || rm -f /app/example/android/app/release.keystore
BASH

# Export artifacts
FROM scratch AS export-stage
COPY --from=flutter-builder /app/example/build/app/outputs/flutter-apk/ /output/
COPY --from=flutter-builder /app/example/build/app/outputs/bundle/release/ /output/
COPY --from=flutter-builder /app/example/build/app/outputs/symbols/ /output/symbols/
COPY --from=flutter-builder /app/example/build/mapping-bundle.zip /output/mapping/mapping-bundle.zip
