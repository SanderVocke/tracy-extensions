cmake_minimum_required(VERSION 3.24)

foreach(_required IN ITEMS
    OUTPUT_ROOT OUTPUT_ARCHIVE EMBEDDED_SOURCE CAPSTONE_SOURCE ZSTD_SOURCE
    EMBEDDED_NAME CAPSTONE_NAME ZSTD_NAME HEADER_SOURCE LICENSE_APACHE
    LICENSE_MIT LICENSE_TRACY LICENSE_CAPSTONE LICENSE_CAPSTONE_BSD
    LICENSE_CAPSTONE_LLVM LICENSE_ZSTD COPYING_ZSTD PROJECT_VERSION TARGET_TRIPLE ARCHITECTURE
    PLATFORM RUNTIME_ABI DEPLOYMENT_BASELINE COMPILER_ID SOURCE_COMMIT
    SOURCE_DIRECTORY NATIVE_PROFILE FORBIDDEN_SOURCE FORBIDDEN_BUILD
)
    if(NOT DEFINED ${_required} OR "${${_required}}" STREQUAL "")
        message(FATAL_ERROR "Package input ${_required} is required")
    endif()
endforeach()
if(NOT PROJECT_VERSION STREQUAL "0.7.0")
    message(FATAL_ERROR "Embedded-native bundles must report tracy-extensions 0.7.0")
endif()
execute_process(
    COMMAND git rev-parse HEAD
    WORKING_DIRECTORY "${SOURCE_DIRECTORY}"
    OUTPUT_VARIABLE _current_commit
    OUTPUT_STRIP_TRAILING_WHITESPACE
    RESULT_VARIABLE _git_result
)
execute_process(
    COMMAND git status --porcelain --untracked-files=no
    WORKING_DIRECTORY "${SOURCE_DIRECTORY}"
    OUTPUT_VARIABLE _dirty_files
    OUTPUT_STRIP_TRAILING_WHITESPACE
)
if(NOT _git_result EQUAL 0 OR NOT "${_current_commit}" STREQUAL "${SOURCE_COMMIT}")
    message(FATAL_ERROR "Source commit changed after package configure; reconfigure a clean package build")
endif()
if(NOT _dirty_files STREQUAL "")
    message(FATAL_ERROR "Refusing to package a dirty source tree:\n${_dirty_files}")
endif()

set(_root "${OUTPUT_ROOT}/tracy-embedded-native")
file(REMOVE_RECURSE "${OUTPUT_ROOT}")
file(MAKE_DIRECTORY "${_root}/include/tracy_embedded_capture" "${_root}/lib" "${_root}/licenses")

function(_copy_nonempty source destination)
    if(NOT EXISTS "${source}")
        message(FATAL_ERROR "Missing package input: ${source}")
    endif()
    file(SIZE "${source}" _size)
    if(_size EQUAL 0)
        message(FATAL_ERROR "Empty package input: ${source}")
    endif()
    file(COPY_FILE "${source}" "${destination}" ONLY_IF_DIFFERENT)
endfunction()

_copy_nonempty("${EMBEDDED_SOURCE}" "${_root}/lib/${EMBEDDED_NAME}")
_copy_nonempty("${CAPSTONE_SOURCE}" "${_root}/lib/${CAPSTONE_NAME}")
_copy_nonempty("${ZSTD_SOURCE}" "${_root}/lib/${ZSTD_NAME}")
_copy_nonempty("${HEADER_SOURCE}" "${_root}/include/tracy_embedded_capture/embedded_capture.h")
_copy_nonempty("${LICENSE_APACHE}" "${_root}/licenses/LICENSE-APACHE")
_copy_nonempty("${LICENSE_MIT}" "${_root}/licenses/LICENSE-MIT")
_copy_nonempty("${LICENSE_TRACY}" "${_root}/licenses/LICENSE-TRACY")
_copy_nonempty("${LICENSE_CAPSTONE}" "${_root}/licenses/LICENSE-CAPSTONE")
_copy_nonempty("${LICENSE_CAPSTONE_BSD}" "${_root}/licenses/LICENSE-CAPSTONE-BSD-3-CLAUSE")
_copy_nonempty("${LICENSE_CAPSTONE_LLVM}" "${_root}/licenses/LICENSE-CAPSTONE-LLVM")
_copy_nonempty("${LICENSE_ZSTD}" "${_root}/licenses/LICENSE-ZSTD")
_copy_nonempty("${COPYING_ZSTD}" "${_root}/licenses/COPYING-ZSTD")

