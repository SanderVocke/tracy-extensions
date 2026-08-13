# Canonical embedded-capture native release bundle configuration.

set(_supported_platforms
    linux-x86_64 linux-arm64 macos-x86_64 macos-arm64
    windows-x86_64 windows-arm64
)
if(NOT TRACY_EMBEDDED_NATIVE_PLATFORM IN_LIST _supported_platforms)
    message(FATAL_ERROR
        "Unsupported TRACY_EMBEDDED_NATIVE_PLATFORM: ${TRACY_EMBEDDED_NATIVE_PLATFORM}"
    )
endif()

if(TRACY_EMBEDDED_NATIVE_PLATFORM STREQUAL "linux-x86_64")
    set(_expected_system Linux)
    set(_expected_processor "x86_64|AMD64")
    set(_expected_triple x86_64-unknown-linux-gnu)
    set(_architecture x86_64)
    set(_runtime_abi gnu-glibc)
    set(_deployment_baseline ubuntu-24.04-glibc)
elseif(TRACY_EMBEDDED_NATIVE_PLATFORM STREQUAL "linux-arm64")
    set(_expected_system Linux)
    set(_expected_processor "aarch64|arm64|ARM64")
    set(_expected_triple aarch64-unknown-linux-gnu)
    set(_architecture aarch64)
    set(_runtime_abi gnu-glibc)
    set(_deployment_baseline ubuntu-24.04-glibc)
elseif(TRACY_EMBEDDED_NATIVE_PLATFORM STREQUAL "macos-x86_64")
    set(_expected_system Darwin)
    set(_expected_processor "x86_64|AMD64")
    set(_expected_triple x86_64-apple-darwin)
    set(_architecture x86_64)
    set(_runtime_abi apple-clang-libc++)
    set(_deployment_baseline macos-12.0)
elseif(TRACY_EMBEDDED_NATIVE_PLATFORM STREQUAL "macos-arm64")
    set(_expected_system Darwin)
    set(_expected_processor "aarch64|arm64|ARM64")
    set(_expected_triple aarch64-apple-darwin)
    set(_architecture aarch64)
    set(_runtime_abi apple-clang-libc++)
    set(_deployment_baseline macos-12.0)
elseif(TRACY_EMBEDDED_NATIVE_PLATFORM STREQUAL "windows-x86_64")
    set(_expected_system Windows)
    set(_expected_processor "x86_64|AMD64")
    set(_expected_triple x86_64-pc-windows-msvc)
    set(_architecture x86_64)
    set(_runtime_abi msvc-dynamic)
    set(_deployment_baseline windows-10)
elseif(TRACY_EMBEDDED_NATIVE_PLATFORM STREQUAL "windows-arm64")
    set(_expected_system Windows)
    set(_expected_processor "aarch64|arm64|ARM64")
    set(_expected_triple aarch64-pc-windows-msvc)
    set(_architecture aarch64)
    set(_runtime_abi msvc-dynamic)
    set(_deployment_baseline windows-10)
endif()

if(NOT CMAKE_SYSTEM_NAME STREQUAL _expected_system)
    message(FATAL_ERROR
        "Platform ${TRACY_EMBEDDED_NATIVE_PLATFORM} requires ${_expected_system}, got ${CMAKE_SYSTEM_NAME}"
    )
endif()
if(NOT CMAKE_SYSTEM_PROCESSOR MATCHES "${_expected_processor}")
    message(FATAL_ERROR
        "Platform ${TRACY_EMBEDDED_NATIVE_PLATFORM} does not match processor ${CMAKE_SYSTEM_PROCESSOR}"
    )
endif()
if(NOT TRACY_EMBEDDED_NATIVE_TARGET_TRIPLE STREQUAL _expected_triple)
    message(FATAL_ERROR
        "Platform ${TRACY_EMBEDDED_NATIVE_PLATFORM} requires target triple ${_expected_triple}"
    )
endif()

execute_process(
    COMMAND git rev-parse HEAD
    WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
    OUTPUT_VARIABLE _source_commit
    OUTPUT_STRIP_TRAILING_WHITESPACE
    RESULT_VARIABLE _git_result
)
string(LENGTH "${_source_commit}" _source_commit_length)
if(NOT _git_result EQUAL 0 OR NOT _source_commit_length EQUAL 40 OR NOT _source_commit MATCHES "^[0-9a-f]+$")
    message(FATAL_ERROR "A full source Git commit is required for package provenance")
endif()

if(WIN32)
    set(_archive_name "tracy-embedded-native-${TRACY_EMBEDDED_NATIVE_PLATFORM}.zip")
    set(_embedded_name tracy_embedded_capture_native.lib)
    set(_capstone_name capstone.lib)
    set(_zstd_name zstd_static.lib)
else()
    set(_archive_name "tracy-embedded-native-${TRACY_EMBEDDED_NATIVE_PLATFORM}.tar.gz")
    set(_embedded_name libtracy_embedded_capture_native.a)
    set(_capstone_name libcapstone.a)
    set(_zstd_name libzstd.a)
