#include <chrono>
#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <string>
#include <thread>

#include <tracy/Tracy.hpp>
#include <tracy/TracyC.h>

#include "tracy_embedded_capture/embedded_capture.h"

namespace {

constexpr auto Capacity = 256 * 1024;
constexpr auto MemoryLimit = 256LL * 1024 * 1024;

int start(const std::string& path) {
    const auto status = ___tracy_embedded_capture_start(
        path.data(), path.size(), Capacity, MemoryLimit);
    if (status != TRACY_EMBEDDED_CAPTURE_OK) return status;

    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
    while (___tracy_embedded_capture_get_state() != TRACY_EMBEDDED_CAPTURE_CAPTURING) {
        if (std::chrono::steady_clock::now() >= deadline) return 100;
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    return TRACY_EMBEDDED_CAPTURE_OK;
}

void emit(const char* message) {
    ZoneScopedN("embedded.fixture.repeated");
    TracyMessage(message, std::char_traits<char>::length(message));
    TracyPlot("embedded.fixture.repeated.plot", 17.0);
    FrameMarkNamed("embedded.fixture.repeated.frame");
}

}  // namespace

int main(int argc, char** argv) {
    if (argc != 3) {
        std::fprintf(stderr, "usage: tracy-embedded-repeat-fixture FIRST.tracy SECOND.tracy\n");
        return 2;
    }
    const std::string first = argv[1];
    const std::string second = argv[2];
    std::error_code ignored;
    std::filesystem::remove(first, ignored);
    std::filesystem::remove(second, ignored);

    auto status = ___tracy_embedded_capture_start(
        first.data(), first.size(), Capacity, MemoryLimit);
    if (status != TRACY_EMBEDDED_CAPTURE_OK) return 10 + status;
    if (___tracy_embedded_capture_get_state() != TRACY_EMBEDDED_CAPTURE_CONFIGURED) return 20;

    ___tracy_startup_profiler();
    const auto firstDeadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
    while (___tracy_embedded_capture_get_state() != TRACY_EMBEDDED_CAPTURE_CAPTURING) {
        if (std::chrono::steady_clock::now() >= firstDeadline) return 21;
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    if (___tracy_embedded_capture_get_event_storage_bytes() <= 0) return 22;
    emit("embedded.fixture.first-capture");
    status = ___tracy_embedded_capture_stop();
    if (status != TRACY_EMBEDDED_CAPTURE_OK ||
        ___tracy_embedded_capture_get_state() != TRACY_EMBEDDED_CAPTURE_IDLE ||
        ___tracy_embedded_capture_get_event_storage_bytes() != 0) {
        return 23;
    }

    status = start(second);
    if (status != TRACY_EMBEDDED_CAPTURE_OK) return 30 + status;
    if (___tracy_embedded_capture_get_event_storage_bytes() <= 0) return 31;
    emit("embedded.fixture.second-capture");
    status = ___tracy_embedded_capture_stop();
    if (status != TRACY_EMBEDDED_CAPTURE_OK ||
        ___tracy_embedded_capture_get_state() != TRACY_EMBEDDED_CAPTURE_IDLE ||
        ___tracy_embedded_capture_get_event_storage_bytes() != 0) {
        return 32;
    }

    status = ___tracy_embedded_capture_shutdown();
    if (status != TRACY_EMBEDDED_CAPTURE_OK ||
        ___tracy_embedded_capture_get_state() != TRACY_EMBEDDED_CAPTURE_FINISHED ||
        ___tracy_profiler_started() != 0) {
        return 40;
    }
    return std::filesystem::file_size(first) > 0 &&
                   std::filesystem::file_size(second) > 0
               ? 0
               : 41;
}
