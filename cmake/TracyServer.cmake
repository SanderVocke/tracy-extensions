include_guard(GLOBAL)

include(FetchContent)

# Tracy's installed CMake package only exposes the instrumentation client. Trace
# loading lives in the version-specific server API, so fetch the exact 0.13.1
# source revision and compile the same source set used by Tracy's CLI tools.
FetchContent_Declare(
    tracy_0131
    URL https://github.com/wolfpld/tracy/archive/05cceee0df3b8d7c6fa87e9638af311dbabc63cb.tar.gz
    URL_HASH SHA256=9447edfc59838348e94f7057999b65612d6a9073020efa5a9bea75200377ee1d
    SOURCE_SUBDIR tracy-query-no-cmakelists
    DOWNLOAD_EXTRACT_TIMESTAMP FALSE
)

# These revisions match Tracy 0.13.1's own dependency declarations. They are
# also commit- and content-pinned so a tag moving cannot change the build.
FetchContent_Declare(
    tracy_ppqsort
    URL https://github.com/GabTux/PPQSort/archive/21c5a20ca3daf572caaf0a8522db32e27e28fa1d.tar.gz
    URL_HASH SHA256=b9b3a1b226bc19fffac2d080d1775b5350573856a61893e444f5ffa7cc982242
    SOURCE_SUBDIR tracy-query-no-cmakelists
    DOWNLOAD_EXTRACT_TIMESTAMP FALSE
)
FetchContent_MakeAvailable(tracy_0131 tracy_ppqsort)

# Install the project-owned embedded transport overlay into the pinned Tracy
# tree. Only targets compiled with TRACY_EMBEDDED_CAPTURE select it; ordinary
# Tracy socket behavior is unchanged. Keep these exact, idempotent edits here so
# CMake and the patched tracy-client-sys build consume one reviewed patch set.
configure_file(
    "${CMAKE_CURRENT_LIST_DIR}/../tracy-embedded-capture/src/TracyEmbeddedTransport.hpp"
    "${tracy_0131_SOURCE_DIR}/public/common/TracyEmbeddedTransport.hpp"
    COPYONLY
)
configure_file(
    "${CMAKE_CURRENT_LIST_DIR}/../tracy-embedded-capture/src/TracyEmbeddedSocket.cpp"
    "${tracy_0131_SOURCE_DIR}/public/common/TracyEmbeddedSocket.cpp"
    COPYONLY
)

set(_tracy_client_source "${tracy_0131_SOURCE_DIR}/public/TracyClient.cpp")
file(READ "${_tracy_client_source}" _tracy_client_contents)
if(NOT _tracy_client_contents MATCHES "TracyEmbeddedSocket.cpp")
    string(REPLACE
        "#include \"common/TracySocket.cpp\""
        "#ifdef TRACY_EMBEDDED_CAPTURE\n#include \"common/TracyEmbeddedSocket.cpp\"\n#else\n#include \"common/TracySocket.cpp\"\n#endif"
        _tracy_client_contents
        "${_tracy_client_contents}"
    )
endif()
if(NOT _tracy_client_contents MATCHES "TracyEmbeddedSocket.cpp")
    message(FATAL_ERROR "Tracy 0.13.1 client socket include patch did not apply")
endif()
file(WRITE "${_tracy_client_source}" "${_tracy_client_contents}")
unset(_tracy_client_contents)
unset(_tracy_client_source)

# Tracy's normal on-demand disconnect handler sends its termination marker
# before draining producer queues. The embedded stop API promises a quiescent
# boundary, so drain the already-committed queues before that marker to prevent
# the capture Worker from observing an empty termination and closing early.
set(_tracy_profiler_source "${tracy_0131_SOURCE_DIR}/public/client/TracyProfiler.cpp")
file(READ "${_tracy_profiler_source}" _tracy_profiler_contents)
if(NOT _tracy_profiler_contents MATCHES "TRACY_EMBEDDED_CAPTURE_DISCONNECT_DRAIN")
    string(REPLACE
        "#endif\n\n    QueueItem terminate;"
        "#endif\n\n#ifdef TRACY_EMBEDDED_CAPTURE\n    // TRACY_EMBEDDED_CAPTURE_DISCONNECT_DRAIN\n    for(;;)\n    {\n        const auto status = Dequeue( token );\n        const auto serialStatus = DequeueSerial();\n        if( status == DequeueStatus::ConnectionLost || serialStatus == DequeueStatus::ConnectionLost ) return;\n        while( m_sock->HasData() )\n        {\n            if( !HandleServerQuery() ) return;\n        }\n        if( status == DequeueStatus::QueueEmpty && serialStatus == DequeueStatus::QueueEmpty )\n        {\n            if( m_bufferOffset != m_bufferStart && !CommitData() ) return;\n            break;\n        }\n    }\n#endif\n\n    QueueItem terminate;"
        _tracy_profiler_contents
        "${_tracy_profiler_contents}"
    )
