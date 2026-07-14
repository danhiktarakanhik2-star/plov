--[[ 
    Realistic Blood - Server v1.2 MEGA
    Новые функции:
    - Система ран (Wounds): каждая рана кровоточит отдельно, макс rb_wound_max
    - Кровопотеря: rb_bleed_damage наносит урон по интервалу
    - Бинты: rb_bandage_enabled, команда rb_bandage
    - Разбрызгивание на соседей: rb_splatter_on_nearby
    - Расчленёнка: rb_dismember при уроне > threshold и gore 3
    - Зомби/пришельцы цвета
    - Артериальный фонтан: rb_arterial_spray
    - Слипание луж (pool merge) - сервер мержит если рядом
    - Замедление при кровопотере
--]]

if not RB then include("autorun/sh_realistic_blood_init.lua") end

local IsValid = IsValid
local CurTime = CurTime
local math_Clamp = math.Clamp
local bit_band = bit.band

RB.LastHitGroup = RB.LastHitGroup or {}
RB.BleedingEntities = RB.BleedingEntities or {}
RB.RagdollOwners = RB.RagdollOwners or {}
RB.Wounds = RB.Wounds or {} -- [ent] = { {pos, severity, lastBleed, hitgroup, isArtery} }
RB.BleedDamageNext = RB.BleedDamageNext or {}

timer.Create("RB_Cleanup", 30, 0, function()
    for ent,_ in pairs(RB.LastHitGroup) do if not IsValid(ent) then RB.LastHitGroup[ent]=nil end end
    for ent,_ in pairs(RB.BleedingEntities) do if not IsValid(ent) then RB.BleedingEntities[ent]=nil end end
    for ent,_ in pairs(RB.RagdollOwners) do if not IsValid(ent) then RB.RagdollOwners[ent]=nil end end
    for ent,_ in pairs(RB.Wounds) do if not IsValid(ent) then RB.Wounds[ent]=nil end end
end)

hook.Add("ScalePlayerDamage","RB_ScaleP",function(ply,hitgroup,dmginfo)
    if IsValid(ply) then RB.LastHitGroup[ply]=hitgroup ply.RB_LastHitGroup=hitgroup ply.RB_LastDamageTime=CurTime() end
end)
hook.Add("ScaleNPCDamage","RB_ScaleNPC",function(npc,hitgroup,dmginfo)
    if IsValid(npc) then RB.LastHitGroup[npc]=hitgroup npc.RB_LastHitGroup=hitgroup npc.RB_LastDamageTime=CurTime() end
end)

------------------------------------------------------------
-- ОТПРАВКА ЭФФЕКТА
------------------------------------------------------------
local function SendBloodImpact(pos, dir, normal, damage, wType, hitgroup, attacker, victim)
    if GetConVar("rb_enabled"):GetInt()==0 then return end
    if damage<1 then return end
    local cfg = RB.GetConfig()
    if not cfg.enabled then return end
    if cfg.lowViolence then return end -- low violence - без крови, только искры (клиент сделает искры если захочет)

    local col = RB.GetBloodColorForEntity(victim,false)
    if IsValid(victim) and victim.RB_BloodColor then col = victim.RB_BloodColor end

    local isHeadshot = (hitgroup==HITGROUP_HEAD)

    local recipients={}
    for _,ply in ipairs(player.GetAll()) do
        if not IsValid(ply) then continue end
        if ply:GetPos():DistToSqr(pos) < 16000000 then table.insert(recipients,ply)
        elseif ply:TestPVS(victim or ply) then table.insert(recipients,ply) end
    end
    if #recipients==0 then return end

    net.Start("RB_BloodImpact")
        net.WriteVector(pos) net.WriteVector(dir) net.WriteVector(normal)
        net.WriteFloat(damage) net.WriteString(wType or "generic")
        net.WriteUInt(hitgroup or 0,8) net.WriteBool(isHeadshot)
        net.WriteUInt(col.r,8) net.WriteUInt(col.g,8) net.WriteUInt(col.b,8)
        local isCritical = damage>75 or wType=="explosive" or wType=="crush"
        net.WriteBool(isCritical)
    net.Send(recipients)

    -- Splatter на соседей (новая функция)
    if cfg.splatterNearby then
        local near = ents.FindInSphere(pos, cfg.splatterRange or 120)
        for _, ent in ipairs(near) do
            if ent==victim then continue end
            if not (ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot() or ent:GetClass()=="prop_ragdoll") then continue end
            if ent:GetPos():DistToSqr(pos) > (cfg.splatterRange*cfg.splatterRange) then continue end
            -- Отправляем отдельное сообщение для загрязнения
            net.Start("RB_SplatterNearby")
                net.WriteEntity(ent)
                net.WriteVector(pos)
                net.WriteUInt(col.r,8) net.WriteUInt(col.g,8) net.WriteUInt(col.b,8)
                net.WriteFloat(math_Clamp(damage/100,0.2,1))
            net.Send(recipients)
        end
    end

    if cfg.goreLevel>=3 and (wType=="explosive" or wType=="crush" or damage>80) then
        for _,ply in ipairs(recipients) do
            local dist=ply:GetPos():Distance(pos)
            if dist<700 then
                local intensity=math_Clamp(1-dist/700,0.1,1)*(damage/100)
                net.Start("RB_ScreenBlood") net.WriteFloat(math_Clamp(intensity,0,1)) net.WriteFloat(3.0) net.WriteBool(false) net.Send(ply)
            end
        end
    end
