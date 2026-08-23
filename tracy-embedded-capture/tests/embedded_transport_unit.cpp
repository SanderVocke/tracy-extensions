#include <array>
#include <atomic>
#include <chrono>
#include <cstring>
#include <iostream>
#include <string_view>
#include <thread>

#include "TracyEmbeddedTransport.hpp"

namespace {

int fail(const char* message) {
    std::cerr << message << '\n';
    return 1;
}

}  // namespace

int main(int argc, char** argv) {
    using namespace tracy::embedded;
    const std::string_view mode = argc == 2 ? argv[1] : "core";
    if (argc > 2 ||
        (mode != "core" && mode != "peer-destroy" && mode != "cancel" &&
         mode != "accept-timeout" && mode != "accept-connect" &&
         mode != "accept-cancel" && mode != "accept-reset")) {
        return fail("usage: embedded-transport-unit "
                    "[core|peer-destroy|cancel|accept-timeout|accept-connect|"
                    "accept-cancel|accept-reset]");
    }
    if (!Configure(8)) return fail("configure failed");
    if (!Listen()) return fail("listen failed");

    void* server = nullptr;
    void* client = nullptr;
    if (mode == "accept-timeout") {
        const auto begin = std::chrono::steady_clock::now();
        if (Accept(client, 80) || client) return fail("accept unexpectedly succeeded");
        const auto elapsed = std::chrono::steady_clock::now() - begin;
        if (elapsed < std::chrono::milliseconds(40)) {
            return fail("accept returned before its bounded wait");
        }
        if (elapsed > std::chrono::seconds(2)) return fail("accept timeout was excessive");
        Reset();
        return 0;
    }
    if (mode == "accept-connect" || mode == "accept-cancel" ||
        mode == "accept-reset") {
        std::atomic<bool> acceptStarted = false;
        bool accepted = false;
        std::thread accepter([&] {
            acceptStarted.store(true, std::memory_order_release);
            accepted = Accept(client, 2000);
        });
        while (!acceptStarted.load(std::memory_order_acquire)) std::this_thread::yield();
        std::this_thread::sleep_for(std::chrono::milliseconds(40));

        const auto wakeBegin = std::chrono::steady_clock::now();
        bool stateChangeSucceeded = true;
        if (mode == "accept-connect") {
            stateChangeSucceeded = Connect(server);
        } else if (mode == "accept-cancel") {
            Cancel();
        } else {
            Reset();
        }
        accepter.join();
        if (!stateChangeSucceeded) return fail("connect failed while accept was waiting");
        const auto wakeElapsed = std::chrono::steady_clock::now() - wakeBegin;
        if (wakeElapsed > std::chrono::milliseconds(500)) {
            return fail("accept did not wake promptly after transport state changed");
        }
        if (accepted != (mode == "accept-connect")) {
            return fail("accept returned the wrong result after transport state changed");
        }
        if (accepted && (!client || !IsValid(client))) {
            return fail("woken accept did not return a valid endpoint");
        }
        DestroyEndpoint(client);
        DestroyEndpoint(server);
        Cancel();
        Reset();
        return 0;
    }

    if (!Connect(server) || !Accept(client)) return fail("rendezvous failed");
    if (!IsValid(server) || !IsValid(client) || Capacity(server) != 8) {
        return fail("invalid endpoints");
    }

    if (mode == "core") {
        std::array<char, 32> source{};
        for (std::size_t i = 0; i < source.size(); ++i) source[i] = static_cast<char>(i);
        std::atomic<bool> writerStarted = false;
        std::atomic<bool> writerDone = false;
        std::thread writer([&] {
            writerStarted = true;
            if (Send(client, source.data(), static_cast<int>(source.size())) !=
                static_cast<int>(source.size())) {
                std::abort();
            }
            writerDone = true;
        });

        while (!writerStarted) std::this_thread::yield();
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
        if (writerDone) return fail("bounded stream did not apply backpressure");

        std::array<char, 32> destination{};
        int offset = 0;
        while (offset != static_cast<int>(destination.size())) {
            const int count = Read(server, destination.data() + offset, 3, 1000);
            if (count <= 0) return fail("ordered read failed");
            offset += count;
        }
        writer.join();
        if (destination != source) return fail("stream ordering or wraparound failed");

        char byte = 0;
        if (Read(server, &byte, 1, 5) != -1) return fail("read timeout was not reported");

        constexpr char reply[] = "reply";
        if (Send(server, reply, 5) != 5 || !HasData(client)) {
            return fail("reverse stream failed");
        }
        std::array<char, 5> replyBuffer{};
        if (Read(client, replyBuffer.data(), 5, 1000) != 5 ||
            std::memcmp(replyBuffer.data(), reply, 5) != 0) {
            return fail("reverse stream contents failed");
        }

        const auto statistics = GetStatistics();
        if (statistics.clientToServerBytes != source.size() ||
            statistics.serverToClientBytes != 5 ||
            statistics.clientToServerHighWater > 8 ||
            statistics.clientToServerHighWater == 0) {
            return fail("transport statistics failed");
        }
    } else {
        std::array<char, 8> fill{};
        if (Send(server, fill.data(), static_cast<int>(fill.size())) !=
            static_cast<int>(fill.size())) {
            return fail("cannot fill reverse stream");
        }
        char byte = 0;
        std::atomic<int> blockedCount = 0;
        std::atomic<int> closeRead = -2;
        std::atomic<int> closeWrite = -2;
        std::thread blockedReader([&] {
            ++blockedCount;
            closeRead = Read(server, &byte, 1, -1);
        });
        std::thread blockedWriter([&] {
            ++blockedCount;
            closeWrite = Send(server, &byte, 1);
        });
        while (blockedCount != 2) std::this_thread::yield();
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
        if (closeRead != -2 || closeWrite != -2) return fail("operation did not block");

        if (mode == "peer-destroy") {
            DestroyEndpoint(client);
        } else {
            Cancel();
            Cancel();
        }
        blockedReader.join();
        blockedWriter.join();
        if (closeRead != 0) return fail("shutdown did not wake blocked reader with EOF");
        if (closeWrite != -1) return fail("shutdown did not wake blocked writer with error");
    }

    CloseEndpoint(client);
    CloseEndpoint(client);
    DestroyEndpoint(client);
    CloseEndpoint(server);
    CloseEndpoint(server);
    DestroyEndpoint(server);
    Cancel();

    if (mode == "core") {
        Reset();
        if (!Configure(16)) return fail("second configure failed");
        server = nullptr;
        client = nullptr;
        // The profiler-side listener survives between on-demand sessions.
        if (!Connect(server) || !Accept(client)) return fail("second rendezvous failed");
        constexpr char second[] = "second session";
        if (Send(client, second, 14) != 14) return fail("second session send failed");
        std::array<char, 14> secondBuffer{};
        if (Read(server, secondBuffer.data(), 14, 1000) != 14 ||
            std::memcmp(secondBuffer.data(), second, 14) != 0) {
            return fail("second session contents failed");
        }
        const auto secondStatistics = GetStatistics();
        if (secondStatistics.clientToServerBytes != 14) {
            return fail("second session statistics were not reset");
        }
        DestroyEndpoint(client);
        DestroyEndpoint(server);
        Cancel();
        Reset();
    }
    return 0;
}
