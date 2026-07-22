/*****************************************************************************
 *
 *  PROJECT:     Multi Theft Auto v1.0
 *  LICENSE:     See LICENSE in the top level directory
 *  FILE:        game_sa/CDynamicPool.h
 *  PURPOSE:     Custom implementation for SA pools
 *
 *  Multi Theft Auto is available from https://www.multitheftauto.com/
 *
 *****************************************************************************/

#pragma once

#include <algorithm>
#include <array>
#include <memory>
#include <vector>

template <typename PoolObjT>
class CDynamicPoolPart
{
public:
    struct TestSnapshot
    {
        std::vector<PoolObjT>    items;
        std::vector<std::size_t> unusedIndices;
    };

    explicit CDynamicPoolPart(std::size_t size) : m_size{size}
    {
        m_items = std::make_unique<PoolObjT[]>(size);
        m_unusedIndices.reserve(size);
        for (std::size_t i = 0; i < size; i++)
            m_unusedIndices.push_back(i);
    }

    PoolObjT* AllocateItem()
    {
        std::size_t index = m_unusedIndices.back();
        m_unusedIndices.pop_back();
        return &m_items[index];
    }

    void RemoveItem(PoolObjT* item)
    {
        auto pos = item - m_items.get();
        m_unusedIndices.push_back(pos);
    }

    bool        OwnsItem(PoolObjT* item) const noexcept { return item >= m_items.get() && item < m_items.get() + m_size; }
    bool        HasFreeSize() const noexcept { return m_unusedIndices.size() != 0; }
    std::size_t GetCapacity() const noexcept { return m_size; }
    std::size_t GetUsedSize() const noexcept { return m_size - m_unusedIndices.size(); }

    void CaptureTestSnapshot(TestSnapshot& snapshot) const
    {
        snapshot.items.assign(m_items.get(), m_items.get() + m_size);
        snapshot.unusedIndices = m_unusedIndices;
    }

    bool IsTestSnapshotCompatible(const TestSnapshot& snapshot) const { return snapshot.items.size() == m_size && snapshot.unusedIndices.size() <= m_size; }

    void RestoreTestSnapshot(const TestSnapshot& snapshot)
    {
        std::copy(snapshot.items.begin(), snapshot.items.end(), m_items.get());
        m_unusedIndices = snapshot.unusedIndices;
    }

private:
    std::unique_ptr<PoolObjT[]> m_items;
    std::vector<std::size_t>    m_unusedIndices;
    const std::size_t           m_size;
};

template <std::size_t InitialSize, std::size_t AddSize>
struct PoolGrowAddStrategy
{
    static constexpr std::size_t GetInitialSize() { return InitialSize; }
    static constexpr std::size_t GetNextSize(std::size_t index) { return AddSize; }
};

template <typename PoolObjT, typename GrowStrategy>
class CDynamicPool
{
public:
    struct TestSnapshot
    {
        std::vector<typename CDynamicPoolPart<PoolObjT>::TestSnapshot> parts;
    };

    CDynamicPool()
    {
        constexpr size_t initialSize = GrowStrategy::GetInitialSize();
        m_poolParts.emplace_back(initialSize);
    }

    PoolObjT* AllocateItem()
    {
        for (auto& pool : m_poolParts)
        {
            if (pool.HasFreeSize())
                return pool.AllocateItem();
        }

        try
        {
            return AllocateNewPart().AllocateItem();
        }
        catch (const std::bad_alloc&)
        {
            assert(false && "Could not allocate a memory for CDynamicPoolPart");
        }

        return nullptr;
    }

    void RemoveItem(PoolObjT* item)
    {
        for (auto& pool : m_poolParts)
        {
            if (pool.OwnsItem(item))
            {
                pool.RemoveItem(item);
                return;
            }
        }

        assert(false && "Invalid item for CDynamicPool::RemoveItem");
    }

    std::size_t GetCapacity() const noexcept
    {
        std::size_t size = 0;
        for (auto& pool : m_poolParts)
            size += pool.GetCapacity();

        return size;
    }

    std::size_t GetUsedSize() const noexcept
    {
        std::size_t size = 0;
        for (auto& pool : m_poolParts)
            size += pool.GetUsedSize();

        return size;
    }

    void CaptureTestSnapshot(TestSnapshot& snapshot) const
    {
        snapshot.parts.clear();
        snapshot.parts.resize(m_poolParts.size());
        auto savedPart = snapshot.parts.begin();
        for (const auto& pool : m_poolParts)
        {
            pool.CaptureTestSnapshot(*savedPart);
            ++savedPart;
        }
    }

    bool RestoreTestSnapshot(const TestSnapshot& snapshot)
    {
        if (snapshot.parts.size() != m_poolParts.size())
            return false;

        auto savedPart = snapshot.parts.begin();
        for (const auto& pool : m_poolParts)
        {
            if (!pool.IsTestSnapshotCompatible(*savedPart))
                return false;
            ++savedPart;
        }

        savedPart = snapshot.parts.begin();
        for (auto& pool : m_poolParts)
        {
            pool.RestoreTestSnapshot(*savedPart);
            ++savedPart;
        }
        return true;
    }

    bool SetCapacity(std::size_t newSize)
    {
        if (newSize == 0)
            return false;

        std::size_t currentSize = GetCapacity();

        if (currentSize == newSize)
            return false;
        else if (currentSize < newSize)
        {
            // Grow
            while (currentSize < newSize)
            {
                try
                {
                    auto& nextPart = AllocateNewPart();
                    currentSize += nextPart.GetCapacity();
                }
                catch (const std::bad_alloc&)
                {
                    return false;
                }
            }
        }
        else
        {
            // Shrink
            while (true)
            {
                auto& part = m_poolParts.back();
                if (part.GetUsedSize() != 0)
                    return false;

                currentSize -= part.GetCapacity();
                if (currentSize < newSize)
                    return false;

                m_poolParts.pop_back();

                if (currentSize == newSize)
                    return true;
            }
        }

        return true;
    }

private:
    CDynamicPoolPart<PoolObjT>& AllocateNewPart()
    {
        const std::size_t nextSize = GrowStrategy::GetNextSize(m_poolParts.size());
        m_poolParts.emplace_back(nextSize);
        return m_poolParts.back();
    }

private:
    std::list<CDynamicPoolPart<PoolObjT>> m_poolParts;
};