end

------------------------------------------------------------
-- РАНЕНИЯ СИСТЕМА
------------------------------------------------------------
local function AddWound(victim, hitgroup, damage, pos)
    local cfg = RB.GetConfig()
    if not cfg.woundSystem then return end
    if not IsValid(victim) or not victim:IsPlayer() then return end -- пока только для игроков, для NPC слишком много
    RB.Wounds[victim] = RB.Wounds[victim] or {}
    if #RB.Wounds[victim] >= cfg.woundMax then
        -- Удаляем самую старую
        table.remove(RB.Wounds[victim],1)
    end
    local isArtery = (hitgroup==HITGROUP_CHEST or hitgroup==HITGROUP_STOMACH or hitgroup==HITGROUP_HEAD) and damage>30
    table.insert(RB.Wounds[victim], {
        pos = pos,
        hitgroup = hitgroup,
        severity = math_Clamp(damage/30,0.3,3),
        lastBleed = CurTime(),
        nextArterial = CurTime()+math.Rand(0.2,1.0),
        isArtery = isArtery,
        dieTime = CurTime()+120 -- рана заживает через 2 мин если не перебинтовать
    })

    -- Если артерия - запускаем артериальный фонтан
    if isArtery and cfg.arterial then
        net.Start("RB_ArterialSpray")
            net.WriteEntity(victim)
            net.WriteVector(pos)
            net.WriteUInt(hitgroup,8)
            net.WriteBool(true)
        net.Broadcast()
    end
end

