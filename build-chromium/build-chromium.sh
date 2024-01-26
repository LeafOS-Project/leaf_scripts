#!/bin/bash

set -e

chromium_version="121.0.6167.71"
chromium_code="616710100"
clean=0
gsync=0
supported_archs=(arm64 x64)

usage() {
    echo "Usage:"
    echo "  build_webview [ options ]"
    echo
    echo "  Options:"
    echo "    -a <arch> Build specified arch"
    echo "    -c Clean"
    echo "    -h Show this message"
    echo "    -r <release> Specify chromium release"
    echo "    -s Sync"
    echo
    echo "  Example:"
    echo "    build_webview -c -r $chromium_version:$chromium_code"
    echo
    exit 1
}

build() {
    build_args=$args' target_cpu="'$1'"'

    code=$chromium_code
    if [ $1 '==' "arm" ]; then
        code+=00
    elif [ $1 '==' "arm64" ]; then
        code+=50
    elif [ $1 '==' "x86" ]; then
        code+=10
    elif [ $1 '==' "x64" ]; then
        code+=60
    fi
    build_args+=' android_default_version_code="'$code'"'

    gn gen "out/$1" --args="$build_args"
    ninja -C out/$1 trichrome_webview_64_32_apk trichrome_chrome_64_32_apk trichrome_library_64_32_apk
}

while getopts ":a:chr:s" opt; do
    case $opt in
        a) for arch in ${supported_archs[@]}; do
               [ "$OPTARG" '==' "$arch" ] && build_arch="$OPTARG"
           done
           if [ -z "$build_arch" ]; then
               echo "Unsupported ARCH: $OPTARG"
               echo "Supported ARCHs: ${supported_archs[@]}"
               exit 1
           fi
           ;;
        c) clean=1 ;;
        h) usage ;;
        r) version=(${OPTARG//:/ })
           chromium_version=${version[0]}
           chromium_code=${version[1]}
           ;;
        s) gsync=1 ;;
        :)
          echo "Option -$OPTARG requires an argument"
          echo
          usage
          ;;
        \?)
          echo "Invalid option:-$OPTARG"
          echo
          usage
          ;;
    esac
done
shift $((OPTIND-1))

# Add depot_tools to PATH
if [ ! -d depot_tools ]; then
    git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
fi
export PATH="$(pwd -P)/depot_tools:$PATH"

if [ ! -d src ]; then
    fetch --no-history android
    yes | gclient sync -D -R -r $chromium_version --no-history
fi

if [ $gsync -eq 1 ]; then
    find src -name index.lock -delete
    yes | gclient sync -D -R -r $chromium_version --no-history
fi
cd src

# Apply our patches
if [ $gsync -eq 1 ]; then
    git am $(realpath $(dirname $0))/patches/*.patch
fi

# Replace webview icon
cp chrome/android/java/res_chromium_base/mipmap-mdpi/app_icon.png android_webview/nonembedded/java/res_icon/drawable-mdpi/icon_webview.png
cp chrome/android/java/res_chromium_base/mipmap-hdpi/app_icon.png android_webview/nonembedded/java/res_icon/drawable-hdpi/icon_webview.png
cp chrome/android/java/res_chromium_base/mipmap-xhdpi/app_icon.png android_webview/nonembedded/java/res_icon/drawable-xhdpi/icon_webview.png
cp chrome/android/java/res_chromium_base/mipmap-xxhdpi/app_icon.png android_webview/nonembedded/java/res_icon/drawable-xxhdpi/icon_webview.png

# Build args
args='target_os="android"'
args+=' android_channel="stable"'
args+=' is_debug=false'
args+=' is_official_build=true'
args+=' is_chrome_branded=false'
args+=' use_official_google_api_keys=false'
args+=' ffmpeg_branding="Chrome"'
args+=' proprietary_codecs=true'
args+=' enable_resource_allowlist_generation=false'
args+=' enable_remoting=false'
args+=' is_component_build=false'
args+=' symbol_level=0'
args+=' enable_nacl=false'
args+=' blink_symbol_level=0'
args+=' webview_devui_show_icon=false'
args+=' dfmify_dev_ui=false'
args+=' enable_gvr_services=false'
args+=' enable_vr=false'
args+=' enable_arcore=false'
args+=' enable_openxr=false'
args+=' enable_cardboard=false'
args+=' disable_fieldtrial_testing_config=true'
args+=' android_default_version_name="'$chromium_version'"'
args+=' chrome_public_manifest_package="org.leafos.chromium"'
args+=' system_webview_package_name="org.leafos.webview"'
args+=' trichrome_library_package="org.leafos.trichromelibrary"'
args+=' trichrome_certdigest="f57883d4c1f9007222ea92c5f25b42156bfa3aa13f5634237057e58835a996e2"'

# Setup environment
[ $clean -eq 1 ] && rm -rf out
. build/android/envsetup.sh

# Check target and build
if [ -n "$build_arch" ]; then
    build $build_arch
else
    build arm64
    build x64
fi
