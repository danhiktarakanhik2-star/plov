--[[ 
    Эффект: rb_blood_impact
    Тип: Client Effect
    Описание: Кастомный эффект всплеска крови, вызываемый через util.Effect.
              Может использоваться другими аддонами или через EffectData.
              Поддерживает параметры: origin, normal, magnitude (урон), scale (множитель частиц),
              materialIndex (тип оружия как ID), hitbox (хитгруппа).
              Повторяет логику из cl_realistic_blood, но в упрощённом виде для совместимости.
              Полностью прокомментирован на русском.
--]]

-- EFFECT таблица - стандартная для GMod эффектов
EFFECT = EFFECT or {}

-- Маппинг materialIndex -> тип оружия (для совместимости с EffectData)
local WeaponTypeByID = {
    [0] = "generic",
    [1] = "pistol",
    [2] = "smg",
    [3] = "rifle",
    [4] = "sniper",
    [5] = "shotgun",
    [6] = "explosive",
    [7] = "melee"
}

-- Инициализация эффекта (вызывается при создании)
function EFFECT:Init(data)
    -- Получаем данные из EffectData
    self.Pos = data:GetOrigin() or Vector(0,0,0)
    self.Normal = data:GetNormal() or Vector(0,0,1)
    self.Damage = data:GetMagnitude() or 20
    self.Scale = data:GetScale() or 1.0 -- множитель частиц
    self.HitGroup = data:GetHitBox() or 0
    local matID = data:GetMaterialIndex() or 0
    self.WeaponType = WeaponTypeByID[matID] or "generic"

    self.DieTime = CurTime() + 2 -- время жизни эффекта (частицы живут дольше сами)
    self.Emitter = nil

    -- Проверяем глобальную таблицу RB
    if not RB then
        -- Если RB не загружен, пытаемся минимально отработать без него
        self:FallbackEffect()
        return
    end

    -- Конфиг
    local cfg = RB.GetConfig and RB.GetConfig() or {enabled=true, particleMult=1, quality=2, goreLevel=2, colorR=130, colorG=0, colorB=0, decalMax=500, decalLifetime=300}
    if not cfg.enabled then return end

    -- PVS/LOD проверки (оптимизация)
    if RB.IsPointVisible and not RB.IsPointVisible(self.Pos) then return end

    -- Создаём частицы напрямую, используя ParticleEmitter
    self:CreateParticles(cfg)
end

