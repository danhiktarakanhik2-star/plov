--[[ 
    Realistic Blood - Client v1.2 MEGA
    35+ настроек: drying, slip, wounds, bandage, splatter nearby, stain, dismember, water, merge, zombie/alien, arterial, dynamic quality, low violence, footstep, vehicle wheels
--]]

if not RB then include("autorun/sh_realistic_blood_init.lua") end

local IsValid = IsValid
local CurTime = CurTime
local math_random = math.random
local math_Rand = math.Rand
local math_Clamp = math.Clamp
local VectorRand = VectorRand
local Lerp = Lerp

RB.ClientConfigCache = RB.ClientConfigCache or {}
local function UpdateCache() RB.ClientConfigCache = RB.GetConfig() end
timer.Create("RB_UpdateCache", 0.5, 0, UpdateCache)
UpdateCache()

RB.LoadedParticleMats = {}
local _rb_safeMats = {"effects/blood_core","effects/blood2","effects/blood","decals/blood1","decals/blood2","decals/blood3","decals/blood4","decals/blood5","decals/blood6","decals/blood7","decals/blood8"}
for _,p in ipairs(_rb_safeMats) do local m=Material(p) if m and not m:IsError() then table.insert(RB.LoadedParticleMats,m) end end
if #RB.LoadedParticleMats==0 then table.insert(RB.LoadedParticleMats,Material("effects/blood_core")) end

RB.LoadedDecalMats = {}
for _,p in ipairs({"decals/blood1","decals/blood2","decals/blood3","decals/blood4","decals/blood5","decals/blood6","decals/blood7","decals/blood8","effects/blood_core","effects/blood2"}) do local m=Material(p) if m and not m:IsError() then table.insert(RB.LoadedDecalMats,m) end end
if #RB.LoadedDecalMats==0 then table.insert(RB.LoadedDecalMats,Material("effects/blood_core")) end

RB.PuddleMaterial = nil
RB.RobotOilMaterial = nil
RB.ZombieMaterial = nil
RB.AlienMaterial = nil
local function CreateMats()
    -- UnlitGeneric для плоских квадов — VertexLitGeneric даёт чёрно-фиолетовые артефакты без света
    local bloodBaseTex = "effects/blood_core"
    local testMat = Material("models/flesh")
    if not testMat:IsError() then bloodBaseTex = "models/flesh" end

    RB.PuddleMaterial = CreateMaterial("rb_puddle_v12_ul","UnlitGeneric",{
        ["$basetexture"]=bloodBaseTex,
        ["$translucent"]="1",
        ["$vertexalpha"]="1",
        ["$vertexcolor"]="1"
    })
    if RB.PuddleMaterial:IsError() then RB.PuddleMaterial=Material("effects/blood_core") end

    RB.RobotOilMaterial = CreateMaterial("rb_robot_oil_v12_ul","UnlitGeneric",{
        ["$basetexture"]="effects/blood_core",
        ["$translucent"]="1",
        ["$vertexalpha"]="1",
        ["$vertexcolor"]="1"
    })
    if RB.RobotOilMaterial:IsError() then RB.RobotOilMaterial=Material("effects/blood_core") end

    RB.ZombieMaterial = CreateMaterial("rb_zombie_v12_ul","UnlitGeneric",{
        ["$basetexture"]="effects/blood_core",
        ["$translucent"]="1",
        ["$vertexalpha"]="1",
        ["$vertexcolor"]="1"
    })
    if RB.ZombieMaterial:IsError() then RB.ZombieMaterial=Material("effects/blood_core") end

    RB.AlienMaterial = CreateMaterial("rb_alien_v12_ul","UnlitGeneric",{
        ["$basetexture"]="effects/blood_core",
        ["$translucent"]="1",
        ["$vertexalpha"]="1",
        ["$vertexcolor"]="1"
    })
    if RB.AlienMaterial:IsError() then RB.AlienMaterial=Material("effects/blood_core") end
end
CreateMats()

RB.WeaponProfiles["crush"] = RB.WeaponProfiles["crush"] or {label="Давление/Машина", particles=25, speedMin=100, speedMax=400, decalSizeMin=12, decalSizeMax=40, spread=0.9, hasExitWound=false, goreMult=1.6}
RB.WeaponProfiles["flame"] = RB.WeaponProfiles["flame"] or {label="Огонь", particles=8, speedMin=50, speedMax=150, decalSizeMin=6, decalSizeMax=12, spread=0.6, hasExitWound=false, goreMult=0.8}
RB.WeaponProfiles["crossbow"] = RB.WeaponProfiles["crossbow"] or {label="Арбалет", particles=22, speedMin=200, speedMax=500, decalSizeMin=10, decalSizeMax=30, spread=0.2, hasExitWound=true, exitMult=2.2, goreMult=1.5}

RB.ScreenBloodMat = Material("effects/blood2")

RB.Decals = RB.Decals or {}
RB.Puddles = RB.Puddles or {}
RB.ScreenBloodGroups = RB.ScreenBloodGroups or {}
RB.EmitterPool = RB.EmitterPool or {}
RB.EmitterPoolMax = 4
RB.ActiveEmitters = {}
RB.StainedPlayers = RB.StainedPlayers or {} -- [ent] = dieTime
RB.DynamicFPS = 60

local function IsValidEmitter(em)
    if not em then return false end
    -- В GMod NULL CLuaEmitter это userdata с нулевым указателем
    -- Проверяем через pcall чтобы не крашнуться
    local ok, _ = pcall(function() return em.SetPos ~= nil end)
    return ok
end

local function GetEmitter(pos)
    -- Валидация позиции: не создаём эмиттер в невалидном месте
    if not pos or pos:IsZero() then return nil end
    local e = nil
    -- Ищем валидный эмиттер из пула
    while #RB.EmitterPool > 0 do
        local candidate = table.remove(RB.EmitterPool)
        if IsValidEmitter(candidate) then
            e = candidate
            e:SetPos(pos)
            break
        end
        -- Невалидный эмиттер — пропускаем
    end
    if not e then
        e = ParticleEmitter(pos, false)
        if not IsValidEmitter(e) then return nil end
    end
    table.insert(RB.ActiveEmitters, e)
    return e
end
local function ReleaseEmitter(em)
    if not em then return end
    local ok = pcall(function() em:Finish() end)
    for i,v in ipairs(RB.ActiveEmitters) do if v==em then table.remove(RB.ActiveEmitters,i) break end end
    if ok and #RB.EmitterPool < RB.EmitterPoolMax then table.insert(RB.EmitterPool,em) end
end
hook.Add("ShutDown","RB_CleanupEm",function() for _,em in ipairs(RB.ActiveEmitters) do pcall(function() if em then em:Finish() end end) end for _,em in ipairs(RB.EmitterPool) do pcall(function() if em then em:Finish() end end) end end)