endif()

set(_package_root "${PROJECT_BINARY_DIR}/tracy-embedded-native-package")
set(_archive "${PROJECT_BINARY_DIR}/dist/${_archive_name}")
set(_profile "embedded_capture,enable,on_demand,manual_lifetime,delayed_init,timer_fallback,no_system_tracing,no_context_switch,no_sampling,no_code_transfer,no_broadcast,no_callstack_inlines,no_crash_handler,no_verify,no_debuginfod,no_demangle,no_fibers,no_flush_on_exit,no_only_localhost,no_only_ipv4,no_build_testing")

add_custom_target(
    tracy-embedded-native-package
    COMMAND
        "${CMAKE_COMMAND}"
        "-DOUTPUT_ROOT=${_package_root}"
        "-DOUTPUT_ARCHIVE=${_archive}"
        "-DEMBEDDED_SOURCE=$<TARGET_FILE:tracy_embedded_capture_native>"
        "-DCAPSTONE_SOURCE=$<TARGET_FILE:capstone_static>"
        "-DZSTD_SOURCE=$<TARGET_FILE:libzstd_static>"
        "-DEMBEDDED_NAME=${_embedded_name}"
        "-DCAPSTONE_NAME=${_capstone_name}"
        "-DZSTD_NAME=${_zstd_name}"
        "-DLIB_TOOL=${CMAKE_AR}"
        "-DHEADER_SOURCE=${PROJECT_SOURCE_DIR}/tracy-embedded-capture/include/tracy_embedded_capture/embedded_capture.h"
        "-DLICENSE_APACHE=${PROJECT_SOURCE_DIR}/tracy-embedded-capture/rust/tracy-client-sys/LICENSE-APACHE"
        "-DLICENSE_MIT=${PROJECT_SOURCE_DIR}/tracy-embedded-capture/rust/tracy-client-sys/LICENSE-MIT"
        "-DLICENSE_TRACY=${PROJECT_SOURCE_DIR}/tracy-embedded-capture/rust/tracy-client-sys/LICENSE-TRACY"
        "-DLICENSE_CAPSTONE=${tracy_capstone_SOURCE_DIR}/LICENSES/LICENSE.TXT"
        "-DLICENSE_CAPSTONE_BSD=${tracy_capstone_SOURCE_DIR}/LICENSES/LICENSE_BSD_3_CLAUSE.txt"
        "-DLICENSE_CAPSTONE_LLVM=${tracy_capstone_SOURCE_DIR}/LICENSES/LICENSE_LLVM.TXT"
        "-DLICENSE_ZSTD=${tracy_zstd_SOURCE_DIR}/LICENSE"
        "-DCOPYING_ZSTD=${tracy_zstd_SOURCE_DIR}/COPYING"
        "-DPROJECT_VERSION=${PROJECT_VERSION}"
        "-DTARGET_TRIPLE=${TRACY_EMBEDDED_NATIVE_TARGET_TRIPLE}"
        "-DARCHITECTURE=${_architecture}"
        "-DPLATFORM=${TRACY_EMBEDDED_NATIVE_PLATFORM}"
        "-DRUNTIME_ABI=${_runtime_abi}"
        "-DDEPLOYMENT_BASELINE=${_deployment_baseline}"
        "-DCOMPILER_ID=${CMAKE_CXX_COMPILER_ID}-${CMAKE_CXX_COMPILER_VERSION}"
        "-DSOURCE_COMMIT=${_source_commit}"
        "-DSOURCE_DIRECTORY=${PROJECT_SOURCE_DIR}"
        "-DNATIVE_PROFILE=${_profile}"
        "-DFORBIDDEN_SOURCE=${PROJECT_SOURCE_DIR}"
        "-DFORBIDDEN_BUILD=${PROJECT_BINARY_DIR}"
        -P "${PROJECT_SOURCE_DIR}/cmake/PackageTracyEmbeddedNative.cmake"
    COMMAND
        "${CMAKE_COMMAND}"
        "-DBUNDLE_DIR=${_package_root}/tracy-embedded-native"
        "-DEXPECTED_TARGET=${TRACY_EMBEDDED_NATIVE_TARGET_TRIPLE}"
        "-DEXPECTED_COMMIT=${_source_commit}"
        -P "${PROJECT_SOURCE_DIR}/cmake/VerifyTracyEmbeddedNative.cmake"
    DEPENDS
        tracy_embedded_capture_native capstone_static libzstd_static
        "${PROJECT_SOURCE_DIR}/cmake/PackageTracyEmbeddedNative.cmake"
        "${PROJECT_SOURCE_DIR}/cmake/VerifyTracyEmbeddedNative.cmake"
    BYPRODUCTS "${_archive}"
    COMMENT "Building and verifying ${_archive_name}"
    VERBATIM
)

message(STATUS "Embedded-native release asset: ${_archive}")
