#!/bin/sh
set -eu

log() {
    printf '[Rokurics][embed_whisper_helper] %s\n' "$*"
}

fail() {
    printf '[Rokurics][embed_whisper_helper] error: %s\n' "$*" >&2
    exit 1
}

first_existing_whisper_root() {
    if [ -n "${WHISPER_CPP_ROOT:-}" ]; then
        printf '%s\n' "$WHISPER_CPP_ROOT"
        return
    fi

    if [ -d "/Users/vita/ThirdParty/whisper.cpp" ]; then
        printf '%s\n' "/Users/vita/ThirdParty/whisper.cpp"
        return
    fi

    if [ -d "/Users/vita/thirdparty/whisper.cpp" ]; then
        printf '%s\n' "/Users/vita/thirdparty/whisper.cpp"
        return
    fi

    printf '%s\n' "/Users/vita/ThirdParty/whisper.cpp"
}

copy_dylib() {
    source_path="$1"
    output_name="$2"
    destination_path="${WHISPER_DYLIB_DIR}/${output_name}"

    [ -f "$source_path" ] || fail "missing dylib: ${source_path}"
    rm -f "$destination_path"
    cp -fL "$source_path" "$destination_path"
    chmod 755 "$destination_path"
    fix_dylib_rpaths "$destination_path"
    sign_file "$destination_path"
}

delete_rpath_if_present() {
    binary_path="$1"
    rpath_value="$2"

    install_name_tool -delete_rpath "$rpath_value" "$binary_path" 2>/dev/null || true
}

fix_helper_rpaths() {
    binary_path="$1"

    delete_rpath_if_present "$binary_path" "${WHISPER_ROOT}/build/src"
    delete_rpath_if_present "$binary_path" "${WHISPER_ROOT}/build/ggml/src"
    delete_rpath_if_present "$binary_path" "${WHISPER_ROOT}/build/ggml/src/ggml-blas"
    delete_rpath_if_present "$binary_path" "${WHISPER_ROOT}/build/ggml/src/ggml-metal"
    delete_rpath_if_present "$binary_path" "/Users/vita/ThirdParty/whisper.cpp/build/src"
    delete_rpath_if_present "$binary_path" "/Users/vita/ThirdParty/whisper.cpp/build/ggml/src"
    delete_rpath_if_present "$binary_path" "/Users/vita/ThirdParty/whisper.cpp/build/ggml/src/ggml-blas"
    delete_rpath_if_present "$binary_path" "/Users/vita/ThirdParty/whisper.cpp/build/ggml/src/ggml-metal"
    delete_rpath_if_present "$binary_path" "/Users/vita/thirdparty/whisper.cpp/build/src"
    delete_rpath_if_present "$binary_path" "/Users/vita/thirdparty/whisper.cpp/build/ggml/src"
    delete_rpath_if_present "$binary_path" "/Users/vita/thirdparty/whisper.cpp/build/ggml/src/ggml-blas"
    delete_rpath_if_present "$binary_path" "/Users/vita/thirdparty/whisper.cpp/build/ggml/src/ggml-metal"

    install_name_tool -add_rpath "@executable_path/../Frameworks/Whisper" "$binary_path"
}