------------------------------------------------------------
-- EntityTakeDamage
------------------------------------------------------------
hook.Add("EntityTakeDamage","RB_EntityTakeDamage",function(victim,dmginfo)
    local vClass=victim:GetClass()
    local isCorpse = (vClass=="prop_ragdoll") or (vClass=="prop_physics" and victim.RB_IsCorpse)
    local isLiving = victim:IsPlayer() or victim:IsNPC() or victim:IsNextBot() or string.find(vClass,"monster_")
    if not (isLiving or isCorpse) then return end
    if GetConVar("rb_enabled"):GetInt()==0 then return end
    local cfg=RB.GetConfig()
    if not cfg.enabled then return end
    if isCorpse and not cfg.corpseBlood then return end

    local damage=dmginfo:GetDamage()
    if damage<1 then return end
    local dmgType=dmginfo:GetDamageType()
    local isBloodDmg=false
    local wOverride=nil

    if bit_band(dmgType,DMG_BULLET)~=0 then isBloodDmg=true end
    if bit_band(dmgType,DMG_BUCKSHOT)~=0 then isBloodDmg=true end
    if bit_band(dmgType,DMG_CLUB)~=0 then isBloodDmg=true end
    if bit_band(dmgType,DMG_SLASH)~=0 then isBloodDmg=true end
    if bit_band(dmgType,DMG_BLAST)~=0 then isBloodDmg=true end
    if bit_band(dmgType,DMG_BLAST_SURFACE)~=0 then isBloodDmg=true end
    if bit_band(dmgType,DMG_AIRBOAT)~=0 then isBloodDmg=true end
    if bit_band(dmgType,DMG_SNIPER)~=0 then isBloodDmg=true end
    if bit_band(dmgType,DMG_CRUSH)~=0 then isBloodDmg=true wOverride="crush" end
    if bit_band(dmgType,DMG_VEHICLE)~=0 then isBloodDmg=true wOverride="crush" end
    if bit_band(dmgType,DMG_BURN)~=0 and math.random()<0.3 then isBloodDmg=true wOverride="flame" end

    if not isBloodDmg then
        local inf=dmginfo:GetInflictor()
        if IsValid(inf) and inf:IsWeapon() then
            local wt=RB.GetWeaponType(inf,dmgType)
            if wt=="melee" or wt=="generic" then isBloodDmg=true end
        elseif dmgType==DMG_GENERIC then isBloodDmg=true
        elseif isCorpse and damage>5 then isBloodDmg=true end
    end
    if not isBloodDmg then return end

    local dmgPos=dmginfo:GetDamagePosition()
    if dmgPos==vector_origin then
        if isCorpse then
            local phys=victim:GetPhysicsObject()
            dmgPos = IsValid(phys) and phys:GetPos() or victim:WorldSpaceCenter()
        else dmgPos=victim:WorldSpaceCenter() end
    end

    local attacker=dmginfo:GetAttacker()
    local inflictor=dmginfo:GetInflictor()
    local shootDir=Vector(0,0,0)
    if IsValid(attacker) then
        if attacker:IsVehicle() or (IsValid(inflictor) and inflictor:IsVehicle()) then
            shootDir=dmginfo:GetDamageForce():GetNormalized()
            if shootDir:Length()<0.1 then
                local veh=attacker:IsVehicle() and attacker or inflictor
                if IsValid(veh) then shootDir=veh:GetVelocity():GetNormalized() end
            end
            wOverride="crush"
        else
            shootDir=(dmgPos-attacker:EyePos()):GetNormalized()
            if shootDir:Length()<0.1 then shootDir=dmginfo:GetDamageForce():GetNormalized() end
        end
    else
        shootDir=dmginfo:GetDamageForce():GetNormalized()
        if shootDir:Length()<0.1 then shootDir=VectorRand():GetNormalized() end
    end
    local normal=-shootDir
    if isCorpse then normal=normal+VectorRand()*0.3 normal:Normalize() end

    local wType=wOverride or "generic"
    if wType=="generic" then
        if IsValid(inflictor) then wType=RB.GetWeaponType(inflictor,dmgType)
        elseif IsValid(attacker) and attacker:IsPlayer() then
            local wep=attacker:GetActiveWeapon()
            if IsValid(wep) then wType=RB.GetWeaponType(wep,dmgType) end
        end
    end
    if bit_band(dmgType,DMG_CRUSH)~=0 or bit_band(dmgType,DMG_VEHICLE)~=0 then wType="crush" end

    local hitgroup=victim.RB_LastHitGroup or RB.LastHitGroup[victim] or 0
    if isCorpse and hitgroup==0 then hitgroup=math.random(0,3)==0 and HITGROUP_HEAD or HITGROUP_CHEST end

    SendBloodImpact(dmgPos, shootDir, normal, damage, wType, hitgroup, attacker, victim)

    -- Ранения
    if isLiving and cfg.woundSystem then AddWound(victim, hitgroup, damage, dmgPos) end

    -- Следы для живых
    if not isCorpse and cfg.trailsEnabled then
        local maxH=victim:GetMaxHealth() or 100
        local curH=victim:Health()-damage
        if curH < maxH*0.6 then
            RB.BleedingEntities[victim]={startTime=CurTime(), lastTrailTime=RB.BleedingEntities[victim] and RB.BleedingEntities[victim].lastTrailTime or 0, healthPercent=math_Clamp(curH/maxH,0,1), intensity=1-math_Clamp(curH/maxH,0,1)}
        end
    end

    -- Трупные следы
    if isCorpse and damage>15 and cfg.trailsEnabled then
        local tr=util.TraceLine({start=dmgPos+Vector(0,0,10), endpos=dmgPos-Vector(0,0,100), filter=victim, mask=MASK_SOLID})
        if tr.Hit then
            local recipients={}
            for _,ply in ipairs(player.GetAll()) do if ply:GetPos():DistToSqr(tr.HitPos)<16000000 then table.insert(recipients,ply) end end
            if #recipients>0 then
                net.Start("RB_BloodTrail") net.WriteVector(tr.HitPos+tr.HitNormal*0.5) net.WriteVector(tr.HitNormal) net.WriteFloat(math_Clamp(damage/50,0.2,1)) net.WriteEntity(victim) net.Send(recipients)
            end
        end
    end

    if victim:IsPlayer() and cfg.goreLevel>=1 then
        local scrI=math_Clamp(damage/80,0.1,0.9)
        if wType=="crush" then scrI=scrI*1.8 end
        if hitgroup==HITGROUP_HEAD then scrI=scrI*1.5 end
        net.Start("RB_ScreenBlood") net.WriteFloat(math_Clamp(scrI,0,1)) net.WriteFloat(wType=="crush" and 4.0 or 2.5) net.WriteBool(true) net.Send(victim)
        -- stain player
        if cfg.stainPlayer then
            net.Start("RB_StainPlayer") net.WriteEntity(victim) net.WriteFloat(scrI) net.Send(victim)
        end
    end

    -- Пятно на оружии атакующего
    if cfg.bloodOnWeapon and IsValid(attacker) and attacker:IsPlayer() then
        net.Start("RB_StainPlayer") net.WriteEntity(attacker) net.WriteFloat(0.3) net.Send(attacker)
    end

    if wType=="crush" and damage>20 then
        timer.Simple(0.1,function() if IsValid(victim) then HandleEntityDeath(victim, victim:GetPos(), true) end end)
    end

    -- Расчленёнка
    if cfg.dismember and cfg.goreLevel>=3 and damage >= cfg.dismemberThreshold and not isCorpse then
        timer.Simple(0.05, function()
            if not IsValid(victim) then return end
            if victim:IsPlayer() and victim:Alive() then return end -- не расчленяем живых игроков, только трупы? Но можем и живых если умер
            if victim:IsNPC() and victim:Health()<=0 then
                net.Start("RB_Dismember") net.WriteEntity(victim) net.WriteVector(dmgPos) net.WriteUInt(hitgroup,8) net.WriteFloat(damage) net.Broadcast()
            end
        end)
    end
end)