endif()
if(NOT _tracy_profiler_contents MATCHES "TRACY_EMBEDDED_CAPTURE_DISCONNECT_DRAIN")
    message(FATAL_ERROR "Tracy 0.13.1 reusable disconnect drain patch did not apply")
endif()
if(NOT _tracy_profiler_contents MATCHES "TRACY_EMBEDDED_CAPTURE_DISCONNECT_RESPONSES")
    string(REPLACE
        "    for(;;)\n    {\n        ClearQueues( token );\n        if( m_sock->HasData() )"
        "    for(;;)\n    {\n#ifdef TRACY_EMBEDDED_CAPTURE\n        // TRACY_EMBEDDED_CAPTURE_DISCONNECT_RESPONSES: metadata responses may\n        // enter the queues after the initial drain; serialize rather than discard them.\n        if( Dequeue( token ) == DequeueStatus::ConnectionLost || DequeueSerial() == DequeueStatus::ConnectionLost ) return;\n#else\n        ClearQueues( token );\n#endif\n        if( m_sock->HasData() )"
        _tracy_profiler_contents
        "${_tracy_profiler_contents}"
    )
endif()
if(NOT _tracy_profiler_contents MATCHES "TRACY_EMBEDDED_CAPTURE_DISCONNECT_RESPONSES")
    message(FATAL_ERROR "Tracy 0.13.1 reusable disconnect response patch did not apply")
endif()
file(WRITE "${_tracy_profiler_source}" "${_tracy_profiler_contents}")
unset(_tracy_profiler_contents)
unset(_tracy_profiler_source)

set(_tracy_socket_header "${tracy_0131_SOURCE_DIR}/public/common/TracySocket.hpp")
file(READ "${_tracy_socket_header}" _tracy_socket_contents)
if(NOT _tracy_socket_contents MATCHES "TRACY_EMBEDDED_CAPTURE_FIELDS")
    string(REPLACE
        "    char* m_buf;\n    char* m_bufPtr;\n    std::atomic<int> m_sock;\n    int m_bufLeft;\n\n    struct addrinfo *m_res;\n    struct addrinfo *m_ptr;\n    int m_connSock;"
        "#ifdef TRACY_EMBEDDED_CAPTURE\n    // TRACY_EMBEDDED_CAPTURE_FIELDS\n    void* m_embedded;\n#else\n    char* m_buf;\n    char* m_bufPtr;\n    std::atomic<int> m_sock;\n    int m_bufLeft;\n\n    struct addrinfo *m_res;\n    struct addrinfo *m_ptr;\n    int m_connSock;\n#endif"
        _tracy_socket_contents
        "${_tracy_socket_contents}"
    )
endif()
if(NOT _tracy_socket_contents MATCHES "TRACY_EMBEDDED_CAPTURE_FIELDS")
    message(FATAL_ERROR "Tracy 0.13.1 embedded Socket layout patch did not apply")
endif()
file(WRITE "${_tracy_socket_header}" "${_tracy_socket_contents}")
unset(_tracy_socket_contents)
unset(_tracy_socket_header)

# Tracy 0.13.1 initializes an unsigned byte with -1. GCC accepts this default
# member initializer, but MSVC correctly rejects the narrowing conversion when
# the structural fixture includes TracyEvent.hpp directly. Preserve the exact
# sentinel value with an explicit conversion.
set(_tracy_event_header "${tracy_0131_SOURCE_DIR}/server/TracyEvent.hpp")
file(READ "${_tracy_event_header}" _tracy_event_contents)
if(_tracy_event_contents MATCHES "uint8_t cpu = -1;")
    string(REPLACE
        "uint8_t cpu = -1;"
        "uint8_t cpu = uint8_t( -1 );"
        _tracy_event_contents
        "${_tracy_event_contents}"
    )
    file(WRITE "${_tracy_event_header}" "${_tracy_event_contents}")
endif()
unset(_tracy_event_contents)
unset(_tracy_event_header)

