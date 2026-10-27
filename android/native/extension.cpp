#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <cstring>
#include <vector>

extern "C" {
#include "core.h"
}

using namespace godot;

class OiramEngine : public RefCounted {
    GDCLASS(OiramEngine, RefCounted)

protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("configure", "level", "progress"), &OiramEngine::configure);
        ClassDB::bind_method(D_METHOD("step", "mask"), &OiramEngine::step);
        ClassDB::bind_method(D_METHOD("advance_clock", "seconds"), &OiramEngine::advance_clock);
        ClassDB::bind_method(D_METHOD("frame"), &OiramEngine::frame);
        ClassDB::bind_method(D_METHOD("state"), &OiramEngine::state);
        ClassDB::bind_method(D_METHOD("set_easter_egg", "code"), &OiramEngine::set_easter_egg);
    }

public:
    bool configure(const Dictionary &level, const Dictionary &progress) {
        if (level.get("tiles", Variant()).get_type() != Variant::PACKED_BYTE_ARRAY ||
            level.get("warps", Variant()).get_type() != Variant::PACKED_INT32_ARRAY) return false;
        int64_t width = level.get("width", 0), height = level.get("height", 0);
        PackedByteArray tiles = level["tiles"];
        PackedInt32Array packed_warps = level["warps"];
        if (width < 1 || width > 255 || height < 1 || height > 255 ||
            tiles.size() != width * height || packed_warps.size() > 510 || packed_warps.size() % 2) return false;
        std::vector<uint32_t> warps;
        warps.reserve(packed_warps.size());
        for (int64_t i = 0; i < packed_warps.size(); ++i) {
            if (packed_warps[i] < 0 || packed_warps[i] > 0xffffff) return false;
            warps.push_back(static_cast<uint32_t>(packed_warps[i]));
        }
        return oiram_native_configure(tiles.ptr(), width, height,
            static_cast<int>(level.get("scroll", 0)), static_cast<uint16_t>(static_cast<int>(level.get("color", 0))),
            warps.data(), static_cast<int>(warps.size()), static_cast<int>(level.get("index", 0)),
            static_cast<int>(level.get("count", 1)), static_cast<int>(progress.get("lives", 3)),
            static_cast<int>(progress.get("flags", 0)), static_cast<int>(progress.get("coins", 0)),
            static_cast<int>(progress.get("score", 0)));
    }
    void step(int64_t mask) { oiram_native_step(static_cast<uint32_t>(mask) & 127u); }
    void set_easter_egg(int64_t code) { oiram_native_set_easter_egg(static_cast<int>(code)); }
    void advance_clock(int64_t seconds) {
        if (seconds > 0) oiram_native_clock(static_cast<unsigned>(seconds > 86400 ? 86400 : seconds));
    }
    PackedByteArray frame() const {
        PackedByteArray bytes;
        bytes.resize(320 * 240 * 4);
        std::memcpy(bytes.ptrw(), oiram_native_frame(), bytes.size());
        return bytes;
    }
    Dictionary state() const {
        const auto s = oiram_native_state();
        Dictionary result;
#define OIRAM_STATE(key) result[#key] = s.key
        OIRAM_STATE(x); OIRAM_STATE(y); OIRAM_STATE(vx); OIRAM_STATE(vy);
        OIRAM_STATE(momentum); OIRAM_STATE(flags); OIRAM_STATE(lives);
        OIRAM_STATE(coins); OIRAM_STATE(score); OIRAM_STATE(seconds);
        OIRAM_STATE(exit); OIRAM_STATE(completed); OIRAM_STATE(failed); OIRAM_STATE(level);
#undef OIRAM_STATE
        return result;
    }
};

static void initialize_oiram(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) ClassDB::register_class<OiramEngine>();
}
static void terminate_oiram(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) oiram_native_shutdown();
}

extern "C" GDExtensionBool GDE_EXPORT oiram_library_init(
    GDExtensionInterfaceGetProcAddress get_proc_address, GDExtensionClassLibraryPtr library,
    GDExtensionInitialization *initialization) {
    GDExtensionBinding::InitObject init(get_proc_address, library, initialization);
    init.register_initializer(initialize_oiram);
    init.register_terminator(terminate_oiram);
    init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