------------------------------------------------------------
-- BLEEDING + WOUND THINK
------------------------------------------------------------
local nextThink=0
hook.Add("Think","RB_BleedingThink",function()
    if CurTime()<nextThink then return end
    nextThink=CurTime()+0.15
    if GetConVar("rb_enabled"):GetInt()==0 then return end
    local cfg=RB.GetConfig()
    if not cfg.enabled then return end

    -- Раненые следы (v1.3: движение ускоряет кровотечение)
    if cfg.trailsEnabled then
        for ent,data in pairs(RB.BleedingEntities) do
            if not IsValid(ent) then RB.BleedingEntities[ent]=nil continue end
            if not ent:Alive() or (ent.Health and ent:Health()<=0) then RB.BleedingEntities[ent]=nil continue end
            local hpP=1
            if ent.Health then hpP=ent:Health()/(ent:GetMaxHealth() or 100) else hpP=data.healthPercent or 0.5 end
            if hpP>0.65 and CurTime()-data.startTime>15 then RB.BleedingEntities[ent]=nil continue end
            local vel=ent:GetVelocity():Length()
            -- Стоячий раненый тоже теряет кровь (капает под ноги), но медленнее
            local moveMult = 1.0
            if vel < 20 then moveMult = 0.15  -- стоит на месте
            elseif vel < 100 then moveMult = 0.5 -- идёт
            elseif vel < 200 then moveMult = 0.8 -- бежит
            else moveMult = 1.2 end -- спринт
            local interval=math_Clamp((0.3+hpP*1.2) / moveMult, 0.08, 2.0)
            if CurTime()-data.lastTrailTime<interval then continue end
            data.lastTrailTime=CurTime() data.healthPercent=hpP
            local pos=ent:GetPos()+Vector(0,0,5)
            local tr=util.TraceLine({start=pos,endpos=pos-Vector(0,0,100),filter=ent,mask=MASK_SOLID_BRUSHONLY})
            if tr.Hit and tr.HitWorld then
                local rec={}
                for _,ply in ipairs(player.GetAll()) do if ply:GetPos():DistToSqr(tr.HitPos)<16000000 then table.insert(rec,ply) end end
                if #rec==0 then continue end
                net.Start("RB_BloodTrail") net.WriteVector(tr.HitPos+tr.HitNormal*0.5) net.WriteVector(tr.HitNormal) net.WriteFloat(1-hpP) net.WriteEntity(ent) net.Send(rec)
                -- v1.3: Стоячий раненый игрок оставляет лужу под ногами
                if vel < 20 and not data._lastPuddleCheck or (CurTime() - (data._lastPuddleCheck or 0)) > 8 then
                    data._lastPuddleCheck = CurTime()
                    local col = RB.GetBloodColorForEntity(ent, false)
                    HandleEntityDeath(ent, tr.HitPos, true) -- лужа под ногами
                end
            end
        end
    end

    -- Раны кровоточат и артериальный пульс
    if cfg.woundSystem then
        for ent,wounds in pairs(RB.Wounds) do
            if not IsValid(ent) or not ent:Alive() then RB.Wounds[ent]=nil continue end
            for idx,w in ipairs(wounds) do
                if CurTime()>w.dieTime then table.remove(wounds,idx) continue end
                -- Обычное кровотечение из раны
                local bleedInterval = w.isArtery and cfg.arterialInterval or 2.0
                -- Движение ускоряет кровотечение
                local vel = ent:GetVelocity():Length()
                if vel > 100 then bleedInterval = bleedInterval * 0.5
                elseif vel > 200 then bleedInterval = bleedInterval * 0.3 end
                if CurTime()-w.lastBleed > bleedInterval then
                    w.lastBleed = CurTime()
                    -- Небольшой брызг из раны
                    local pos = ent:GetPos()+Vector(0,0,40)+VectorRand()*10
                    if ent:IsPlayer() then pos = ent:GetPos()+Vector(0,0,40) end
                    SendBloodImpact(pos, Vector(0,0,-1), Vector(0,0,1), w.severity*5, "generic", w.hitgroup, ent, ent)
                    -- Отправляем каплю с раны на клиент (для визуального эффекта на модели)
                    local rec={}
                    for _,ply in ipairs(player.GetAll()) do if ply:GetPos():DistToSqr(ent:GetPos())<16000000 then table.insert(rec,ply) end end
                    if #rec>0 then
                        net.Start("RB_WoundDrip")
                            net.WriteEntity(ent)
                            net.WriteUInt(w.hitgroup,8)
                            net.WriteFloat(w.severity)
                            net.WriteBool(w.isArtery)
                        net.Send(rec)
                    end
                end
            end
        end
    end

    -- Кровопотеря урон
    if cfg.bleedDamage then
        for ent,data in pairs(RB.BleedingEntities) do
            if not IsValid(ent) or not ent:IsPlayer() then continue end
            if not ent:Alive() then continue end
            local nextDmg = RB.BleedDamageNext[ent] or 0
            if CurTime() >= nextDmg then
                RB.BleedDamageNext[ent] = CurTime()+cfg.bleedInterval
                local dmg=DamageInfo()
                dmg:SetDamage(cfg.bleedAmount)
                dmg:SetDamageType(DMG_GENERIC)
                dmg:SetAttacker(ent)
                dmg:SetInflictor(ent)
                dmg:SetDamageForce(Vector(0,0,0))
                ent:TakeDamageInfo(dmg)
                if cfg.bloodLossSlow then
                    ent:SetWalkSpeed(math.max(50, ent:GetWalkSpeed()-5))
                    ent:SetRunSpeed(math.max(50, ent:GetRunSpeed()-5))
                    timer.Simple(cfg.bleedInterval*2, function() if IsValid(ent) then ent:SetWalkSpeed(200) ent:SetRunSpeed(400) end end)
                end
            end
        end
    end

    -- Трупы перетаскивание следы + скольжение
    if cfg.corpseBlood or cfg.slip then
        for ent,info in pairs(RB.RagdollOwners) do
            if not IsValid(ent) then RB.RagdollOwners[ent]=nil continue end
            local vel=ent:GetVelocity():Length()
            -- Следы
            if vel>80 and cfg.corpseBlood then
                if not ent.RB_LastDragTrail or CurTime()-ent.RB_LastDragTrail>0.25 then
                    ent.RB_LastDragTrail=CurTime()
                    local pos=ent:GetPos()+Vector(0,0,5)
                    local tr=util.TraceLine({start=pos,endpos=pos-Vector(0,0,100),filter=ent,mask=MASK_SOLID_BRUSHONLY})
                    if tr.Hit then
                        local rec={}
                        for _,ply in ipairs(player.GetAll()) do if ply:GetPos():DistToSqr(tr.HitPos)<16000000 then table.insert(rec,ply) end end
                        if #rec>0 then
                            net.Start("RB_BloodTrail") net.WriteVector(tr.HitPos+tr.HitNormal*0.5) net.WriteVector(tr.HitNormal) net.WriteFloat(math_Clamp(vel/300,0.3,1)) net.WriteEntity(ent) net.Send(rec)
                        end
                    end
                end
            end
            -- Скольжение (проверяем игроков рядом с лужей? Тут проверяем игроков на трупах)
            if cfg.slip and vel>100 then
                -- Труп сам не скользит, но игроки рядом скользят - обрабатывается на клиенте по лужам
            end
        end
    end

    -- Скольжение на лужах - серверный вариант (проверяем игроков стоящих на кровяной луже - нужен список луж, но лужи на клиенте. Мы можем по трайлу пола проверять декали? Упрощение: проверяем если игрок в зоне недавно созданной лужи)
    -- Для простоты скольжение обрабатывается на клиенте, сервер только применяет velocity если клиент запросил? Мы сделаем net сообщение от клиента? Пока пропустим, сделаем на клиенте через SetVelocity локально? Но SetVelocity на клиенте не сработает для сервера. Сделаем серверный чек: если игрок стоит на месте где недавно была лужа, шанс поскользнуться
    if cfg.slip then
        -- Эта логика требует хранения луж на сервере, что сложно. Сделаем простой чек: если игрок двигается быстро по крови (трейлы), иногда скользит
        for _,ply in ipairs(player.GetAll()) do
            if not IsValid(ply) or not ply:Alive() then continue end
            if ply:GetVelocity():Length()>200 and RB.BleedingEntities[ply] and math.random()<0.02 then
                local v=ply:GetVelocity()
                v=v* (1+cfg.slipIntensity*0.2)
                v.z=math.max(v.z, 100)
                ply:SetVelocity(v*cfg.slipIntensity*50 + VectorRand()*20)
                if cfg.soundEnabled then ply:EmitSound("physics/flesh/flesh_squishy_impact_hard2.wav", 60, math.random(90,110), cfg.soundVolume*0.4) end
            end
        end
    end
end)

