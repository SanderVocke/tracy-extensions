#include <tracy_embedded_capture/embedded_capture.h>

#include <cstdint>

int main()
{
    return ___tracy_embedded_capture_abi_version() ==
            static_cast<uint32_t>(TRACY_EMBEDDED_CAPTURE_ABI_VERSION)
        ? 0
        : 1;
}
