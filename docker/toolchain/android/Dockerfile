# syntax=docker/dockerfile:1

FROM adguard/android-sdk31@sha256:ed1fc181460c255700366a784aeebfd47a0108bdf7ac3c81e32ff329456333c3

ARG ANDROID_BUILD_TOOLS=35.0.0
ARG ANDROID_NDK=27.0.12077973

WORKDIR /opt

# Copy Flutter version file
ARG FLUTTER_VERSION_FILE=.ci-flutter-version
COPY ${FLUTTER_VERSION_FILE} /opt/.ci-flutter-version

# Install Flutter
RUN set -eux; \
    FLUTTER_VERSION=$(cat /opt/.ci-flutter-version); \
    echo "Using Flutter version $FLUTTER_VERSION"; \
    curl -o flutter.tar.xz "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"; \
    tar xf flutter.tar.xz; \
    rm flutter.tar.xz; \
    touch /.dockerenv

ENV FLUTTER_HOME=/opt/flutter
ENV PATH="$PATH:$FLUTTER_HOME/bin"

RUN flutter config --no-analytics || true

# Precache Flutter artifacts for Android
RUN flutter precache --android

# Accept Android licenses and verify installation
RUN yes | flutter doctor --android-licenses && flutter doctor -v

# Setup Android SDK paths
ENV ANDROID_SDK_ROOT=/storage/android-sdk
ENV PATH="$PATH:${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools"

# Install Android SDK components
RUN set -eux; \
    yes | sdkmanager --licenses; \
    sdkmanager --install \
      "platform-tools" \
      "build-tools;${ANDROID_BUILD_TOOLS}" \
      "platforms;android-33" "platforms;android-34" "platforms;android-35" "platforms;android-36" \
      "ndk;${ANDROID_NDK}"; \
    echo "Installed SDK components:"; \
    ls -1 ${ANDROID_SDK_ROOT}/platforms || true; \
    ls -1 ${ANDROID_SDK_ROOT}/build-tools || true; \
    ls -1 ${ANDROID_SDK_ROOT}/ndk || true
