#!/bin/bash

set -e

SOURCE_ARCHIVE="$1"
XCFRAMEWORK_NAME="libopus.xcframework"
ARCHS=("arm64-ios" "x86_64-ios" "arm64-macos")

MIN_IOS_VERSION="13.0"
MIN_MACOS_VERSION="10.13"

if [ -z "$SOURCE_ARCHIVE" ]; then
  echo "❌ Please provide the .tar.gz source archive as the first argument"
  exit 1
fi

rm -rf build "$XCFRAMEWORK_NAME"

build_arch() {
  ARCH=$1
  TARGET_ARCH="${ARCH%%-*}"
  PLATFORM_TAG="${ARCH##*-}"
  OUT_DIR="$(pwd)/build/${ARCH}/out"
  SRC_DIR="$(pwd)/build/${ARCH}/src"

  mkdir -p "$OUT_DIR" "$SRC_DIR"
  tar -xzf "$SOURCE_ARCHIVE" -C "$SRC_DIR"
  cd "$SRC_DIR"/*

  if [[ "$PLATFORM_TAG" == "ios" ]]; then
    if [[ "$TARGET_ARCH" == "x86_64" ]]; then
      PLATFORM="iphonesimulator"
      HOST="x86_64-apple-darwin"
    else
      PLATFORM="iphoneos"
      HOST="arm-apple-darwin"
    fi
    SDK_PATH=$(xcrun --sdk "$PLATFORM" --show-sdk-path)
    MIN_VERSION="-miphoneos-version-min=${MIN_IOS_VERSION}"
  else
    PLATFORM="macosx"
    HOST="arm-apple-darwin"
    SDK_PATH=$(xcrun --sdk "$PLATFORM" --show-sdk-path)
    MIN_VERSION="-mmacosx-version-min=${MIN_MACOS_VERSION}"
  fi

  ./configure \
    --enable-float-approx \
    --disable-shared \
    --enable-static \
    --with-pic \
    --disable-extra-programs \
    --disable-doc \
    --host="$HOST" \
    --prefix="$OUT_DIR" \
    CFLAGS="-arch $TARGET_ARCH $MIN_VERSION -isysroot $SDK_PATH" \
    LDFLAGS="-arch $TARGET_ARCH $MIN_VERSION -isysroot $SDK_PATH"

  make -j && make install
  echo "✅ Built for $ARCH"
}

for ARCH in "${ARCHS[@]}"; do
  build_arch "$ARCH"
  cd - > /dev/null
done

echo "📦 Creating $XCFRAMEWORK_NAME..."
CMD=(xcodebuild -create-xcframework)

for ARCH in "${ARCHS[@]}"; do
  LIB_PATH="build/${ARCH}/out/lib/libopus.a"
  HEADERS_PATH="build/${ARCH}/out/include"
  CMD+=("-library" "$LIB_PATH" "-headers" "$HEADERS_PATH")
  echo "✅ Included slice from $ARCH"
  echo "   ↪︎ $LIB_PATH"
  echo "   ↪︎ $HEADERS_PATH"
done

CMD+=("-output" "$XCFRAMEWORK_NAME")
"${CMD[@]}"

rm -rf build

echo "🎉 Done: $XCFRAMEWORK_NAME created successfully."
