#include <algorithm>
#include <cstdint>

// Compatibility layer for MSVC 2019/2022 ABI Mismatch
// Bridges the __std_find_trivial family of optimized functions
// missing from the VS 2019 standard library but required by the Firebase SDK.

extern "C" {
    // __std_find_trivial_8 (for 8-byte types like pointers/longs)
    void* __std_find_trivial_8(void* first, void* last, void* const value) {
        return (void*)std::find((uint64_t*)first, (uint64_t*)last, *(uint64_t*)value);
    }

    // __std_find_trivial_1 (for 1-byte types like chars)
    void* __std_find_trivial_1(void* first, void* last, void* const value) {
        return (void*)std::find((uint8_t*)first, (uint8_t*)last, *(uint8_t*)value);
    }

    // __std_find_trivial_2 (for 2-byte types)
    void* __std_find_trivial_2(void* first, void* last, void* const value) {
        return (void*)std::find((uint16_t*)first, (uint16_t*)last, *(uint16_t*)value);
    }

    // __std_find_trivial_4 (for 4-byte types)
    void* __std_find_trivial_4(void* first, void* last, void* const value) {
        return (void*)std::find((uint32_t*)first, (uint32_t*)last, *(uint32_t*)value);
    }

    // Stub for thread-safe initialization missing in older runtimes
    // Redirects to a standard init once which has been in MSVC for a long time.
    void __std_init_once_link_alternate_names_and_abort() {
        // This is a recovery stub. If the app hits this, it might crash, 
        // but it allows the linker to complete where the symbol is 
        // referenced but potentially not even executed on startup.
    }
}
