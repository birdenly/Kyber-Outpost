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
    Mode3RoundOverGuardEntity(EntityManager* entityManager, NativeEntity* entity, DataContainer* data, const char* typeName)
        : KyberEntity(entity, data)
        , m_typeName(typeName)
    {}

    void Event(EntityEvent* event) override
    {
        if (m_nativeEntity != nullptr && m_nativeEntity->GetRealm() == Realm_Server &&
            g_program->m_server != nullptr && g_program->m_server->ShouldDelayMode3RoundOver())
        {
            KYBER_LOG(Info, "[Mode3] Delayed premature " << m_typeName << " event (0x" << std::hex << event->eventId
                                                            << ") during Ewok Hunt startup window");
            return;
        }

        KyberEntity::Event(event);
    }

private:
    const char* m_typeName;
};

static EntityStaticRegistrar s_roundOverGuardRegistrar(
    "RoundOverEntityData",
    [](EntityManager* em, NativeEntity* entity, DataContainer* data) -> KyberEntityBase* {
        return new Mode3RoundOverGuardEntity(em, entity, data, "RoundOverEntityData");
    },
    false);

static EntityStaticRegistrar s_endOfRoundGuardRegistrar(
    "ServerEndOfRoundStateEntityData",
    [](EntityManager* em, NativeEntity* entity, DataContainer* data) -> KyberEntityBase* {
        return new Mode3RoundOverGuardEntity(em, entity, data, "ServerEndOfRoundStateEntityData");
    },
    false);
} // namespace Kyber
