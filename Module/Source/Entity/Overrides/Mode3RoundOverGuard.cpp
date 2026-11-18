// Copyright Armchair Developers / Sean Kahler. Licensed under GPLv3.
// Modified for Kyber Outpost (LAN Edition) - 2026-11-17.

#include <Entity/NativeEntityManager.h>

#include <Base/Log.h>
#include <Core/Program.h>
#include <Hook/HookManager.h>

namespace Kyber
{
void Mode3EntityBusFireEventHk(EntityBus* inst, const DataContainer* data, const EntityEvent* entityEvent)
{
    static auto trampoline = HookManager::Call(Mode3EntityBusFireEventHk);
    if (inst != nullptr && data != nullptr && entityEvent != nullptr &&
        g_program->m_server != nullptr && g_program->m_server->m_currentMode == "Mode3")
    {
        const uint32_t eid = static_cast<uint32_t>(entityEvent->eventId);
        const bool isServer = inst->GetRealm() == Realm_Server;
        if (g_program->m_server->ShouldDelayMode3RoundOver())
        {
            if (isServer && (eid == 0x41f6410b || eid == 0xd5b34b68 || eid == 0xbedcdf13 || eid == 0xc37da1e2 || eid == 0xaeafbb9 || eid == 0x76a5ad0c))
            {
                const char* typeName = data->getType() ? data->getType()->getName() : "<null>";
                KYBER_LOG(Info, "[Mode3] Suppressed premature EOR trigger " << typeName << " (0x" << std::hex << eid << ")");
                return;
            }
            if (!isServer && (eid == 0x9870b677 || eid == 0xe13f2472))
            {
                const char* typeName = data->getType() ? data->getType()->getName() : "<null>";
                KYBER_LOG(Info, "[Mode3] Suppressed premature client EOR UI trigger " << typeName << " (0x" << std::hex << eid << ")");
                return;
            }
        }
    }
    trampoline(inst, data, entityEvent);
}

class Mode3RoundOverGuardEntity : public KyberEntity<DataContainer>
{
public:
    Mode3RoundOverGuardEntity(EntityManager* entityManager, NativeEntity* entity, DataContainer* data, const char* typeName, bool blockWhenDelayed)
        : KyberEntity(entity, data)
        , m_typeName(typeName)
        , m_blockWhenDelayed(blockWhenDelayed)
    {}

    void Event(EntityEvent* event) override
    {
        if (m_nativeEntity != nullptr && g_program->m_server != nullptr &&
            g_program->m_server->m_currentMode == "Mode3")
        {
            const bool isServer = m_nativeEntity->GetRealm() == Realm_Server;
            if (isServer && g_program->m_server->ShouldDelayMode3RoundOver())
            {
                if (m_blockWhenDelayed)
                {
                    KYBER_LOG(Info, "[Mode3] Delayed premature " << m_typeName << " event (0x" << std::hex << event->eventId
                                                                    << ") during Ewok Hunt startup window");
                    return;
                }
                KYBER_LOG(Info, "[Mode3] Observed server " << m_typeName << " event (0x" << std::hex << event->eventId << ") during grace window");
            }
            else if (!m_blockWhenDelayed)
            {
                KYBER_LOG(Info, "[Mode3] Observed " << (isServer ? "server " : "client ") << m_typeName << " event (0x" << std::hex << event->eventId << ")");
            }
            else if (isServer)
            {
                KYBER_LOG(Info, "[Mode3] Allowing " << m_typeName << " event (0x" << std::hex << event->eventId << ")");
            }
        }

        KyberEntity::Event(event);
    }

private:
    const char* m_typeName;
    bool m_blockWhenDelayed;
};

static EntityStaticRegistrar s_roundOverGuardRegistrar(
    "RoundOverEntityData",
    [](EntityManager* em, NativeEntity* entity, DataContainer* data) -> KyberEntityBase* {
        return new Mode3RoundOverGuardEntity(em, entity, data, "RoundOverEntityData", true);
    },
    false);

static EntityStaticRegistrar s_endOfRoundGuardRegistrar(
    "ServerEndOfRoundStateEntityData",
    [](EntityManager* em, NativeEntity* entity, DataContainer* data) -> KyberEntityBase* {
        return new Mode3RoundOverGuardEntity(em, entity, data, "ServerEndOfRoundStateEntityData", true);
    },
    false);

static EntityStaticRegistrar s_gameRoundGuardRegistrar(
    "GameRoundEntityData",
    [](EntityManager* em, NativeEntity* entity, DataContainer* data) -> KyberEntityBase* {
        return new Mode3RoundOverGuardEntity(em, entity, data, "GameRoundEntityData", false);
    },
    false);

static EntityStaticRegistrar s_serverGameLoopWriterGuardRegistrar(
    "ServerGameLoopStateWriterEntityData",
    [](EntityManager* em, NativeEntity* entity, DataContainer* data) -> KyberEntityBase* {
        return new Mode3RoundOverGuardEntity(em, entity, data, "ServerGameLoopStateWriterEntityData", false);
    },
    false);

static EntityStaticRegistrar s_clientGameLoopWriterGuardRegistrar(
    "ClientGameLoopStateWriterEntityData",
    [](EntityManager* em, NativeEntity* entity, DataContainer* data) -> KyberEntityBase* {
        return new Mode3RoundOverGuardEntity(em, entity, data, "ClientGameLoopStateWriterEntityData", false);
    },
    false);
} // namespace Kyber
