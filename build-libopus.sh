#! /bin/sh

set -ex

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPUS_DIR=$(echo "$SCRIPT_DIR" | sed 's:/*$::')

BUILD_DIR="${OPUS_DIR}"
SOURCE_CODE_ARCHIVE="${OPUS_DIR}/$1"

MINIOSVERSION="13.0"
MINMACOSVERSION="10.0"

# Include macOS archs
ARCHS=("arm64-ios" "x86_64-ios" "arm64-macos")

# 🧹 Cleaning previous build artifacts
echo "🧹 Cleaning previous build directories..."
rm -rf "$BUILD_DIR/Sources"
rm -rf "$BUILD_DIR/Public"
for ARCH in "${ARCHS[@]}"; do
    rm -rf "$BUILD_DIR/$ARCH"
done

LIBS=()
FRAMEWORKS=()

OPT_CFLAGS="-Os -g"
OPT_LDFLAGS=""
OPT_CONFIG_ARGS=""

DEVELOPER=`xcode-select -print-path`
OUTPUTDIR="$BUILD_DIR/Public"

for ARCH in "${ARCHS[@]}"; do
    echo "🔧 Building for $ARCH..."

    TARGET_ARCH="${ARCH%%-*}"
    PLATFORM_TAG="${ARCH##*-}"

    SRCDIR="${BUILD_DIR}/${ARCH}/src"
    mkdir -p "$SRCDIR"
    INTERDIR="${BUILD_DIR}/${ARCH}/built"
    mkdir -p "$INTERDIR"

    echo "📦 Extracting source archive for $ARCH"
    tar zxf "$SOURCE_CODE_ARCHIVE" -C "$SRCDIR"
    cd "${SRCDIR}/opus-"*

    if [ "$PLATFORM_TAG" == "ios" ]; then
        echo "📱 Targeting iOS ($TARGET_ARCH)"
        if [ "$TARGET_ARCH" == "x86_64" ]; then
            PLATFORM="iphonesimulator"
            EXTRA_CFLAGS="-arch $TARGET_ARCH"
            EXTRA_CONFIG="--host=x86_64-apple-darwin"
        elif [ "$TARGET_ARCH" == "sim_arm64" ]; then
            PLATFORM="iphonesimulator"
            EXTRA_CFLAGS="-arch arm64 --target=arm64-apple-ios$MINIOSVERSION-simulator"
            EXTRA_CONFIG="--host=arm-apple-darwin20"
        else
            PLATFORM="iphoneos"
            EXTRA_CFLAGS="-arch $TARGET_ARCH"
            EXTRA_CONFIG="--host=arm-apple-darwin"
        fi
        SDK_PATH="$(xcrun --sdk $PLATFORM --show-sdk-path 2>/dev/null)"
        MIN_VERSION_FLAG="-miphoneos-version-min=${MINIOSVERSION}"
    elif [ "$PLATFORM_TAG" == "macos" ]; then
        echo "💻 Targeting macOS ($TARGET_ARCH)"
        PLATFORM="macosx"
        EXTRA_CFLAGS="-arch $TARGET_ARCH"
        
        if [ "$TARGET_ARCH" == "arm64" ]; then
            EXTRA_CONFIG="--host=aarch64-apple-darwin"
        else
            EXTRA_CONFIG="--host=$TARGET_ARCH-apple-darwin"
        fi

        SDK_PATH="$(xcrun --sdk $PLATFORM --show-sdk-path 2>/dev/null)"
        MIN_VERSION_FLAG="-mmacosx-version-min=${MINMACOSVERSION}"
    else
        echo "❌ Unknown platform: $PLATFORM_TAG"
        exit 1
    fi

    echo "⚙️ Configuring opus for $ARCH"
    ./configure --enable-float-approx --disable-shared --enable-static --with-pic --disable-extra-programs --disable-doc ${EXTRA_CONFIG} \
    --prefix="${INTERDIR}" \
    LDFLAGS="$LDFLAGS ${OPT_LDFLAGS} -fPIE $MIN_VERSION_FLAG -L${OUTPUTDIR}/lib" \
    CFLAGS="$CFLAGS ${EXTRA_CFLAGS} ${OPT_CFLAGS} -fPIE $MIN_VERSION_FLAG -I${OUTPUTDIR}/include -isysroot ${SDK_PATH}"

    echo "🛠  Building opus for $ARCH"
    make -j
    make install

    LIB_PATH="$INTERDIR/lib/libopus.a"
    LIBS+=("$LIB_PATH")
done