------------------------------------------------------------
-- ЛУЖИ + MERGE
------------------------------------------------------------
RB.ServerPuddles = RB.ServerPuddles or {} -- храним на сервере для merge и slip
function HandleEntityDeath(victim,pos,isNonLethal)
    if not IsValid(victim) and not pos then return end
    local cfg=RB.GetConfig()
    if not cfg.enabled or not cfg.puddleEnabled then return end
    if isNonLethal and cfg.goreLevel<1 then return end

    local deathPos=pos or victim:GetPos()
    local ragdoll=nil
    if IsValid(victim) and (victim:IsPlayer() or victim:IsNPC()) then
        local nearby=ents.FindInSphere(deathPos,120)
        local best=9999
        for _,e in ipairs(nearby) do if e:GetClass()=="prop_ragdoll" then local d=e:GetPos():Distance(deathPos) if d<best then best=d ragdoll=e end end end
    end
    if IsValid(ragdoll) then
        deathPos=ragdoll:GetPos()
        if IsValid(victim) then
            ragdoll.RB_BloodColor=RB.GetBloodColorForEntity(victim,false)
            ragdoll.RB_IsRobot=RB.IsRobot(victim) ragdoll.RB_IsZombie=RB.IsZombie(victim) ragdoll.RB_IsAlien=RB.IsAlien(victim)
            RB.RagdollOwners[ragdoll]={owner=victim,isRobot=ragdoll.RB_IsRobot,bloodColor=ragdoll.RB_BloodColor,dieTime=CurTime()}
        end
    end

    local tr=util.TraceLine({start=deathPos+Vector(0,0,20),endpos=deathPos-Vector(0,0,100),filter=victim,mask=MASK_SOLID})
    local puddlePos=tr.Hit and tr.HitPos or deathPos
    local puddleNormal=tr.Hit and tr.HitNormal or Vector(0,0,1)
    if puddleNormal.z<0.5 then
        local tr2=util.TraceLine({start=deathPos+Vector(0,0,20),endpos=deathPos+Vector(0,0,-100),filter=victim,mask=MASK_SOLID_BRUSHONLY})
        if tr2.Hit then puddlePos=tr2.HitPos puddleNormal=tr2.HitNormal end
    end

    local baseSize=80
    if IsValid(victim) then
        if victim:IsPlayer() then baseSize=100
        elseif victim:IsNPC() then
            local m=victim:GetModel() or ""
            if string.find(m,"hulk") or string.find(m,"super") then baseSize=150 end
        elseif victim:GetClass()=="prop_ragdoll" then baseSize=90 end
    end
    if isNonLethal then baseSize=baseSize*0.6 end
    baseSize=baseSize*cfg.puddleSize

    local col=Color(cfg.colorR,cfg.colorG,cfg.colorB)
    if IsValid(victim) then col=RB.GetBloodColorForEntity(victim,false)
    elseif IsValid(ragdoll) and ragdoll.RB_BloodColor then col=ragdoll.RB_BloodColor end

    -- Merge луж: если рядом есть лужа в пределах mergeDist, увеличиваем её вместо новой
    if cfg.poolMerge then
        for i,p in ipairs(RB.ServerPuddles) do
            if p.pos:Distance(puddlePos) < cfg.poolMergeDist then
                p.size = math.min(p.size + baseSize*0.3, 400)
                puddlePos = p.pos -- используем старую позицию
                baseSize = p.size
                -- обновляем
                RB.ServerPuddles[i].size = baseSize
                break
            end
        end
    end

    table.insert(RB.ServerPuddles, {pos=puddlePos, size=baseSize, color=col, dieTime=CurTime()+cfg.decalLifetime+100})
    -- чистим старые
    for i=#RB.ServerPuddles,1,-1 do if CurTime()>RB.ServerPuddles[i].dieTime then table.remove(RB.ServerPuddles,i) end end

    local recipients={}
    for _,ply in ipairs(player.GetAll()) do if ply:GetPos():DistToSqr(puddlePos)<25000000 then table.insert(recipients,ply) end end
    if #recipients==0 then return end

    net.Start("RB_BloodPuddle")
        net.WriteVector(puddlePos+puddleNormal*1) net.WriteVector(puddleNormal) net.WriteFloat(baseSize) net.WriteFloat(isNonLethal and 6 or 12)
        net.WriteUInt(col.r,8) net.WriteUInt(col.g,8) net.WriteUInt(col.b,8)
    net.Send(recipients)