# Tracy 0.13.1 selects x86-64 lzcnt/popcnt intrinsics for every 64-bit Windows
# target. MSVC ARM64 defines _WIN64 but does not provide __lzcnt64, so let that
# target use Tracy's portable fallback instead.
set(_tracy_popcnt_header "${tracy_0131_SOURCE_DIR}/server/TracyPopcnt.hpp")
file(READ "${_tracy_popcnt_header}" _tracy_popcnt_contents)
if(_tracy_popcnt_contents MATCHES "#if defined _WIN64")
    string(REPLACE
        "#if defined _WIN64"
        "#if defined( _WIN64 ) && defined( _M_X64 )"
        _tracy_popcnt_contents
        "${_tracy_popcnt_contents}"
    )
    file(WRITE "${_tracy_popcnt_header}" "${_tracy_popcnt_contents}")
endif()
unset(_tracy_popcnt_contents)
unset(_tracy_popcnt_header)

# Tracy 0.13.1 exposes hardware-sample lookup by address but not iteration. Add
# one read-only accessor at the pinned integration boundary so the hardware
# adapter can provide complete source discovery and queries. A second accessor
# is available only to the synthetic fixture generator when it explicitly
# defines TRACY_QUERY_FIXTURE_ACCESS. Keep this patch narrow and idempotent; a
# Tracy upgrade must revalidate this exact seam.
set(_tracy_worker_header "${tracy_0131_SOURCE_DIR}/server/TracyWorker.hpp")
file(READ "${_tracy_worker_header}" _tracy_worker_contents)
set(_tracy_query_accessors "    const unordered_flat_map<uint64_t, HwSampleData>& GetHwSampleMapForQuery() const { return m_data.hwSamples; }\n#ifdef TRACY_QUERY_FIXTURE_ACCESS\n    auto& GetMutableDataForFixture() { return m_data; }\n#endif")
if(NOT _tracy_worker_contents MATCHES "GetHwSampleMapForQuery")
    string(REPLACE
        "    HwSampleData* GetHwSampleData( uint64_t addr );"
        "    HwSampleData* GetHwSampleData( uint64_t addr );\n${_tracy_query_accessors}"
        _tracy_worker_contents
        "${_tracy_worker_contents}"
    )
elseif(_tracy_worker_contents MATCHES "    auto& GetMutableDataForFixture\\(\\) \\{ return m_data; \\}")
    string(REPLACE
        "    const unordered_flat_map<uint64_t, HwSampleData>& GetHwSampleMapForQuery() const { return m_data.hwSamples; }\n    auto& GetMutableDataForFixture() { return m_data; }"
        "${_tracy_query_accessors}"
        _tracy_worker_contents
        "${_tracy_worker_contents}"
    )
elseif(NOT _tracy_worker_contents MATCHES "TRACY_QUERY_FIXTURE_ACCESS")
    string(REPLACE
        "    const unordered_flat_map<uint64_t, HwSampleData>& GetHwSampleMapForQuery() const { return m_data.hwSamples; }"
        "${_tracy_query_accessors}"
        _tracy_worker_contents
        "${_tracy_worker_contents}"
    )
endif()
if(NOT _tracy_worker_contents MATCHES "RequestEmbeddedDisconnect")
    string(REPLACE
        "    void Shutdown() { m_shutdown.store( true, std::memory_order_relaxed ); }\n    void Disconnect();"
        "    void Shutdown() { m_shutdown.store( true, std::memory_order_relaxed ); }\n#ifdef TRACY_EMBEDDED_CAPTURE\n    void RequestEmbeddedDisconnect() { m_embeddedDisconnectRequested.store( true, std::memory_order_relaxed ); m_netReadCv.notify_one(); }\n#endif\n    void Disconnect();"
        _tracy_worker_contents
        "${_tracy_worker_contents}"
    )
    string(REPLACE
        "    std::atomic<bool> m_shutdown { false };"
        "    std::atomic<bool> m_shutdown { false };\n#ifdef TRACY_EMBEDDED_CAPTURE\n    std::atomic<bool> m_embeddedDisconnectRequested { false };\n#endif"
        _tracy_worker_contents
        "${_tracy_worker_contents}"
    )
endif()
if(NOT _tracy_worker_contents MATCHES "RequestEmbeddedDisconnect")
    message(FATAL_ERROR "Tracy 0.13.1 embedded disconnect header patch did not apply")
endif()
file(WRITE "${_tracy_worker_header}" "${_tracy_worker_contents}")
unset(_tracy_query_accessors)
unset(_tracy_worker_contents)
unset(_tracy_worker_header)

