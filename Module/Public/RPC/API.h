// Copyright Armchair Developers / Sean Kahler. Licensed under GPLv3.

#pragma once

#include <RPC/API/Launcher.h>
#include <RPC/AsyncRPCManager.h>

#include <memory>

namespace Kyber
{
class API
{
public:
    API(std::string token);

    void Update() const;

    const LauncherInterface* GetLauncherInterface() const
    {
        return m_launcherInterface.get();
    }

private:
    std::unique_ptr<LauncherInterface> m_launcherInterface;

    AsyncRPCManager m_asyncManager;
};
} // namespace Kyber