end

hook.Add("PostPlayerDeath","RB_PostPlayerDeath",function(ply)
    HandleEntityDeath(ply,ply:GetPos())
    -- Смертельное кровотечение: кровь продолжает течь из трупа
    local cfg=RB.GetConfig()
    if cfg.enabled and cfg.corpseBlood then
        local col = RB.GetBloodColorForEntity(ply,false)
        local rec={}
        for _,p in ipairs(player.GetAll()) do if p:GetPos():DistToSqr(ply:GetPos())<16000000 then table.insert(rec,p) end end
        if #rec>0 then
            net.Start("RB_DeathBloodFlow")
                net.WriteEntity(ply)
                net.WriteVector(ply:GetPos())
                net.WriteUInt(col.r,8) net.WriteUInt(col.g,8) net.WriteUInt(col.b,8)
            net.Send(rec)
        end
    end
end)
hook.Add("OnNPCKilled","RB_OnNPCKilled",function(npc,_,_) timer.Simple(0.2,function() if IsValid(npc) then HandleEntityDeath(npc,npc:GetPos()+Vector(0,0,5)) end end) end)
hook.Add("PostEntityTakeDamage","RB_PostTakeDmgCheck",function(ent,dmginfo,taken) if taken and ent:Health()<=0 then if not ent.RB_PuddleCreated then ent.RB_PuddleCreated=true timer.Simple(0.2,function() if IsValid(ent) then HandleEntityDeath(ent,ent:GetPos()) end end) end end end)
hook.Add("PlayerSpawn","RB_PlayerSpawnReset",function(ply) ply.RB_PuddleCreated=false RB.BleedingEntities[ply]=nil RB.LastHitGroup[ply]=nil RB.Wounds[ply]=nil RB.BleedDamageNext[ply]=nil end)