# In a combined manual-lifetime client/server process, Tracy's common
# SetThreadName() also records client metadata. The endpoint-backed Worker must
# start before the client profiler exists, so defer naming only these two early
# server threads in embedded builds.
set(_tracy_worker_source "${tracy_0131_SOURCE_DIR}/server/TracyWorker.cpp")
file(READ "${_tracy_worker_source}" _tracy_worker_source_contents)
if(NOT _tracy_worker_source_contents MATCHES "TRACY_EMBEDDED_CAPTURE_EARLY_THREADS")
    string(REPLACE
        "    m_thread = std::thread( [this] { SetThreadName( \"Tracy Worker\" ); Exec(); } );\n    m_threadNet = std::thread( [this] { SetThreadName( \"Tracy Network\" ); Network(); } );"
        "#ifdef TRACY_EMBEDDED_CAPTURE\n    // TRACY_EMBEDDED_CAPTURE_EARLY_THREADS: client manual lifetime has not started yet.\n    m_thread = std::thread( [this] { Exec(); } );\n    m_threadNet = std::thread( [this] { Network(); } );\n#else\n    m_thread = std::thread( [this] { SetThreadName( \"Tracy Worker\" ); Exec(); } );\n    m_threadNet = std::thread( [this] { SetThreadName( \"Tracy Network\" ); Network(); } );\n#endif"
        _tracy_worker_source_contents
        "${_tracy_worker_source_contents}"
    )
endif()
if(NOT _tracy_worker_source_contents MATCHES "TRACY_EMBEDDED_CAPTURE_EARLY_THREADS")
    message(FATAL_ERROR "Tracy 0.13.1 early Worker thread patch did not apply")
endif()
if(NOT _tracy_worker_source_contents MATCHES "TRACY_EMBEDDED_CAPTURE_REUSABLE_DISCONNECT")
    string(REPLACE
        "            std::unique_lock<std::mutex> lock( m_netReadLock );\n            m_netReadCv.wait( lock, [this] { return !m_netRead.empty(); } );\n            netbuf = m_netRead.front();"
        "            std::unique_lock<std::mutex> lock( m_netReadLock );\n#ifdef TRACY_EMBEDDED_CAPTURE\n            // TRACY_EMBEDDED_CAPTURE_REUSABLE_DISCONNECT: request the normal\n            // on-demand disconnect handshake from Worker's owning thread.\n            m_netReadCv.wait( lock, [this] { return !m_netRead.empty() || m_embeddedDisconnectRequested.load( std::memory_order_relaxed ); } );\n            if( m_embeddedDisconnectRequested.exchange( false, std::memory_order_relaxed ) )\n            {\n                lock.unlock();\n                m_disconnect = true;\n                Query( ServerQueryDisconnect, 0 );\n                continue;\n            }\n#else\n            m_netReadCv.wait( lock, [this] { return !m_netRead.empty(); } );\n#endif\n            netbuf = m_netRead.front();"
        _tracy_worker_source_contents
        "${_tracy_worker_source_contents}"
    )
endif()
if(NOT _tracy_worker_source_contents MATCHES "TRACY_EMBEDDED_CAPTURE_REUSABLE_DISCONNECT")
    message(FATAL_ERROR "Tracy 0.13.1 reusable disconnect patch did not apply")
endif()
file(WRITE "${_tracy_worker_source}" "${_tracy_worker_source_contents}")
unset(_tracy_worker_source_contents)
unset(_tracy_worker_source)