------------------------------------------------------------
-- УТИЛИТЫ
------------------------------------------------------------
function RB.IsPointVisible(pos)
    local ply=LocalPlayer() if not IsValid(ply) then return true end
    local cfg=RB.ClientConfigCache
    if cfg.quality==0 and ply:GetPos():DistToSqr(pos)>25000000 then return false end
    if ply:GetPos():DistToSqr(pos)>16000000 then return false end
    if ply:GetPos():DistToSqr(pos)>900000 then
        local dir=(pos-ply:EyePos()):GetNormalized()
        if ply:EyeAngles():Forward():Dot(dir) < -0.5 then return false end
    end
    return true
end
function RB.GetLODMultiplier(pos)
    local ply=LocalPlayer() if not IsValid(ply) then return 1 end
    local dist=ply:GetPos():Distance(pos) local cfg=RB.ClientConfigCache
    if cfg.quality==0 then if dist>2000 then return 0.2 elseif dist>1000 then return 0.4 else return 0.6 end
    elseif cfg.quality==1 then if dist>2500 then return 0.3 elseif dist>1200 then return 0.6 else return 1 end
    else if dist>3000 then return 0.4 elseif dist>1500 then return 0.7 else return 1 end end
end
function RB.GetRandomBloodColor(base)
    if not base then local cfg=RB.ClientConfigCache base=Color(cfg.colorR,cfg.colorG,cfg.colorB) end
    local isDark = base.r<50 and base.g<50 and base.b<50
    if isDark then
        local v=math_random(-8,8) return Color(math_Clamp(base.r+v,0,255),math_Clamp(base.g+v,0,255),math_Clamp(base.b+v,0,255))
    else
        return Color(math_Clamp(base.r+math_random(-15,15),0,255), math_Clamp(base.g+math_random(-10,10),0,255), math_Clamp(base.b+math_random(-10,10),0,255))
    end