hook.Add("OnEntityCreated","RB_EntityCreated",function(ent)
    timer.Simple(0.1,function()
        if not IsValid(ent) then return end
        ent.RB_PuddleCreated=false
        if ent:GetClass()=="prop_ragdoll" then
            ent.RB_IsCorpse=true
            local pos=ent:GetPos()
            local nearby=ents.FindInSphere(pos,150)
            for _,e in ipairs(nearby) do
                if e:IsPlayer() or e:IsNPC() then
                    if e:Health()<=0 or (e.RB_LastDamageTime and CurTime()-e.RB_LastDamageTime<2) then
                        ent.RB_BloodColor=RB.GetBloodColorForEntity(e,false)
                        ent.RB_IsRobot=RB.IsRobot(e) ent.RB_IsZombie=RB.IsZombie(e) ent.RB_IsAlien=RB.IsAlien(e)
                        RB.RagdollOwners[ent]={owner=e,isRobot=ent.RB_IsRobot,bloodColor=ent.RB_BloodColor,dieTime=CurTime()}
                        break
                    end
                end
            end
            if not ent.RB_BloodColor and RB.IsRobot(ent) then local cfg=RB.GetConfig() ent.RB_BloodColor=Color(cfg.robotColorR,cfg.robotColorG,cfg.robotColorB) ent.RB_IsRobot=true end
            if not ent.RB_BloodColor and RB.IsZombie(ent) then local cfg=RB.GetConfig() ent.RB_BloodColor=Color(cfg.zombieR,cfg.zombieG,cfg.zombieB) ent.RB_IsZombie=true end
            timer.Simple(0.6,function()
                if not IsValid(ent) then return end
                local cfg=RB.GetConfig() if not cfg.enabled or not cfg.puddleEnabled then return end
                if ent.RB_PuddleCreated then return end
                ent.RB_PuddleCreated=true
                local tr=util.TraceLine({start=ent:GetPos()+Vector(0,0,20),endpos=ent:GetPos()-Vector(0,0,100),filter=ent,mask=MASK_SOLID})
                if tr.Hit then
                    local col=ent.RB_BloodColor or Color(cfg.colorR,cfg.colorG,cfg.colorB)
                    local rec={}
                    for _,ply in ipairs(player.GetAll()) do if ply:GetPos():DistToSqr(tr.HitPos)<25000000 then table.insert(rec,ply) end end
                    if #rec>0 then
                        net.Start("RB_BloodPuddle") net.WriteVector(tr.HitPos+tr.HitNormal*1) net.WriteVector(tr.HitNormal) net.WriteFloat(80*cfg.puddleSize) net.WriteFloat(12) net.WriteUInt(col.r,8) net.WriteUInt(col.g,8) net.WriteUInt(col.b,8) net.Send(rec)
                    end
                end
            end)
        end
    end)
end)