set(CAPSTONE_BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(CAPSTONE_BUILD_STATIC_LIBS ON CACHE BOOL "" FORCE)
set(CAPSTONE_BUILD_LEGACY_TESTS OFF CACHE BOOL "" FORCE)
set(CAPSTONE_BUILD_CSTOOL OFF CACHE BOOL "" FORCE)
set(CAPSTONE_BUILD_CSTEST OFF CACHE BOOL "" FORCE)
set(CAPSTONE_INSTALL OFF CACHE BOOL "" FORCE)
set(CAPSTONE_ARCHITECTURE_DEFAULT OFF CACHE BOOL "" FORCE)
set(CAPSTONE_AARCH64_SUPPORT ON CACHE BOOL "" FORCE)
set(CAPSTONE_ARM_SUPPORT ON CACHE BOOL "" FORCE)
set(CAPSTONE_X86_SUPPORT ON CACHE BOOL "" FORCE)
FetchContent_Declare(
    tracy_capstone
    URL https://github.com/capstone-engine/capstone/archive/fad9f80564501f083adc92db3ef37f999af28dd0.tar.gz
    URL_HASH SHA256=bcd3940bd989cab5fd960ced81a8de99168363b1baaeb943da581a8d0e0ac96a
    DOWNLOAD_EXTRACT_TIMESTAMP FALSE
)
# Capstone inherits PROJECT_VERSION when embedded, so temporarily provide its
# upstream version instead of letting it consume tracy-query's version.
set(_tracy_query_project_version "${PROJECT_VERSION}")
set(PROJECT_VERSION 6.0.0)
FetchContent_MakeAvailable(tracy_capstone)
set(PROJECT_VERSION "${_tracy_query_project_version}")
unset(_tracy_query_project_version)
# Alpha5 creates this helper unconditionally; it is not needed by the parser.
set_target_properties(fuzz_disasm PROPERTIES EXCLUDE_FROM_ALL TRUE)

set(ZSTD_BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_CONTRIB OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_STATIC ON CACHE BOOL "" FORCE)
set(ZSTD_BUILD_COMPRESSION ON CACHE BOOL "" FORCE)
set(ZSTD_BUILD_DECOMPRESSION ON CACHE BOOL "" FORCE)
# TracyWorker also contains trace-writing code that references zdict symbols,
# even though this executable only reads traces.
set(ZSTD_BUILD_DICTBUILDER ON CACHE BOOL "" FORCE)
set(ZSTD_LEGACY_SUPPORT OFF CACHE BOOL "" FORCE)
FetchContent_Declare(
    tracy_zstd
    URL https://github.com/facebook/zstd/archive/f8745da6ff1ad1e7bab384bd1f9d742439278e99.tar.gz
    URL_HASH SHA256=4b0bd1f0cfb25e61b9103c35f27395530ff5b4c0d2513a00fd745849e85ea52c
    SOURCE_SUBDIR build/cmake
    DOWNLOAD_EXTRACT_TIMESTAMP FALSE
)
FetchContent_MakeAvailable(tracy_zstd)
# zstd 1.5.7 has no install-disable option. Excluding its subdirectory keeps
# this application's install component limited to the tracy-query executable.
set_property(
    DIRECTORY "${tracy_zstd_SOURCE_DIR}/build/cmake"
    PROPERTY EXCLUDE_FROM_ALL TRUE
)

find_package(Threads REQUIRED)

add_library(tracy_ppqsort_headers INTERFACE)
target_include_directories(
    tracy_ppqsort_headers
    INTERFACE "${tracy_ppqsort_SOURCE_DIR}/include"
)
target_link_libraries(tracy_ppqsort_headers INTERFACE Threads::Threads)

set(_tracy_common_dir "${tracy_0131_SOURCE_DIR}/public/common")
set(_tracy_server_dir "${tracy_0131_SOURCE_DIR}/server")

add_library(
    tracy_query_tracy_server STATIC
    "${_tracy_common_dir}/tracy_lz4.cpp"
    "${_tracy_common_dir}/tracy_lz4hc.cpp"
    "${_tracy_common_dir}/TracySocket.cpp"
    "${_tracy_common_dir}/TracyStackFrames.cpp"
    "${_tracy_common_dir}/TracySystem.cpp"
    "${_tracy_server_dir}/TracyMemory.cpp"
    "${_tracy_server_dir}/TracyMmap.cpp"
    "${_tracy_server_dir}/TracyPrint.cpp"
    "${_tracy_server_dir}/TracySysUtil.cpp"
    "${_tracy_server_dir}/TracyTaskDispatch.cpp"
    "${_tracy_server_dir}/TracyTextureCompression.cpp"
    "${_tracy_server_dir}/TracyThreadCompress.cpp"
    "${_tracy_server_dir}/TracyWorker.cpp"
)
add_library(TracyQuery::TracyServer ALIAS tracy_query_tracy_server)

target_compile_features(tracy_query_tracy_server PUBLIC cxx_std_20)
target_include_directories(
    tracy_query_tracy_server
    SYSTEM PUBLIC
        "${_tracy_common_dir}"
        "${_tracy_server_dir}"
    PRIVATE
        # Tracy includes this as <capstone.h>, while Capstone's public target
        # exposes the parent directory for <capstone/capstone.h>.
        "${tracy_capstone_SOURCE_DIR}/include/capstone"
)
target_link_libraries(
    tracy_query_tracy_server
    PUBLIC
        capstone_static
        libzstd_static
        tracy_ppqsort_headers
)

unset(_tracy_common_dir)
unset(_tracy_server_dir)
