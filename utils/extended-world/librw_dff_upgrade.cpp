/*
 * Deterministically upgrade one legacy RenderWare clump through librw's real
 * deserializer/serializer. Header rewriting is intentionally not supported:
 * RenderWare versions change the serialized core layouts.
 *
 * Build this small offline tool against the pinned local librw NULL backend.
 * It is an asset-pipeline utility and is never linked into MTA.
 */

#include <rw.h>

#include <cstring>
#include <cstdio>

namespace
{
    bool g_rawPluginFailure = false;

    void* RawConstruct(void* object, rw::int32 offset, rw::int32 size)
    {
        std::memset(static_cast<char*>(object) + offset, 0, size);
        return object;
    }

    void* RawCopy(void* destination, void* source, rw::int32 offset, rw::int32 size)
    {
        std::memcpy(static_cast<char*>(destination) + offset, static_cast<char*>(source) + offset, size);
        return destination;
    }

    rw::Stream* RawRead(rw::Stream* stream, rw::int32 length, void* object, rw::int32 offset, rw::int32 size)
    {
        auto*           storage = reinterpret_cast<rw::uint32*>(static_cast<char*>(object) + offset);
        const rw::int32 capacity = size - sizeof(*storage);
        if (length < 0 || length > capacity)
        {
            g_rawPluginFailure = true;
            std::fprintf(stderr, "raw plugin length %d exceeds capacity %d\n", length, capacity);
            if (length > 0)
                stream->seek(length);
            return stream;
        }
        *storage = static_cast<rw::uint32>(length);
        if (length && stream->read8(storage + 1, static_cast<rw::uint32>(length)) != static_cast<rw::uint32>(length))
        {
            *storage = 0;
            g_rawPluginFailure = true;
            std::fprintf(stderr, "raw plugin payload is truncated\n");
        }
        return stream;
    }

    rw::Stream* RawWrite(rw::Stream* stream, rw::int32, void* object, rw::int32 offset, rw::int32)
    {
        const auto* storage = reinterpret_cast<const rw::uint32*>(static_cast<const char*>(object) + offset);
        if (*storage && stream->write8(storage + 1, *storage) != *storage)
            g_rawPluginFailure = true;
        return stream;
    }

    rw::int32 RawSize(void* object, rw::int32 offset, rw::int32 size)
    {
        const auto* storage = reinterpret_cast<const rw::uint32*>(static_cast<const char*>(object) + offset);
        return *storage <= static_cast<rw::uint32>(size - sizeof(*storage)) ? static_cast<rw::int32>(*storage) : 0;
    }

    template <class Object>
    void RenamePlugin(rw::uint32 id, bool all)
    {
        FORLIST(link, Object::s_plglist.plugins)
        {
            auto* plugin = LLLinkGetData(link, rw::Plugin, inParentList);
            if (plugin->id == id && (all || plugin->size == 0))
                plugin->id ^= 0x80000000U;
        }
    }

    template <class Object>
    void RegisterRawPlugin(rw::uint32 id, rw::int32 maximumBytes, bool replaceExisting = false)
    {
        // Platform modules sometimes reserve this ID before the converter can
        // attach storage. Rename the inert/explicitly replaced handler so the
        // stream callback below cannot bind a zero-byte plugin.
        RenamePlugin<Object>(id, replaceExisting);
        Object::registerPlugin(static_cast<rw::int32>(sizeof(rw::uint32)) + maximumBytes, id, RawConstruct, nullptr, RawCopy);
        Object::registerPluginStream(id, RawRead, RawWrite, RawSize);
    }

    void RegisterPlugins()
    {
        // VC 642.dff has this exact closed plugin grammar. Raw passthrough
        // preserves the legacy payloads while librw upgrades all core layouts.
        rw::registerHAnimPlugin();
        RegisterRawPlugin<rw::Frame>(0x0000011E, 12, true);  // HAnim
        RegisterRawPlugin<rw::Frame>(0x0253F2FE, 15);        // Node name
        rw::registerMeshPlugin();
        RegisterRawPlugin<rw::Geometry>(0x00000105, 4);  // Morph
        RegisterRawPlugin<rw::Texture>(0x00000110, 4);   // Sky mipmap
        rw::registerNativeDataPlugin();
        rw::registerAtomicRightsPlugin();
        rw::registerMaterialRightsPlugin();
        rw::xbox::registerVertexFormatPlugin();
        rw::registerSkinPlugin();
        rw::registerUserDataPlugin();
        rw::registerMatFXPlugin();
        rw::registerUVAnimPlugin();
        rw::ps2::registerADCPlugin();
    }

    bool SameShape(rw::Clump* left, rw::Clump* right)
    {
        return left && right && left->getFrame() && right->getFrame() && left->getFrame()->count() == right->getFrame()->count() &&
               left->atomics.count() == right->atomics.count() && left->lights.count() == right->lights.count() &&
               left->cameras.count() == right->cameras.count();
    }
}

int main(int argc, char** argv)
{
    if (argc != 3)
    {
        std::fprintf(stderr, "usage: %s INPUT.dff OUTPUT.dff\n", argv[0]);
        return 2;
    }

    rw::Engine::init();
    RegisterPlugins();
    if (!rw::Engine::open(nullptr) || !rw::Engine::start())
    {
        std::fprintf(stderr, "librw engine initialization failed\n");
        return 3;
    }
    rw::Texture::setCreateDummies(true);

    rw::StreamFile input;
    if (!input.open(argv[1], "rb") || !rw::findChunk(&input, rw::ID_CLUMP, nullptr, nullptr))
    {
        std::fprintf(stderr, "legacy DFF root could not be opened\n");
        return 4;
    }
    rw::Clump* clump = rw::Clump::streamRead(&input);
    input.close();
    if (!clump || g_rawPluginFailure)
    {
        std::fprintf(stderr, "legacy DFF could not be deserialized\n");
        return 5;
    }

    rw::version = 0x36003;
    rw::build = 0xFFFF;
    rw::StreamFile output;
    if (!output.open(argv[2], "wb") || !clump->streamWrite(&output) || g_rawPluginFailure)
    {
        clump->destroy();
        std::fprintf(stderr, "upgraded DFF could not be serialized\n");
        return 6;
    }
    output.close();

    rw::StreamFile verification;
    rw::Clump*     roundTrip = nullptr;
    if (verification.open(argv[2], "rb") && rw::findChunk(&verification, rw::ID_CLUMP, nullptr, nullptr))
        roundTrip = rw::Clump::streamRead(&verification);
    verification.close();
    if (!SameShape(clump, roundTrip))
    {
        if (roundTrip)
            roundTrip->destroy();
        clump->destroy();
        std::fprintf(stderr, "upgraded DFF failed the librw semantic round-trip\n");
        return 7;
    }
    roundTrip->destroy();
    clump->destroy();
    rw::Engine::stop();
    rw::Engine::close();
    rw::Engine::term();
    return 0;
}