------------------------------------------------------------
-- БИНТЫ
------------------------------------------------------------
concommand.Add("rb_bandage",function(ply,cmd,args)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local cfg=RB.GetConfig()
    if not cfg.bandage then ply:ChatPrint("[Realistic Blood] Бинты отключены") return end
    if not RB.Wounds[ply] or #RB.Wounds[ply]==0 then
        if RB.BleedingEntities[ply] then
            RB.BleedingEntities[ply]=nil
            ply:ChatPrint("[Realistic Blood] Кровотечение остановлено (бинт)")
            net.Start("RB_Bandage") net.WriteEntity(ply) net.Send(ply)
            if cfg.soundEnabled then ply:EmitSound("items/medshot4.wav", 75, 100, cfg.soundVolume) end
        else ply:ChatPrint("[Realistic Blood] У вас нет ран") end
        return
    end
    -- Удаляем самую тяжёлую рану
    table.sort(RB.Wounds[ply], function(a,b) return a.severity>b.severity end)
    table.remove(RB.Wounds[ply],1)
    if #RB.Wounds[ply]==0 then RB.BleedingEntities[ply]=nil end
    ply:ChatPrint("[Realistic Blood] Рана перебинтована, осталось ран: "..#RB.Wounds[ply])
    local cfg2=RB.GetConfig()
    net.Start("RB_Bandage") net.WriteEntity(ply) net.WriteEntity(ply) net.Send(ply)
    if cfg2.soundEnabled then ply:EmitSound("items/medshot4.wav", 75, 100, cfg2.soundVolume) end
    -- Небольшое лечение
    if ply:Health()<ply:GetMaxHealth() then ply:SetHealth(math.min(ply:GetMaxHealth(), ply:Health()+5)) end
end)

-- Админ команды
concommand.Add("rb_clearblood",function(ply,cmd,args)
    if IsValid(ply) and not ply:IsAdmin() and not game.SinglePlayer() then ply:ChatPrint("Нужно быть админом") return end
    net.Start("RB_ClearBlood") net.Broadcast()
    print("[Realistic Blood] Кровь очищена "..(IsValid(ply) and ply:Nick() or "Console"))
    RB.BleedingEntities={} RB.ServerPuddles={} RB.Wounds={}
end)

concommand.Add("rb_reset_defaults",function(ply)
    if IsValid(ply) and not ply:IsAdmin() and not game.SinglePlayer() then return end
    local defaults={
        rb_enabled=1, rb_particle_multiplier=1.0, rb_decal_lifetime=300, rb_decal_max=500, rb_puddle_enabled=1, rb_puddle_size=1.0,
        rb_trails_enabled=1, rb_wall_drips=1, rb_sound_enabled=0, rb_sound_volume=0.8,
        rb_color_r=130, rb_color_g=0, rb_color_b=0, rb_quality=2, rb_gore_level=2,
        rb_robot_black_blood=1, rb_robot_color_r=20, rb_robot_color_g=20, rb_robot_color_b=20, rb_corpse_blood=1,
        rb_blood_drying=1, rb_blood_drying_time=120, rb_blood_drying_dark=1,
        rb_blood_slip=0, rb_blood_slip_intensity=0.5,
        rb_wound_system=1, rb_wound_max=5, rb_bleed_damage=0, rb_bleed_damage_interval=2.0, rb_bleed_damage_amount=1,
        rb_bandage_enabled=1, rb_blood_loss_slow=0,
        rb_splatter_on_nearby=1, rb_splatter_range=120,
        rb_blood_on_weapon=0, rb_blood_stain_player=1, rb_stain_time=30,
        rb_dismember=0, rb_dismember_threshold=150,
        rb_blood_in_water=1, rb_pool_merge=1, rb_pool_merge_dist=100,
        rb_zombie_blood=1, rb_zombie_color_r=80, rb_zombie_color_g=100, rb_zombie_color_b=20,
        rb_alien_blood=0, rb_alien_color_r=60, rb_alien_color_g=200, rb_alien_color_b=20,
        rb_arterial_spray=1, rb_arterial_interval=0.8,
        rb_dynamic_quality=0, rb_fps_threshold=50,
        rb_low_violence=0, rb_footstep_sound=1, rb_blood_on_vehicle_wheels=1, rb_custom_config=1
    }
    for k,v in pairs(defaults) do RunConsoleCommand(k,tostring(v)) end
    print("[Realistic Blood] Сброшено по умолчанию")
    if IsValid(ply) then ply:ChatPrint("Сброшено") end
end)

concommand.Add("rb_isrobot",function(ply)
    if not IsValid(ply) then return end
    local tr=ply:GetEyeTrace() local ent=tr.Entity
    if not IsValid(ent) then ply:ChatPrint("Смотри на энтити") return end
    ply:ChatPrint("Class:"..ent:GetClass().." Model:"..(ent:GetModel() or "none").." IsRobot:"..tostring(RB.IsRobot(ent)).." IsZombie:"..tostring(RB.IsZombie(ent)).." IsAlien:"..tostring(RB.IsAlien(ent)).." Blood:"..tostring(RB.GetBloodColorForEntity(ent,false)))
end)

concommand.Add("rb_wounds",function(ply)
    if not IsValid(ply) then return end
    local w=RB.Wounds[ply] or {}
    ply:ChatPrint("Ран: "..#w)
    for i,wd in ipairs(w) do
        ply:ChatPrint(i..": hitgroup "..wd.hitgroup.." severity "..math.Round(wd.severity,2).." artery "..tostring(wd.isArtery))
    end
end)

print("[Realistic Blood] Server v1.3 REALISTIC загружен - реалистичное кровотечение, движение влияет на кровопотерю")