# MSVC's librarian preserves absolute object arguments as archive member names.
# Rewrite only that COFF long-name table in place, preserving all offsets and
# object bytes. /Z7 plus /pathmap handles the separate CodeView path records.
if(WIN32)
    if(NOT DEFINED PYTHON_EXECUTABLE OR NOT EXISTS "${PYTHON_EXECUTABLE}" OR
       NOT DEFINED NORMALIZE_MSVC_SCRIPT OR NOT EXISTS "${NORMALIZE_MSVC_SCRIPT}")
        message(FATAL_ERROR "Python and NormalizeMsvcArchive.py are required for MSVC packages")
    endif()
    execute_process(
        COMMAND "${PYTHON_EXECUTABLE}" "${NORMALIZE_MSVC_SCRIPT}"
                "${FORBIDDEN_SOURCE}" "${FORBIDDEN_BUILD}"
                "${_root}/lib/${EMBEDDED_NAME}"
                "${_root}/lib/${CAPSTONE_NAME}"
                "${_root}/lib/${ZSTD_NAME}"
        RESULT_VARIABLE _normalize_result
    )
    if(NOT _normalize_result EQUAL 0)
        message(FATAL_ERROR "Failed to normalize MSVC archive member paths")
    endif()
endif()

file(WRITE "${_root}/licenses/PROVENANCE.txt"
"tracy-extensions_version=${PROJECT_VERSION}\n"
"source_commit=${SOURCE_COMMIT}\n"
"tracy_version=0.13.1\n"
"tracy_protocol=76\n"
"embedded_capture_abi=3\n"
"tracy_commit=05cceee0df3b8d7c6fa87e9638af311dbabc63cb\n"
"capstone_commit=fad9f80564501f083adc92db3ef37f999af28dd0\n"
"zstd_commit=f8745da6ff1ad1e7bab384bd1f9d742439278e99\n"
"ppqsort_commit=21c5a20ca3daf572caaf0a8522db32e27e28fa1d\n"
"compiler=${COMPILER_ID}\n"
"packaging_command=cmake --build <clean-package-build> --config Release --target tracy-embedded-native-package\n"
"license_note=Complete Tracy, Capstone, zstd, project MIT, and project Apache-2.0 license texts are adjacent\n"
)

# The release profile strips checkout/build prefixes from compiler-generated
# paths. Reject any accidental regression before writing the manifest.
foreach(_payload IN ITEMS
    "${_root}/lib/${EMBEDDED_NAME}"
    "${_root}/lib/${CAPSTONE_NAME}"
    "${_root}/lib/${ZSTD_NAME}"
)
    foreach(_forbidden IN ITEMS "${FORBIDDEN_SOURCE}" "${FORBIDDEN_BUILD}")
        file(TO_CMAKE_PATH "${_forbidden}" _forbidden_normalized)
        file(TO_NATIVE_PATH "${_forbidden}" _forbidden_native)
        foreach(_path_variant IN ITEMS "${_forbidden_normalized}" "${_forbidden_native}")
            string(REPLACE "\\" "\\\\" _forbidden_regex "${_path_variant}")
            string(REPLACE "." "\\." _forbidden_regex "${_forbidden_regex}")
            file(STRINGS "${_payload}" _path_leak REGEX "${_forbidden_regex}" LIMIT_COUNT 1)
            if(_path_leak)
                message(FATAL_ERROR
                    "Package payload leaks absolute build path: ${_payload}\n"
                    "matched string: ${_path_leak}"
                )
            endif()
        endforeach()
    endforeach()