-- Основная логика создания частиц (упрощённая версия из клиенской части)
function EFFECT:CreateParticles(cfg)
    -- Получаем цвет крови
    local bloodColor = Color(cfg.colorR or 130, cfg.colorG or 0, cfg.colorB or 0)
    if RB.GetRandomBloodColor then
        -- Базовый, рандомизация внутри цикла
    end

    -- Профили оружия если доступны
    local profile = (RB.WeaponProfiles and RB.WeaponProfiles[self.WeaponType]) or {particles=15, speedMin=200, speedMax=400, spread=0.5}

    -- Вычисляем количество
    local hitMult = (RB.HitGroupMultipliers and RB.HitGroupMultipliers[self.HitGroup]) or 1.0
    local qualityMult = 1.0
    if cfg.quality == 0 then qualityMult = 0.35 elseif cfg.quality == 1 then qualityMult = 0.7 end
    local dmgMult = 1 + (math.Clamp(self.Damage,0,150)/70)

    local count = math.floor(profile.particles * hitMult * (cfg.particleMult or 1) * qualityMult * dmgMult * self.Scale)
    count = math.Clamp(count, 3, 80)

    if RB.GetLODMultiplier then
        count = math.floor(count * RB.GetLODMultiplier(self.Pos))
    end

    -- Эмиттер
    self.Emitter = ParticleEmitter(self.Pos, false)
    if not self.Emitter then return end

    -- Создаём частицы
    for i=1, count do
        -- Рандомный размер категории
        local sizeCat = math.random(1,100)
        local pSize, life
        if sizeCat <= 55 then
            pSize = math.Rand(1,3)
            life = math.Rand(0.5,1.2)
        elseif sizeCat <= 85 then
            pSize = math.Rand(3,6)
            life = math.Rand(0.8,2.0)
        else
            pSize = math.Rand(6,10)
            life = math.Rand(1.0,2.5)
        end

        -- Материал
        local matList = RB.LoadedParticleMats or {Material("effects/blood_core")}
        local mat = matList[math.random(1, #matList)]

        local particle = self.Emitter:Add(mat, self.Pos)
        if not particle then continue end

        -- Направление: нормаль + рандом + spread
        local dir = self.Normal
        -- Если есть направление выстрела, используем -normal как базу, но чуть рандомизируем
        local spreadVec = VectorRand() * (profile.spread or 0.5)
        local velDir = (dir + spreadVec):GetNormalized()

        local speed = math.Rand(profile.speedMin or 200, profile.speedMax or 400)

        particle:SetVelocity(velDir * speed)
        particle:SetDieTime(life)
        particle:SetLifeTime(0)
        particle:SetStartAlpha(255)
        particle:SetEndAlpha(0)
        particle:SetStartSize(pSize)
        particle:SetEndSize(pSize * 0.8)
        particle:SetGravity(Vector(0,0, math.Rand(-500,-300)))
        particle:SetAirResistance(math.Rand(30,80))
        particle:SetRoll(math.Rand(0,360))
        particle:SetRollDelta(math.Rand(-5,5))
        particle:SetCollide(true)
        particle:SetBounce(0.1)

        local col = bloodColor
        if RB.GetRandomBloodColor then
            col = RB.GetRandomBloodColor(bloodColor)
        end
        particle:SetColor(col.r, col.g, col.b)

        -- Коллизия -> декаль
        local sizeForDecal = pSize * 3
        particle:SetCollideCallback(function(part, hitPos, hitNormal)
            if RB.SpawnDecalFromParticle then
                RB.SpawnDecalFromParticle(hitPos, hitNormal, sizeForDecal, part:GetVelocity())
            else
                -- Fallback движковая декаль
                util.Decal("Blood", hitPos + hitNormal*0.5, hitPos - hitNormal*0.5)
            end
            part:SetDieTime(0)
        end)
    end

    -- Звук
    if RB.PlayFleshSound then
        RB.PlayFleshSound(self.Pos, self.Damage > 60)
    end
end

-- Fallback если RB не загружен (минимальный эффект)
function EFFECT:FallbackEffect()
    local emitter = ParticleEmitter(self.Pos, false)
    if not emitter then return end
    for i=1, 12 do
        local particle = emitter:Add("effects/blood_core", self.Pos)
        if particle then
            particle:SetVelocity((self.Normal + VectorRand()*0.5):GetNormalized() * math.Rand(100,400))
            particle:SetDieTime(math.Rand(0.5,1.5))
            particle:SetLifeTime(0)
            particle:SetStartAlpha(255)
            particle:SetEndAlpha(0)
            particle:SetStartSize(math.Rand(2,6))
            particle:SetEndSize(math.Rand(1,4))
            particle:SetGravity(Vector(0,0,-400))
            particle:SetAirResistance(50)
            particle:SetColor(130,0,0)
            particle:SetCollide(true)
            particle:SetBounce(0.1)
            particle:SetCollideCallback(function(part, hitPos, hitNormal)
                util.Decal("Blood", hitPos + hitNormal*0.5, hitPos - hitNormal*0.5)
            end)
        end
    end
    emitter:Finish()
end

-- Think вызывается каждый тик, должен возвращать true чтобы эффект продолжал жить
function EFFECT:Think()
    if not self.DieTime then return false end
    if CurTime() > self.DieTime then
        if self.Emitter then
            self.Emitter:Finish()
            self.Emitter = nil
        end
        return false
    end
    return true
end

-- Render - для этого эффекта не нужен 3D рендер, частицы рендерятся сами
function EFFECT:Render()
    -- Пусто, частицы рисуются движком
end