fix_dylib_rpaths() {
    binary_path="$1"

    delete_rpath_if_present "$binary_path" "${WHISPER_ROOT}/build/src"
    delete_rpath_if_present "$binary_path" "${WHISPER_ROOT}/build/ggml/src"
    delete_rpath_if_present "$binary_path" "${WHISPER_ROOT}/build/ggml/src/ggml-blas"
    delete_rpath_if_present "$binary_path" "${WHISPER_ROOT}/build/ggml/src/ggml-metal"
    delete_rpath_if_present "$binary_path" "/Users/vita/ThirdParty/whisper.cpp/build/src"
    delete_rpath_if_present "$binary_path" "/Users/vita/ThirdParty/whisper.cpp/build/ggml/src"
    delete_rpath_if_present "$binary_path" "/Users/vita/ThirdParty/whisper.cpp/build/ggml/src/ggml-blas"
    delete_rpath_if_present "$binary_path" "/Users/vita/ThirdParty/whisper.cpp/build/ggml/src/ggml-metal"
    delete_rpath_if_present "$binary_path" "/Users/vita/thirdparty/whisper.cpp/build/src"
    delete_rpath_if_present "$binary_path" "/Users/vita/thirdparty/whisper.cpp/build/ggml/src"
    delete_rpath_if_present "$binary_path" "/Users/vita/thirdparty/whisper.cpp/build/ggml/src/ggml-blas"
    delete_rpath_if_present "$binary_path" "/Users/vita/thirdparty/whisper.cpp/build/ggml/src/ggml-metal"

    install_name_tool -add_rpath "@loader_path" "$binary_path"
}

sign_file() {
    file_path="$1"

    if [ "${CODE_SIGNING_ALLOWED:-YES}" = "NO" ]; then
        log "code signing skipped for ${file_path}"
        return
    fi

    sign_identity="${EXPANDED_CODE_SIGN_IDENTITY:-}"
    if [ "${CONFIGURATION:-}" = "Debug" ]; then
        sign_identity="-"
    fi
    if [ -z "$sign_identity" ] || [ "$sign_identity" = "-" ]; then
        sign_identity="-"
    fi

    codesign --force --sign "$sign_identity" ${OTHER_CODE_SIGN_FLAGS:-} "$file_path"
}

[ -n "${TARGET_BUILD_DIR:-}" ] || fail "TARGET_BUILD_DIR is not set"
[ -n "${CONTENTS_FOLDER_PATH:-}" ] || fail "CONTENTS_FOLDER_PATH is not set"
[ -n "${FRAMEWORKS_FOLDER_PATH:-}" ] || fail "FRAMEWORKS_FOLDER_PATH is not set"

WHISPER_ROOT="$(first_existing_whisper_root)"
WHISPER_CLI="${WHISPER_ROOT}/build/bin/whisper-cli"

[ -f "$WHISPER_CLI" ] || fail "missing whisper-cli at ${WHISPER_CLI}; set WHISPER_CPP_ROOT to a compiled whisper.cpp checkout"

APP_CONTENTS_DIR="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}"
WHISPER_HELPER_DIR="${APP_CONTENTS_DIR}/Helpers"
WHISPER_HELPER="${WHISPER_HELPER_DIR}/rokurics-whisper"
WHISPER_DYLIB_DIR="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/Whisper"

mkdir -p "$WHISPER_HELPER_DIR"
mkdir -p "$WHISPER_DYLIB_DIR"

log "embedding helper from ${WHISPER_CLI}"
rm -f "$WHISPER_HELPER"
cp -fL "$WHISPER_CLI" "$WHISPER_HELPER"
chmod 755 "$WHISPER_HELPER"

copy_dylib "${WHISPER_ROOT}/build/src/libwhisper.1.dylib" "libwhisper.1.dylib"
copy_dylib "${WHISPER_ROOT}/build/ggml/src/libggml.0.dylib" "libggml.0.dylib"
copy_dylib "${WHISPER_ROOT}/build/ggml/src/libggml-base.0.dylib" "libggml-base.0.dylib"
copy_dylib "${WHISPER_ROOT}/build/ggml/src/libggml-cpu.0.dylib" "libggml-cpu.0.dylib"
copy_dylib "${WHISPER_ROOT}/build/ggml/src/ggml-blas/libggml-blas.0.dylib" "libggml-blas.0.dylib"
copy_dylib "${WHISPER_ROOT}/build/ggml/src/ggml-metal/libggml-metal.0.dylib" "libggml-metal.0.dylib"

fix_helper_rpaths "$WHISPER_HELPER"
sign_file "$WHISPER_HELPER"

log "embedded helper at ${WHISPER_HELPER}"
log "embedded dylibs at ${WHISPER_DYLIB_DIR}"