SOURCE_DESTINATION_DIR="$BUILD_DIR/Sources/libopus"
HEADERS_DESTINATION_PATH="$SOURCE_DESTINATION_DIR/include"

echo "📁 Preparing framework headers"
mkdir -p $SOURCE_DESTINATION_DIR
mkdir -p $HEADERS_DESTINATION_PATH

cp -R "$BUILD_DIR/${ARCHS[0]}/built/include/opus/"* $HEADERS_DESTINATION_PATH

for ((i = 0; i < ${#LIBS[@]}; i++)); do
    ARCH=${ARCHS[$i]}
    LIB_PATH=${LIBS[$i]}
    
    echo "📦 Packaging $ARCH into .framework"
    XCF_DIR="$SOURCE_DESTINATION_DIR/$ARCH"
    rm -rf "$XCF_DIR"
    mkdir -p "$XCF_DIR"
    
    LIB_FRAMEWORK_DIR="$XCF_DIR/libopus.framework"
    LIB_FRAMEWORK_HEADERS_DIR="$LIB_FRAMEWORK_DIR/Headers"
    LIB_FRAMEWORK_A_PATH="$LIB_FRAMEWORK_DIR/libopus"
    LIB_FRAMEWORK_MODULES_DIR="$LIB_FRAMEWORK_DIR/Modules"
    
    mkdir -p $LIB_FRAMEWORK_HEADERS_DIR
    cp $LIB_PATH $LIB_FRAMEWORK_A_PATH
    
    for file in "$HEADERS_DESTINATION_PATH"/*; do
        [ -e "$file" ] || continue
        cp "$file" "$LIB_FRAMEWORK_HEADERS_DIR"
    done

    mkdir -p "$LIB_FRAMEWORK_MODULES_DIR"

    MODULEMAP_PATH="$LIB_FRAMEWORK_MODULES_DIR/module.modulemap"
    cat <<EOF > "$MODULEMAP_PATH"
framework module libopus {
    header "Headers/opus.h"
    header "Headers/opus_defines.h"
    header "Headers/opus_types.h"
    header "Headers/opus_multistream.h"
    header "Headers/opus_projection.h"

    export *
    module * { export * }

    link "libopus"
}
EOF

    FRAMEWORKS+=($LIB_FRAMEWORK_DIR)
done

echo "🧱 Creating universal .xcframework"
CMD=(xcodebuild -create-xcframework)
for FRAMEWORK in "${FRAMEWORKS[@]}"; do
    CMD+=(-framework "$FRAMEWORK")
done
CMD+=(-output "$BUILD_DIR/libopus.xcframework")
"${CMD[@]}"

# ✅ Inject Info.plist into each framework inside the .xcframework
echo "🧾 Injecting Info.plist into each libopus.framework slice..."

XCFRAMEWORK_PATH="$BUILD_DIR/libopus.xcframework"
EXECUTABLE_NAME="libopus"
BUNDLE_ID="org.opus-codec.libopus"
VERSION="1.3.1"
BUILD="1"

get_platform() {
  case "$1" in
    *ios-arm64*) echo "iPhoneOS" ;;
    *ios-x86_64*) echo "iPhoneSimulator" ;;
    *macos*) echo "MacOSX" ;;
    *) echo "Unknown" ;;
  esac
}

find "$XCFRAMEWORK_PATH" -type d -name "${EXECUTABLE_NAME}.framework" | while read -r fw_path; do
    platform=$(get_platform "$fw_path")

    if [[ "$platform" == "MacOSX" ]]; then
        minOS="$MINMACOSVERSION"
    else
        minOS="$MINIOSVERSION"
    fi

    plist_path="$fw_path/Info.plist"
    echo "   ↪︎ Writing Info.plist → $plist_path"

cat > "$plist_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}.${platform}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${EXECUTABLE_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD}</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>MinimumOSVersion</key>
    <string>${minOS}</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>${platform}</string>
    </array>
    <key>DTPlatformName</key>
    <string>${platform}</string>
    <key>DTPlatformVersion</key>
    <string>${minOS}</string>
    <key>DTSDKName</key>
    <string>${platform}${minOS}</string>
</dict>
</plist>
EOF


done

echo "📦 Info.plist injection complete ✅"

echo "🧹 Cleaning up intermediate build directories"
for ARCH in "${ARCHS[@]}"; do
    rm -rf "$BUILD_DIR/$ARCH"
done
    rm -rf "$BUILD_DIR/Sources"

echo "✅ Done! XCFramework created at $SOURCE_DESTINATION_DIR/libopus.xcframework"
