cmake_minimum_required(VERSION 3.24)
project(tracy-embedded-native-consumer LANGUAGES CXX)

if(NOT DEFINED TRACY_EMBEDDED_NATIVE_DIR)
    message(FATAL_ERROR "TRACY_EMBEDDED_NATIVE_DIR is required")
endif()
set(_root "${TRACY_EMBEDDED_NATIVE_DIR}")
if(WIN32)
    set(_embedded tracy_embedded_capture_native.lib)
    set(_capstone capstone.lib)
    set(_zstd zstd_static.lib)
else()
    set(_embedded libtracy_embedded_capture_native.a)
    set(_capstone libcapstone.a)
    set(_zstd libzstd.a)
endif()
foreach(_library IN ITEMS embedded capstone zstd)
    add_library("package_${_library}" STATIC IMPORTED)
    set_target_properties(
        "package_${_library}" PROPERTIES
        IMPORTED_LOCATION "${_root}/lib/${_${_library}}"
    )
endforeach()

find_package(Threads REQUIRED)
add_executable(package-consumer main.cpp)
target_compile_features(package-consumer PRIVATE cxx_std_20)
target_include_directories(package-consumer PRIVATE "${_root}/include")
target_link_libraries(
    package-consumer PRIVATE
    package_embedded package_capstone package_zstd Threads::Threads ${CMAKE_DL_LIBS}
)
if(WIN32)
    target_link_libraries(package-consumer PRIVATE user32 advapi32 dbghelp ws2_32)
endif()