end
function RB.PlayFleshSound(pos,crit)
    local cfg=RB.ClientConfigCache if not cfg.soundEnabled then return end
    local vol=math_Clamp(cfg.soundVolume*(crit and 1.2 or 1),0,1)
    local snd=RB.FleshSounds[math_random(1,#RB.FleshSounds)]
    sound.Play(snd,pos,75,math_random(90,110),vol)
end
function RB.PlayDripSound(pos)
    local cfg=RB.ClientConfigCache if not cfg.soundEnabled then return end if math_random()>0.35 then return end
    local snd=RB.DripSounds[math_random(1,#RB.DripSounds)] sound.Play(snd,pos,65,math_random(85,115),cfg.soundVolume*0.5)
end
function RB.PlayRobotSound(pos)
    local cfg=RB.ClientConfigCache if not cfg.soundEnabled then return end
    local snd="physics/metal/metal_sheet_impact_bullet"..math_random(1,2)..".wav" sound.Play(snd,pos,75,math_random(85,105),cfg.soundVolume*0.6)
end
function RB.PlaySquish(pos)
    local cfg=RB.ClientConfigCache if not cfg.soundEnabled or not cfg.footstepSound then return end
    if math_random()>0.5 then return end
    local snd=RB.SquishSounds[math_random(1,#RB.SquishSounds)] sound.Play(snd,pos,65,math_random(80,100),cfg.soundVolume*0.4)
end
function RB.IsWater(pos) return bit.band(util.PointContents(pos), CONTENTS_WATER)==CONTENTS_WATER end

------------------------------------------------------------
-- DYNAMIC QUALITY по FPS
------------------------------------------------------------
local lastFPSCheck=0
local fpsSamples={}
hook.Add("Think","RB_DynamicQuality",function()
    local cfg=RB.ClientConfigCache
    if not cfg.dynamicQuality then return end
    if CurTime()-lastFPSCheck < 1 then return end
    lastFPSCheck=CurTime()
    local fps = 1/FrameTime()
    table.insert(fpsSamples,fps) if #fpsSamples>10 then table.remove(fpsSamples,1) end
    local avg=0 for _,v in ipairs(fpsSamples) do avg=avg+v end avg=avg/#fpsSamples
    RB.DynamicFPS=avg
    if avg < cfg.fpsThreshold and cfg.quality>0 then
        RunConsoleCommand("rb_quality", tostring(cfg.quality-1))
        print("[Realistic Blood] FPS низкий ("..math.Round(avg).."), понижаю качество до "..(cfg.quality-1))
    elseif avg > cfg.fpsThreshold+15 and cfg.quality<2 then
        RunConsoleCommand("rb_quality", tostring(cfg.quality+1))
        print("[Realistic Blood] FPS высокий ("..math.Round(avg).."), повышаю качество до "..(cfg.quality+1))
    end
end)

------------------------------------------------------------
-- ДЕКАЛИ с высыханием
------------------------------------------------------------
function RB.AddDecal(pos, normal, size, mat, isFloor, alpha, colorOverride)
    local cfg=RB.ClientConfigCache
    if not pos or not normal then return nil end
    if normal:LengthSqr() < 0.5 then return nil end
    if cfg.lowViolence then -- low violence - искры вместо крови
        local ed=EffectData() ed:SetOrigin(pos) ed:SetNormal(normal) ed:SetMagnitude(1) ed:SetScale(1) util.Effect("ManhackSparks",ed) return nil
    end
    if #RB.Decals >= cfg.decalMax then for i=1,math.min(10,#RB.Decals) do table.remove(RB.Decals,1) end end
    local col=colorOverride or Color(cfg.colorR,cfg.colorG,cfg.colorB)
    local entry={
        pos=pos+normal*0.5, normal=normal, size=size or math_random(10,25),
        mat=mat or RB.LoadedDecalMats[math_random(1,#RB.LoadedDecalMats)],
        isFloor=isFloor or false, dieTime=CurTime()+cfg.decalLifetime, birthTime=CurTime(),
        alpha=alpha or 255, rotation=math_random(0,360), lifetime=cfg.decalLifetime,
        color=col, originalColor=Color(col.r,col.g,col.b), isDrying=false
    }
    table.insert(RB.Decals,entry)
    if cfg.quality>0 then
        local decalName=RB.DecalMaterials[math_random(1,#RB.DecalMaterials)] or "Blood"
        local tr=util.TraceLine({start=pos+normal*2, endpos=pos-normal*8, mask=MASK_SOLID})
        if tr.Hit then util.Decal(decalName, tr.HitPos+tr.HitNormal*0.1, tr.HitPos-tr.HitNormal*0.1) end
    end
    return entry
end

function RB.SpawnDecalFromParticle(hitPos, hitNormal, pSize, vel, bloodColor)
    local cfg=RB.ClientConfigCache
    if not hitPos or not hitNormal then return end
    if hitNormal:LengthSqr() < 0.5 then return end -- невалидная нормаль
    if not RB.IsPointVisible(hitPos) then return end
    if cfg.bloodInWater and RB.IsWater(hitPos) then -- в воде кровь растворяется
        -- делаем эффект размытия
        local emitter=GetEmitter(hitPos)
        if emitter then
            for i=1,3 do
                local par=emitter:Add(RB.LoadedParticleMats[1], hitPos)
                if par then
                    par:SetVelocity(VectorRand()*20)
                    par:SetDieTime(math_Rand(1,2))
                    par:SetStartAlpha(60) par:SetEndAlpha(0)
                    par:SetStartSize(pSize) par:SetEndSize(pSize*3)
                    par:SetColor(bloodColor.r,bloodColor.g,bloodColor.b)
                end
            end
            timer.Simple(2.1,function() ReleaseEmitter(emitter) end)
        end
        return
    end
    local isFloor=hitNormal.z>0.7
    local size=pSize or 10
    local speed=vel and vel:Length() or 200
    size=size*(0.5+speed/500) size=math_Clamp(size,4,60)
    if isFloor then size=size*1.2 else size=size*0.9 end
    local mat=RB.LoadedDecalMats[math_random(1,#RB.LoadedDecalMats)]
    local col=bloodColor or Color(cfg.colorR,cfg.colorG,cfg.colorB)
    RB.AddDecal(hitPos, hitNormal, size, mat, isFloor, 255, col)
    if not isFloor and cfg.wallDrips and hitNormal.z<0.5 and hitNormal.z>-0.5 then if math_random()<0.35 then RB.CreateWallDrip(hitPos, hitNormal, size, col) end end
    if isFloor and math_random()<0.08 then RB.PlayDripSound(hitPos) end
end

function RB.CreateWallDrip(pos, normal, baseSize, bloodColor)
    local cfg=RB.ClientConfigCache if not cfg.wallDrips or cfg.quality==0 then return end
    local cnt=math_random(2,5) local cur=pos
    for i=1,cnt do
        local delay=i*math_Rand(0.4,0.9)
        timer.Simple(delay,function()
            if not RB.ClientConfigCache.wallDrips then return end
            local down=Vector(0,0,-(i*math_Rand(8,16)))
            local newPos=cur+down+VectorRand()*1.5
            local tr=util.TraceLine({start=newPos+normal*5, endpos=newPos-normal*10, mask=MASK_SOLID})
            if tr.Hit and tr.HitNormal:Dot(normal)>0.5 then
                local size=baseSize*(1-i*0.15) size=math_Clamp(size*0.7,3,20)
                local mat=RB.LoadedDecalMats[math_random(1,#RB.LoadedDecalMats)]
                RB.AddDecal(tr.HitPos, tr.HitNormal, size, mat, false, 200-i*20, bloodColor)
                cur=tr.HitPos
            end
        end)
    end
end

hook.Add("PostDrawTranslucentRenderables","RB_RenderDecals",function()
    local cfg=RB.ClientConfigCache if not cfg.enabled then return end if #RB.Decals==0 then return end
    local ply=LocalPlayer() if not IsValid(ply) then return end
    local eye=ply:EyePos()
    for i=#RB.Decals,1,-1 do
        local dec=RB.Decals[i] if not dec then continue end
        local left=dec.dieTime-CurTime() if left<=0 then table.remove(RB.Decals,i) continue end
        if eye:DistToSqr(dec.pos)>9000000 then continue end
        local alpha=255
        if left<10 then alpha=math_Clamp((left/10)*255,0,255) end

        -- Высыхание крови - коричневеет со временем (новая функция)
        local col = dec.color or Color(cfg.colorR,cfg.colorG,cfg.colorB)
        if cfg.drying then
            local age=CurTime()-dec.birthTime
            local dryProg=math_Clamp(age / cfg.dryingTime,0,1)
            if dryProg>0.1 then
                -- оригинал красный, высохший коричневый 60,20,10 или темнее если robot?
                local isDark = dec.originalColor.r<50 and dec.originalColor.g<50 and dec.originalColor.b<50
                if not isDark then
                    -- lerp к коричневому
                    local dried = Color(60, 15, 10)
                    if cfg.dryingDark then dried = Color(40,10,5) end
                    col = Color(Lerp(dryProg, dec.originalColor.r, dried.r), Lerp(dryProg, dec.originalColor.g, dried.g), Lerp(dryProg, dec.originalColor.b, dried.b))
                else
                    -- чёрная кровь (роботы) становится ещё темнее и серее
                    local dried = Color(10,10,10)
                    col = Color(Lerp(dryProg, dec.originalColor.r, dried.r), Lerp(dryProg, dec.originalColor.g, dried.g), Lerp(dryProg, dec.originalColor.b, dried.b))
                end
            end
        end

        render.SetMaterial(dec.mat)
        render.DrawQuadEasy(dec.pos, dec.normal, dec.size, dec.size, Color(col.r,col.g,col.b, alpha*(dec.alpha and dec.alpha/255 or 1)), dec.rotation)
    end
end)

------------------------------------------------------------
-- ЛУЖИ с merge и разными материалами
------------------------------------------------------------
function RB.CreatePuddle(pos, normal, maxSize, growthDuration, colorOverride)
    local cfg=RB.ClientConfigCache
    if not cfg.puddleEnabled or not cfg.enabled then return end
    if normal.z<0.4 then return end
    local col=colorOverride or Color(cfg.colorR,cfg.colorG,cfg.colorB)
    local isRobot = col.r<50 and col.g<50 and col.b<50 and (cfg.robotBlackBlood and col.r==cfg.robotColorR or true) -- упрощение
    local isZombie = cfg.zombieBlood and col.r==cfg.zombieR and col.g==cfg.zombieG
    local isAlien = cfg.alienBlood and col.r==cfg.alienR

    -- Merge проверка на клиенте тоже
    if cfg.poolMerge then
        for _,p in ipairs(RB.Puddles) do
            if p.pos:Distance(pos) < cfg.poolMergeDist then
                p.maxSize = math.min(p.maxSize + maxSize*0.4, 500)
                p.dieTime = math.max(p.dieTime, CurTime()+cfg.decalLifetime+100)
                return -- не создаём новую, увеличиваем старую
            end
        end
    end

    local mat=RB.PuddleMaterial
    if isRobot then mat=RB.RobotOilMaterial
    elseif isZombie then mat=RB.ZombieMaterial
    elseif isAlien then mat=RB.AlienMaterial end

    local puddle={
        pos=pos, normal=normal, maxSize=maxSize or 80, currentSize=5,
        startTime=CurTime(), growthDuration=growthDuration or 12,
        dieTime=CurTime()+(cfg.decalLifetime or 300)+100,
        alpha=255, rotation=math_random(0,360), subPuddles={}, mat=mat, color=col
    }
    local subCount=math_random(5,8)
    for i=1,subCount do
        local ang=(i/subCount)*360+math_random(-15,15)
        local dist=math_Rand(maxSize*0.2,maxSize*0.6)
        local offset=Vector(math.cos(math.rad(ang))*dist, math.sin(math.rad(ang))*dist,0)
        table.insert(puddle.subPuddles,{offset=offset,size=math_Rand(maxSize*0.3,maxSize*0.7),rotation=math_random(0,360)})
    end
    table.insert(RB.Puddles,puddle)
    for _,sub in ipairs(puddle.subPuddles) do
        local dPos=pos+sub.offset
        local mat2=RB.LoadedDecalMats[math_random(1,#RB.LoadedDecalMats)]
        RB.AddDecal(dPos, normal, sub.size*0.6, mat2, true, 230, col)
    end
    if cfg.soundEnabled and math_random()<0.5 then
        local snd= isRobot and "ambient/machines/thumper_dust.wav" or RB.PuddleSounds[math_random(1,#RB.PuddleSounds)]
        sound.Play(snd,pos,70,math_random(90,100),cfg.soundVolume*0.3)
    end
end

hook.Add("PostDrawTranslucentRenderables","RB_RenderPuddles",function()
    local cfg=RB.ClientConfigCache if not cfg.enabled or not cfg.puddleEnabled then return end if #RB.Puddles==0 then return end
    local ply=LocalPlayer() if not IsValid(ply) then return end
    local eye=ply:EyePos()
    for i=#RB.Puddles,1,-1 do
        local pud=RB.Puddles[i] if not pud then continue end if CurTime()>pud.dieTime then table.remove(RB.Puddles,i) continue end
        if eye:DistToSqr(pud.pos)>16000000 then continue end
        local elapsed=CurTime()-pud.startTime local prog=math_Clamp(elapsed/pud.growthDuration,0,1) prog=1-math.pow(1-prog,2)
        pud.currentSize=Lerp(prog,5,pud.maxSize)
        local alpha=math_Clamp(prog*255,60,255)
        local c=pud.color or Color(cfg.colorR,cfg.colorG,cfg.colorB)
        -- drying для луж тоже
        if cfg.drying then
            local age=CurTime()-pud.startTime
            local dryProg=math_Clamp(age/cfg.dryingTime,0,1)
            if dryProg>0.2 and not (c.r<50 and c.g<50) then
                local dried=Color(60,15,10)
                c=Color(Lerp(dryProg, c.r, dried.r), Lerp(dryProg, c.g, dried.g), Lerp(dryProg, c.b, dried.b))
            end
        end
        local col=Color(c.r,c.g,c.b,alpha)
        render.SetMaterial(pud.mat)
        render.DrawQuadEasy(pud.pos, pud.normal, pud.currentSize, pud.currentSize, col, pud.rotation)
        for _,sub in ipairs(pud.subPuddles) do
            local subSize=sub.size*prog local subPos=pud.pos+sub.offset*prog
            render.DrawQuadEasy(subPos, pud.normal, subSize, subSize, col, sub.rotation)
        end
    end
end)

------------------------------------------------------------
-- ЧАСТИЦЫ + АРТЕРИАЛЬНЫЙ ФОНТАН + LOW VIOLENCE
------------------------------------------------------------
function RB.CreateBloodSplash(pos, dir, normal, damage, wType, hitgroup, baseColor, isCritical, isHeadshot)
    local cfg=RB.ClientConfigCache if not cfg.enabled then return end if not RB.IsPointVisible(pos) then return end
    if cfg.lowViolence then -- low violence - искры
        local ed=EffectData() ed:SetOrigin(pos) ed:SetNormal(normal) ed:SetMagnitude(2) ed:SetScale(2) util.Effect("ManhackSparks",ed) return
    end
    local profile=RB.WeaponProfiles[wType] or RB.WeaponProfiles["generic"]
    if profile.noDecal and math_random()<0.7 then return end -- огонь меньше крови
    local hitMult=RB.HitGroupMultipliers[hitgroup] or 1.0
    local qual=1.0 if cfg.quality==0 then qual=0.35 elseif cfg.quality==1 then qual=0.7 end
    local gore=1.0 if cfg.goreLevel==1 then gore=0.7 elseif cfg.goreLevel==3 then gore=1.4 end
    local dmgMult=1+math_Clamp(damage,0,150)/70
    local baseCount=profile.particles
    if wType=="crush" then baseCount=baseCount*1.5 end
    local final=math.floor(baseCount*hitMult*gore*cfg.particleMult*qual*dmgMult)
    final=final*RB.GetLODMultiplier(pos)
    if hitgroup==HITGROUP_HEAD then final=final*1.3 end if isCritical then final=final*1.5 end if wType=="crush" then final=final*1.2 end
    final=math_Clamp(math.floor(final),2,220) if final<1 then return end
    local emitter=GetEmitter(pos)
    if not emitter then return end
    if not baseColor then baseColor=Color(cfg.colorR,cfg.colorG,cfg.colorB) end
    local isRobot = baseColor.r<50 and baseColor.g<50 and baseColor.b<50
    local speedMin=profile.speedMin local speedMax=profile.speedMax local spread=profile.spread or 0.5
    if wType=="crush" then spread=1.0 end
    local hasExit=profile.hasExitWound and (damage>20 or isHeadshot)
    local function SpawnBatch(origin, direction, count, isExit)
        local exitBoost=isExit and (profile.exitMult or 1.5) or 1.0
        for i=1,count do
            local cat=math_random(1,100) local pSize,life,isLarge
            if cat<=50 then pSize=math_Rand(1,3) life=math_Rand(0.5,1.2) isLarge=false
            elseif cat<=85 then pSize=math_Rand(3,6) life=math_Rand(0.8,2.0) isLarge=false
            else pSize=math_Rand(6,12) life=math_Rand(1.2,3.0) isLarge=true end
            if wType=="crush" and cat<=70 then pSize=pSize*1.3 life=life*1.2 end
            local mat=RB.LoadedParticleMats[math_random(1,#RB.LoadedParticleMats)]
            local par=emitter:Add(mat, origin) if not par then continue end
            local spreadVec=VectorRand()*spread
            local velDir
            if wType=="crush" then velDir=(direction*0.5 + spreadVec + Vector(0,0,math_Rand(0.1,0.4))):GetNormalized()
            else velDir=(direction+spreadVec+normal*math_Rand(0.2,0.6)):GetNormalized() end
            if isExit then velDir=(direction+VectorRand()*spread*0.5):GetNormalized() end
            local speed=math_Rand(speedMin,speedMax)*exitBoost*math_Rand(0.7,1.3)
            if wType=="crush" then speed=speed*0.8 end
            par:SetVelocity(velDir*speed) par:SetDieTime(life) par:SetLifeTime(0) par:SetStartAlpha(255) par:SetEndAlpha(0)
            par:SetStartSize(pSize) par:SetEndSize(pSize*0.7) par:SetGravity(Vector(0,0,math_Rand(-500,-300)))
            par:SetAirResistance(math_Rand(20,80)) par:SetRoll(math_Rand(0,360)) par:SetRollDelta(math_Rand(-4,4))
            local col=RB.GetRandomBloodColor(baseColor)
            if isLarge and not isRobot then col.r=math_Clamp(col.r*0.8,0,255) col.g=math_Clamp(col.g*0.8,0,255) col.b=math_Clamp(col.b*0.8,0,255) end
            par:SetColor(col.r,col.g,col.b) par:SetCollide(true) par:SetBounce(0.1)
            local sizeForDecal=pSize*3 local colForDecal=baseColor
            par:SetCollideCallback(function(part, hitPos, hitNormal) RB.SpawnDecalFromParticle(hitPos, hitNormal, sizeForDecal, part:GetVelocity(), colForDecal) part:SetDieTime(0) end)
        end
    end
    if profile.delayed then timer.Simple(math_Rand(0.05,0.15),function() if IsValid(emitter) then SpawnBatch(pos, dir, final,false) end end) else SpawnBatch(pos, dir, final,false) end
    if hasExit then local ePos=pos+dir*math_Rand(10,25) local eCnt=math.floor(final*(profile.exitMult or 1.5)*0.8) timer.Simple(math_Rand(0.01,0.05),function() SpawnBatch(ePos, dir, eCnt,true) end) end
    if wType=="crush" then
        timer.Simple(0.05,function()
            local f=dir f.z=0 f:Normalize()
            for i=1,math_random(4,7) do
                local off=f*(i*math_Rand(15,30)) + VectorRand()*10 off.z=0
                local check=pos+off+Vector(0,0,10)
                local tr=util.TraceLine({start=check,endpos=check-Vector(0,0,50),mask=MASK_SOLID_BRUSHONLY})
                if tr.Hit then RB.AddDecal(tr.HitPos+tr.HitNormal*0.5,tr.HitNormal,math_Rand(15,35),RB.LoadedDecalMats[math_random(1,#RB.LoadedDecalMats)],true,220,baseColor) end
            end
        end)
    end
    if isHeadshot or hitgroup==HITGROUP_HEAD then RB.CreateBloodMist(pos, dir, baseColor, final) end
    if wType=="explosive" and cfg.goreLevel>=3 then RB.CreateBloodMist(pos, VectorRand():GetNormalized(), baseColor, final*1.5,true) end
    timer.Simple(0.6,function() ReleaseEmitter(emitter) end)
    if isRobot then RB.PlayRobotSound(pos) else RB.PlayFleshSound(pos, isCritical) end
end

function RB.CreateBloodMist(pos, dir, baseColor, refCount, isExplosion)
    local cfg=RB.ClientConfigCache if cfg.quality==0 then return end
    local cnt=math_Clamp(math.floor((refCount or 15)*0.4),8,40) if isExplosion then cnt=cnt*2 end
    local emitter=GetEmitter(pos) if not emitter then return end local col=baseColor or Color(cfg.colorR,cfg.colorG,cfg.colorB)
    for i=1,cnt do
        local mat=RB.LoadedParticleMats[math_random(1,#RB.LoadedParticleMats)] local par=emitter:Add(mat, pos+VectorRand()*5) if not par then continue end
        local vel if isExplosion then vel=VectorRand():GetNormalized()*math_Rand(100,400) else vel=(dir+VectorRand()*0.8):GetNormalized()*math_Rand(80,250) end
        par:SetVelocity(vel) par:SetDieTime(math_Rand(0.6,1.5)) par:SetLifeTime(0) par:SetStartAlpha(math_Rand(120,200)) par:SetEndAlpha(0)
        par:SetStartSize(math_Rand(6,14)) par:SetEndSize(math_Rand(18,30)) par:SetGravity(Vector(0,0,math_Rand(-40,40))) par:SetAirResistance(math_Rand(150,250))
        par:SetRoll(math_Rand(0,360)) par:SetRollDelta(math_Rand(-2,2))
        local rc=RB.GetRandomBloodColor(col) par:SetColor(rc.r,rc.g,rc.b)
    end
    timer.Simple(1.6,function() ReleaseEmitter(emitter) end)
end

-- Артериальный фонтан (пульсирующий)
function RB.CreateArterialSpray(ent, pos, hitgroup)
    local cfg=RB.ClientConfigCache if not cfg.arterial or cfg.quality==0 then return end
    if not IsValid(ent) then return end
    local baseColor = RB.GetBloodColorForEntity(ent,false)
    if cfg.lowViolence then return end
    -- Пульс каждые arterialInterval
    local emitter=GetEmitter(pos) if not emitter then return end
    for i=1,8 do
        local mat=RB.LoadedParticleMats[1] local par=emitter:Add(mat, pos)
        if par then
            local dir=Vector(0,0,1) + VectorRand()*0.3
            par:SetVelocity(dir*math_Rand(150,350))
            par:SetDieTime(math_Rand(0.5,1.0)) par:SetStartAlpha(220) par:SetEndAlpha(0)
            par:SetStartSize(math_Rand(2,5)) par:SetEndSize(math_Rand(1,3))
            par:SetGravity(Vector(0,0,-400)) par:SetAirResistance(10)
            par:SetColor(baseColor.r,baseColor.g,baseColor.b)
            par:SetCollide(true) par:SetBounce(0) 
            par:SetCollideCallback(function(p,hp,hn) RB.SpawnDecalFromParticle(hp,hn,6,p:GetVelocity(),baseColor) p:SetDieTime(0) end)
        end
    end
    timer.Simple(1.1,function() ReleaseEmitter(emitter) end)
end

------------------------------------------------------------
-- СЛЕДЫ + СКОЛЬЖЕНИЕ + FOOTSTEP
------------------------------------------------------------
function RB.CreateBloodFootprint(pos, normal, intensity, colorOverride, ent)
    local cfg=RB.ClientConfigCache if not cfg.trailsEnabled then return end if not RB.IsPointVisible(pos) then return end
    local col=colorOverride
    if not col then
        if IsValid(ent) and RB.IsRobot and RB.IsRobot(ent) then col=Color(cfg.robotColorR,cfg.robotColorG,cfg.robotColorB)
        elseif IsValid(ent) and RB.IsZombie and RB.IsZombie(ent) then col=Color(cfg.zombieR,cfg.zombieG,cfg.zombieB)
        elseif IsValid(ent) and RB.IsAlien and RB.IsAlien(ent) then col=Color(cfg.alienR,cfg.alienG,cfg.alienB)
        elseif IsValid(ent) and ent.RB_BloodColor then col=ent.RB_BloodColor
        else col=Color(cfg.colorR,cfg.colorG,cfg.colorB) end
    end
    local size=12+intensity*18+math_random(-3,3)
    local mat=RB.LoadedDecalMats[math_random(1,#RB.LoadedDecalMats)]
    RB.AddDecal(pos, normal, size, mat, true, 220, col)
    if math_random()<0.15 then local off=VectorRand() off.z=0 off:Normalize() off=off*math_Rand(8,15) RB.AddDecal(pos+off, normal, size*0.9, mat, true, 200, col) end

    -- Скольжение - если игрок наступил на чёрную кровь масла? Больше скольжение
    if cfg.slip and ent and ent:IsPlayer() then
        if math_random() < 0.08 then -- 8% шанс поскользнуться на луже
            ent:SetVelocity(ent:GetVelocity()* (1+cfg.slipIntensity*0.3) + VectorRand()*cfg.slipIntensity*80)
            if cfg.footstepSound then RB.PlaySquish(pos) end
        elseif cfg.footstepSound then
            if math_random()<0.4 then RB.PlaySquish(pos) end
        end
    end
end

-- Проверка шагов по лужам
hook.Add("Think","RB_FootstepCheck",function()
    local cfg=RB.ClientConfigCache if not cfg.footstepSound and not cfg.slip then return end
    local ply=LocalPlayer() if not IsValid(ply) or not ply:Alive() then return end
    if ply:GetVelocity():Length()<50 then return end
    if not RB.LastFootstep or CurTime()-RB.LastFootstep>0.3 then
        RB.LastFootstep=CurTime()
        local pos=ply:GetPos()+Vector(0,0,5)
        for _,pud in ipairs(RB.Puddles) do
            if pos:DistToSqr(pud.pos) < (pud.currentSize*pud.currentSize) then
                if cfg.footstepSound then RB.PlaySquish(pud.pos) end
                if cfg.slip and math_random()<0.03 then
                    ply:SetVelocity(ply:GetVelocity()*1.1 + Vector(0,0,50))
                end
                break
            end
        end
    end
end)

------------------------------------------------------------
-- ПЯТНА НА ИГРОКЕ / РАСЧЛЕНЁНКА / SPLATTER NEARBY
------------------------------------------------------------
RB.DamageOverlayAlpha=0
RB.ScreenBloodGroups={}

function RB.AddScreenBlood(intensity, duration, isPlayerDamage)
    local cfg=RB.ClientConfigCache if cfg.goreLevel<1 then return end
    if cfg.quality==0 and not isPlayerDamage then return end
    if isPlayerDamage then
        RB.DamageOverlayAlpha=math_Clamp(RB.DamageOverlayAlpha+intensity*120,0,255)
        table.insert(RB.ScreenBloodGroups,{intensity=intensity,dieTime=CurTime()+duration,isDamage=true,x=math_random(0,1),y=math_random(0,1),size=math_Rand(0.2,0.5),rotation=math_random(0,360)})
    else
        if cfg.goreLevel<3 then return end
        for i=1,math_random(3,6) do table.insert(RB.ScreenBloodGroups,{intensity=intensity,dieTime=CurTime()+duration+math_Rand(0,1),isDamage=false,x=math_Rand(0,1),y=math_Rand(0,1),size=math_Rand(0.15,0.4),rotation=math_random(0,360),mat=RB.LoadedDecalMats[math_random(1,#RB.LoadedDecalMats)]}) end
    end
end

hook.Add("HUDPaint","RB_ScreenBloodHUD",function()
    local cfg=RB.ClientConfigCache if not cfg.enabled then return end
    local cur=CurTime()
    if RB.DamageOverlayAlpha>0 then RB.DamageOverlayAlpha=Lerp(FrameTime()*1.2,RB.DamageOverlayAlpha,0) if RB.DamageOverlayAlpha<1 then RB.DamageOverlayAlpha=0 end end
    if RB.DamageOverlayAlpha>2 then
        local w,h=ScrW(),ScrH() local alpha=math_Clamp(RB.DamageOverlayAlpha,0,180) local col=Color(cfg.colorR,cfg.colorG,cfg.colorB,alpha*0.6)
        surface.SetDrawColor(col.r,col.g,col.b,alpha*0.5)
        surface.DrawRect(0,0,w,h*0.08) surface.DrawRect(0,h*0.92,w,h*0.08) surface.DrawRect(0,0,w*0.06,h) surface.DrawRect(w*0.94,0,w*0.06,h)
        if cfg.goreLevel>=2 then
            surface.SetMaterial(RB.ScreenBloodMat) surface.SetDrawColor(col.r,col.g,col.b,alpha)
            for i=1,3 do local size=w*0.15 surface.DrawTexturedRectRotated(w*0.03,h*(0.2+i*0.2),size,size,math_random(0,360)) surface.DrawTexturedRectRotated(w*0.97,h*(0.15+i*0.22),size,size,math_random(0,360)) end
        end
    end
    if cfg.goreLevel>=3 and #RB.ScreenBloodGroups>0 then
        local w,h=ScrW(),ScrH()
        for i=#RB.ScreenBloodGroups,1,-1 do
            local grp=RB.ScreenBloodGroups[i] if not grp then continue end if cur>grp.dieTime then table.remove(RB.ScreenBloodGroups,i) continue end
            local timeLeft=grp.dieTime-cur local fadeAlpha=math_Clamp(timeLeft/2,0,1)*255*grp.intensity
            local col=Color(cfg.colorR,cfg.colorG,cfg.colorB,fadeAlpha) local mat=grp.mat or RB.ScreenBloodMat
            surface.SetMaterial(mat) surface.SetDrawColor(col.r,col.g,col.b,col.a)
            local x=grp.x*w local y=grp.y*h local size=math.min(w,h)*grp.size
            surface.DrawTexturedRectRotated(x,y,size,size,grp.rotation)
        end
    end

    -- Пятна крови на экране от stained player (новая функция)
    local ply=LocalPlayer()
    if IsValid(ply) and RB.StainedPlayers[ply] and CurTime()<RB.StainedPlayers[ply] then
        local timeLeft=RB.StainedPlayers[ply]-CurTime()
        local alpha=math_Clamp(timeLeft/10,0,1)*120
        if alpha>5 then
            local w,h=ScrW(),ScrH()
            surface.SetMaterial(RB.ScreenBloodMat) surface.SetDrawColor(130,0,0,alpha*0.3)
            surface.DrawTexturedRect(0,0,w,h)
        end
    end

    -- Wound HUD
    if cfg.woundSystem then
        -- можно показать кол-во ран? Упрощённо в углу
        local ply=LocalPlayer()
        if IsValid(ply) then
            -- информацию о ранах получаем с сервера через NW? Пока не реализуем NW, просто покажем иконку если кровотечение
            if RB.Bleeding then
                draw.SimpleText("КРОВОТЕЧЕНИЕ! /rb_bandage", "DermaLarge", ScrW()*0.5, ScrH()*0.8, Color(255,0,0,200), TEXT_ALIGN_CENTER)
            end
        end
    end
end)

------------------------------------------------------------
-- NET
------------------------------------------------------------
net.Receive("RB_BloodImpact",function()
    local pos=net.ReadVector() local dir=net.ReadVector() local normal=net.ReadVector()
    local dmg=net.ReadFloat() local wType=net.ReadString() local hitgroup=net.ReadUInt(8) local isHeadshot=net.ReadBool()
    local r=net.ReadUInt(8) local g=net.ReadUInt(8) local b=net.ReadUInt(8) local isCrit=net.ReadBool()
    local col=Color(r,g,b)
    RB.CreateBloodSplash(pos, dir, normal, dmg, wType, hitgroup, col, isCrit, isHeadshot)
end)

net.Receive("RB_BloodPuddle",function()
    local pos=net.ReadVector() local normal=net.ReadVector() local size=net.ReadFloat() local grow=net.ReadFloat()
    local r=net.ReadUInt(8) local g=net.ReadUInt(8) local b=net.ReadUInt(8) local col=Color(r,g,b)
    RB.CreatePuddle(pos, normal, size, grow, col)
end)

net.Receive("RB_BloodTrail",function()
    local pos=net.ReadVector() local normal=net.ReadVector() local intensity=net.ReadFloat() local ent=net.ReadEntity()
    RB.CreateBloodFootprint(pos, normal, intensity, nil, ent)
end)

net.Receive("RB_ClearBlood",function()
    RB.Decals={} RB.Puddles={} RB.ScreenBloodGroups={} RB.DamageOverlayAlpha=0 RB.StainedPlayers={}
    RunConsoleCommand("r_cleardecals")
    chat.AddText(Color(200,40,40),"[Realistic Blood] ",Color(255,255,255),"Кровь очищена.")
end)

net.Receive("RB_ScreenBlood",function()
    local intensity=net.ReadFloat() local duration=net.ReadFloat() local isDamage=net.ReadBool()
    RB.AddScreenBlood(intensity,duration,isDamage)
end)

net.Receive("RB_Bandage",function()
    local ent=net.ReadEntity()
    if ent==LocalPlayer() then
        RB.Bleeding=false
        chat.AddText(Color(0,255,0),"[Realistic Blood] Вы перевязали раны!")
        local cfg=RB.ClientConfigCache
        if cfg.soundEnabled then surface.PlaySound("items/medshot4.wav") end
    end
end)

net.Receive("RB_ArterialSpray",function()
    local ent=net.ReadEntity() local pos=net.ReadVector() local hitgroup=net.ReadUInt(8) local isArtery=net.ReadBool()
    if not IsValid(ent) then return end
    -- Создаём пульсирующий эффект
    RB.CreateArterialSpray(ent, pos, hitgroup)
    -- Повторяем пульс через интервал
    local cfg=RB.ClientConfigCache
    local interval=cfg.arterialInterval or 0.8
    for i=1,5 do
        timer.Simple(i*interval, function()
            if not IsValid(ent) then return end
            if not ent:Alive() then return end
            RB.CreateArterialSpray(ent, ent:GetPos()+Vector(0,0,40)+VectorRand()*10, hitgroup)
        end)
    end
end)

net.Receive("RB_Dismember",function()
    local ent=net.ReadEntity() local pos=net.ReadVector() local hitgroup=net.ReadUInt(8) local dmg=net.ReadFloat()
    if not IsValid(ent) then return end
    -- Простая расчленёнка: спавним gibs (маленькие кровавые куски)
    local emitter=GetEmitter(pos)
    if emitter then
    for i=1,12 do
        local mat=RB.LoadedParticleMats[math_random(1,#RB.LoadedParticleMats)]
        local par=emitter:Add(mat, pos)
        if par then
            par:SetVelocity(VectorRand()*math_Rand(100,400) + Vector(0,0,100))
            par:SetDieTime(math_Rand(1,3)) par:SetStartAlpha(255) par:SetEndAlpha(0)
            par:SetStartSize(math_Rand(8,16)) par:SetEndSize(math_Rand(4,8))
            par:SetGravity(Vector(0,0,-400)) par:SetAirResistance(20)
            par:SetColor(130,0,0)
            par:SetCollide(true)
        end
    end
    end -- if emitter
    timer.Simple(3.1,function() ReleaseEmitter(emitter) end)
    -- Звук (с проверкой настройки)
    local cfg=RB.ClientConfigCache
    if cfg.soundEnabled then sound.Play("physics/flesh/flesh_bloody_impact_hard1.wav", pos, 80, math_random(80,110), cfg.soundVolume) end
    -- Декали вокруг
    for i=1,10 do
        local off=VectorRand()*50 off.z=0
        local tr=util.TraceLine({start=pos+off+Vector(0,0,10), endpos=pos+off-Vector(0,0,100), mask=MASK_SOLID_BRUSHONLY})
        if tr.Hit then RB.AddDecal(tr.HitPos,tr.HitNormal,math_Rand(20,50),RB.LoadedDecalMats[1],true,255,Color(130,0,0)) end
    end
end)

net.Receive("RB_SplatterNearby",function()
    local ent=net.ReadEntity() local pos=net.ReadVector() local r=net.ReadUInt(8) local g=net.ReadUInt(8) local b=net.ReadUInt(8) local intensity=net.ReadFloat()
    local col=Color(r,g,b)
    if not IsValid(ent) then return end
    -- Просто добавим пару капель вокруг энтити — с трейсом к полу чтобы не спавнить в воздухе
    for i=1,math_random(2,5) do
        local off=VectorRand()*30 off.z=0
        local checkPos=ent:GetPos()+off+Vector(0,0,30)
        local tr=util.TraceLine({start=checkPos, endpos=checkPos-Vector(0,0,100), filter=ent, mask=MASK_SOLID})
        if tr.Hit then
            RB.AddDecal(tr.HitPos+tr.HitNormal*0.5, tr.HitNormal, math_Rand(8,18), RB.LoadedDecalMats[1], true, 200, col)
        end
    end
end)

net.Receive("RB_StainPlayer",function()
    local ent=net.ReadEntity() local intensity=net.ReadFloat()
    if not IsValid(ent) then return end
    if ent==LocalPlayer() then
        local cfg=RB.ClientConfigCache
        RB.StainedPlayers[ent]=CurTime()+cfg.stainTime
        RB.Bleeding = intensity>0.3 -- флаг для HUD
        timer.Simple(cfg.stainTime, function() RB.Bleeding=false end)
    end
end)

------------------------------------------------------------
-- МЕНЮ v1.2 MEGA с категориями
------------------------------------------------------------
hook.Add("PopulateToolMenu","RB_PopulateToolMenu",function()
    spawnmenu.AddToolMenuOption("Utilities","Realistic Blood","RB_Settings","Realistic Blood MEGA","", "",function(panel)
        panel:ClearControls()
        panel:Help("MEGA UPDATE v1.2 - 40+ настроек. Версия "..RB.Version)

        -- Основные
        panel:Help("--- ОСНОВНОЕ ---")
        panel:CheckBox("Включить мод","rb_enabled")
        panel:CheckBox("Лужи","rb_puddle_enabled")
        panel:CheckBox("Следы","rb_trails_enabled")
        panel:CheckBox("Потёки","rb_wall_drips")
        panel:CheckBox("Кровь на трупах","rb_corpse_blood")
        panel:CheckBox("Звуки","rb_sound_enabled")
        panel:NumSlider("Громкость","rb_sound_volume",0,1,2)
        panel:NumSlider("Множитель частиц","rb_particle_multiplier",0.1,5.0,2)
        panel:NumSlider("Время жизни декалей","rb_decal_lifetime",10,600,0)
        panel:NumSlider("Макс декалей","rb_decal_max",50,2000,0)
        panel:NumSlider("Размер луж","rb_puddle_size",0.5,3.0,2)
        panel:NumSlider("Качество","rb_quality",0,2,0)
        panel:NumSlider("Gore уровень","rb_gore_level",1,3,0)

        panel:Help("--- ЦВЕТА КРОВИ ---")
        panel:NumSlider("Люди R","rb_color_r",0,255,0)
        panel:NumSlider("G","rb_color_g",0,255,0)
        panel:NumSlider("B","rb_color_b",0,255,0)
        panel:CheckBox("Чёрная кровь роботов","rb_robot_black_blood")
        panel:NumSlider("Робот R","rb_robot_color_r",0,255,0)
        panel:NumSlider("G","rb_robot_color_g",0,255,0)
        panel:NumSlider("B","rb_robot_color_b",0,255,0)
        panel:CheckBox("Зомби отдельный цвет","rb_zombie_blood")
        panel:NumSlider("Зомби R","rb_zombie_color_r",0,255,0)
        panel:NumSlider("G","rb_zombie_color_g",0,255,0)
        panel:NumSlider("B","rb_zombie_color_b",0,255,0)
        panel:CheckBox("Пришельцы","rb_alien_blood")
        panel:NumSlider("Alien R","rb_alien_color_r",0,255,0)
        panel:NumSlider("G","rb_alien_color_g",0,255,0)
        panel:NumSlider("B","rb_alien_color_b",0,255,0)

        local mixer=vgui.Create("DColorMixer",panel) mixer:SetLabel("Люди") mixer:SetPalette(true) mixer:SetAlphaBar(false) mixer:SetWangs(true)
        timer.Simple(0.1,function() if IsValid(mixer) then local cfg=RB.ClientConfigCache mixer:SetColor(Color(cfg.colorR,cfg.colorG,cfg.colorB)) end end)
        mixer.ValueChanged=function(_,col) RunConsoleCommand("rb_color_r",tostring(col.r)) RunConsoleCommand("rb_color_g",tostring(col.g)) RunConsoleCommand("rb_color_b",tostring(col.b)) end
        panel:AddItem(mixer)

        panel:Help("--- НОВЫЕ ФУНКЦИИ v1.2 ---")

        panel:Help("Высыхание крови:")
        panel:CheckBox("Высыхание (красный->коричневый)","rb_blood_drying")
        panel:NumSlider("Время высыхания сек","rb_blood_drying_time",30,600,0)
        panel:CheckBox("Темнеет при высыхании","rb_blood_drying_dark")

        panel:Help("Скольжение:")
        panel:CheckBox("Скольжение на лужах","rb_blood_slip")
        panel:NumSlider("Сила скольжения","rb_blood_slip_intensity",0.1,2.0,2)
        panel:CheckBox("Хлюпанье шагов","rb_footstep_sound")

        panel:Help("Раны и кровопотеря:")
        panel:CheckBox("Система ран","rb_wound_system")
        panel:NumSlider("Макс ран","rb_wound_max",1,10,0)
        panel:CheckBox("Урон от кровопотери","rb_bleed_damage")
        panel:NumSlider("Интервал урона","rb_bleed_damage_interval",0.5,10,1)
        panel:NumSlider("Урон за тик","rb_bleed_damage_amount",1,10,0)
        panel:CheckBox("Бинты /rb_bandage","rb_bandage_enabled")
        panel:CheckBox("Замедление при кровопотере","rb_blood_loss_slow")

        panel:Help("Окружение:")
        panel:CheckBox("Брызги пачкают соседей","rb_splatter_on_nearby")
        panel:NumSlider("Радиус загрязнения","rb_splatter_range",50,400,0)
        panel:CheckBox("Пятна на оружии","rb_blood_on_weapon")
        panel:CheckBox("Игрок пачкается","rb_blood_stain_player")
        panel:NumSlider("Время пятен","rb_stain_time",10,300,0)
        panel:CheckBox("Следы от колёс машины","rb_blood_on_vehicle_wheels")

        panel:Help("Продвинутое:")
        panel:CheckBox("Расчленёнка (gore 3)","rb_dismember")
        panel:NumSlider("Порог расчленёнки","rb_dismember_threshold",50,500,0)
        panel:CheckBox("Кровь в воде растворяется","rb_blood_in_water")
        panel:CheckBox("Лужи сливаются","rb_pool_merge")
        panel:NumSlider("Дистанция сливания","rb_pool_merge_dist",30,300,0)
        panel:CheckBox("Артериальный пульсирующий фонтан","rb_arterial_spray")
        panel:NumSlider("Интервал пульса","rb_arterial_interval",0.3,2.0,2)

        panel:Help("Производительность и режимы:")
        panel:CheckBox("Динамическое качество по FPS","rb_dynamic_quality")
        panel:NumSlider("FPS порог","rb_fps_threshold",20,90,0)
        panel:CheckBox("Low violence (искры для стримов)","rb_low_violence")
        panel:CheckBox("Кастомный конфиг из data/","rb_custom_config")

        panel:Help("Управление:")
        local btnClear=panel:Button("Очистить кровь","rb_clearblood") btnClear.DoClick=function() RunConsoleCommand("rb_clearblood") end
        local btnBandage=panel:Button("Перевязаться /rb_bandage","rb_bandage") btnBandage.DoClick=function() RunConsoleCommand("rb_bandage") end
        local btnReset=vgui.Create("DButton",panel) btnReset:SetText("Сбросить по умолчанию")
        btnReset.DoClick=function() Derma_Query("Сбросить?","Сброс","Да",function() RunConsoleCommand("rb_reset_defaults") end,"Отмена",function() end) end
        panel:AddItem(btnReset)

        panel:Help("Команды: rb_stats, rb_wounds, rb_isrobot, rb_bandage, rb_clearblood")
        panel:Help("Автор: Arena AI v"..RB.Version.." - 40+ ConVars, трупы, чёрная кровь роботов, машина, высыхание, скольжение, раны, расчленёнка")
    end)
end)

concommand.Add("rb_menu",function() print("Q -> Utilities -> Realistic Blood MEGA") end)
concommand.Add("rb_stats",function()
    local cfg=RB.ClientConfigCache
    print("=== RB v1.2 MEGA Stats ===")
    print("Decals "..#RB.Decals.."/"..cfg.decalMax.." Puddles "..#RB.Puddles.." FPS "..math.Round(RB.DynamicFPS))
    print("Drying:"..tostring(cfg.drying).." Slip:"..tostring(cfg.slip).." Wounds:"..tostring(cfg.woundSystem).." BleedDmg:"..tostring(cfg.bleedDamage))
    print("Robot:"..tostring(cfg.robotBlackBlood).." Zombie:"..tostring(cfg.zombieBlood).." Alien:"..tostring(cfg.alienBlood))
    print("Arterial:"..tostring(cfg.arterial).." Dismember:"..tostring(cfg.dismember).." DynamicQ:"..tostring(cfg.dynamicQuality))
end)

print("[Realistic Blood] Client v1.2 MEGA загружен - 40+ настроек")