endforeach()

set(_files
    "include/tracy_embedded_capture/embedded_capture.h"
    "lib/${EMBEDDED_NAME}"
    "lib/${CAPSTONE_NAME}"
    "lib/${ZSTD_NAME}"
    "licenses/COPYING-ZSTD"
    "licenses/LICENSE-APACHE"
    "licenses/LICENSE-CAPSTONE"
    "licenses/LICENSE-CAPSTONE-BSD-3-CLAUSE"
    "licenses/LICENSE-CAPSTONE-LLVM"
    "licenses/LICENSE-MIT"
    "licenses/LICENSE-TRACY"
    "licenses/LICENSE-ZSTD"
    "licenses/PROVENANCE.txt"
)
list(SORT _files)
string(JOIN "," _expected_files ${_files})

string(CONCAT _manifest
"bundle_format_version=1\n"
"tracy_extensions_version=${PROJECT_VERSION}\n"
"tracy_version=0.13.1\n"
"tracy_protocol=76\n"
"embedded_capture_abi=3\n"
"target_triple=${TARGET_TRIPLE}\n"
"architecture=${ARCHITECTURE}\n"
"platform=${PLATFORM}\n"
"build_profile=release\n"
"native_feature_profile=embedded-capture-v1\n"
"native_definitions=${NATIVE_PROFILE}\n"
"pic_policy=enabled\n"
"runtime_abi=${RUNTIME_ABI}\n"
"deployment_baseline=${DEPLOYMENT_BASELINE}\n"
"compiler=${COMPILER_ID}\n"
"source_commit=${SOURCE_COMMIT}\n"
"embedded_archive=${EMBEDDED_NAME}\n"
"capstone_archive=${CAPSTONE_NAME}\n"
"zstd_archive=${ZSTD_NAME}\n"
"expected_files=${_expected_files}\n"
)
foreach(_file IN LISTS _files)
    file(SHA256 "${_root}/${_file}" _sha256)
    string(APPEND _manifest "sha256.${_file}=${_sha256}\n")
endforeach()
file(WRITE "${_root}/manifest.txt" "${_manifest}")

get_filename_component(_archive_parent "${OUTPUT_ARCHIVE}" DIRECTORY)
file(MAKE_DIRECTORY "${_archive_parent}")
file(REMOVE "${OUTPUT_ARCHIVE}")
if(OUTPUT_ARCHIVE MATCHES "\\.zip$")
    execute_process(
        COMMAND "${CMAKE_COMMAND}" -E tar cf "${OUTPUT_ARCHIVE}" --format=zip
                "--mtime=2025-01-01 00:00:00" tracy-embedded-native
        WORKING_DIRECTORY "${OUTPUT_ROOT}"
        RESULT_VARIABLE _archive_result
    )
else()
    execute_process(
        COMMAND "${CMAKE_COMMAND}" -E tar czf "${OUTPUT_ARCHIVE}" --format=gnutar
                "--mtime=2025-01-01 00:00:00" tracy-embedded-native
        WORKING_DIRECTORY "${OUTPUT_ROOT}"
        RESULT_VARIABLE _archive_result
    )
endif()
if(NOT _archive_result EQUAL 0 OR NOT EXISTS "${OUTPUT_ARCHIVE}")
    message(FATAL_ERROR "Failed to create ${OUTPUT_ARCHIVE}")
endif()
file(SIZE "${OUTPUT_ARCHIVE}" _archive_size)
if(_archive_size EQUAL 0)
    message(FATAL_ERROR "Created empty archive: ${OUTPUT_ARCHIVE}")
endif()
message(STATUS "Created ${OUTPUT_ARCHIVE} (${_archive_size} bytes)")
