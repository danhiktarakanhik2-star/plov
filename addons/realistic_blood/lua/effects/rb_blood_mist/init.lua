--[[ 
    Эффект: rb_blood_mist
    Тип: Client Effect
    Описание: Эффект кровавого тумана (blood mist), возникающий при хедшоте
              или при взрыве (массовый разлёт крови). Состоит из мелких лёгких
              красных частиц, которые медленно парят и быстро затухают.
              Используется в системе попадания в голову (ТЗ Попадание в разные части тела п.2)
              и в системе взрывчатки (ТЗ Дополнительные эффекты).
              Полностью прокомментирован.
--]]

EFFECT = EFFECT or {}

function EFFECT:Init(data)
    -- Позиция - центр тумана
    self.Pos = data:GetOrigin() or Vector(0,0,0)
    -- Нормаль - направление разлёта (если есть)
    self.Dir = data:GetNormal() or Vector(0,0,1)
    -- Magnitude - количество частиц (используем как ориентир)
    self.Magnitude = data:GetMagnitude() or 20
    -- Scale - размер/интенсивность тумана
    self.Scale = data:GetScale() or 1.0
    -- Radius в EffectData используем как флаг взрыва: если >100, то считаем взрывом
    self.IsExplosion = data:GetRadius() and data:GetRadius() > 100 or false

    self.DieTime = CurTime() + 2.0

    -- Если RB не загружен - fallback
    if not RB then
        self:FallbackMist()
        return
    end

    local cfg = RB.GetConfig and RB.GetConfig() or {enabled=true, quality=2, colorR=130, colorG=0, colorB=0, particleMult=1}
    if not cfg.enabled then return end
    if cfg.quality == 0 then return end -- на низком качестве не показываем туман (оптимизация по ТЗ)

    if RB.IsPointVisible and not RB.IsPointVisible(self.Pos) then return end

    self:CreateMist(cfg)
end

function EFFECT:CreateMist(cfg)
    local bloodColor = Color(cfg.colorR or 130, cfg.colorG or 0, cfg.colorB or 0)

    -- Количество частиц тумана
    local baseCount = math.Clamp(math.floor(self.Magnitude * 0.4), 8, 40)
    if self.IsExplosion then baseCount = baseCount * 2 end
    baseCount = math.floor(baseCount * (cfg.particleMult or 1) * self.Scale)

    if RB.GetLODMultiplier then
        baseCount = math.floor(baseCount * RB.GetLODMultiplier(self.Pos))
    end

    local emitter = ParticleEmitter(self.Pos, false)
    if not emitter then return end
    self.Emitter = emitter

    local matList = RB.LoadedParticleMats or {Material("effects/blood_core")}

    for i=1, baseCount do
        local mat = matList[math.random(1, #matList)]
        local particle = emitter:Add(mat, self.Pos + VectorRand()*8)
        if not particle then continue end

        -- Скорость: для взрыва - во все стороны, для хедшота - в направлении + рандом
        local vel
        if self.IsExplosion then
            vel = VectorRand():GetNormalized() * math.Rand(120, 450)
        else
            vel = (self.Dir + VectorRand()*0.9):GetNormalized() * math.Rand(80, 300)
        end

        particle:SetVelocity(vel)
        particle:SetDieTime(math.Rand(0.7, 1.6))
        particle:SetLifeTime(0)
        particle:SetStartAlpha(math.Rand(100, 200))
        particle:SetEndAlpha(0) -- плавный фейд
        particle:SetStartSize(math.Rand(5, 12))
        particle:SetEndSize(math.Rand(16, 28)) -- туман расширяется, в отличие от капель
        particle:SetGravity(Vector(0,0, math.Rand(-30, 30))) -- почти не падает, парит
        particle:SetAirResistance(math.Rand(150, 250)) -- быстро тормозится (лёгкие частицы)
        particle:SetRoll(math.Rand(0,360))
        particle:SetRollDelta(math.Rand(-2,2))

        local col = bloodColor
        if RB.GetRandomBloodColor then
            col = RB.GetRandomBloodColor(bloodColor)
        end
        -- Туман чуть светлее и прозрачнее кровавых капель, чтобы выглядел как мелкодисперсная взвесь
        particle:SetColor(col.r, col.g, col.b)

        -- Туман обычно не оставляет декалей (слишком лёгкий), но крупные частицы могут
        if math.random() < 0.15 then
            particle:SetCollide(true)
            particle:SetBounce(0.05)
            particle:SetCollideCallback(function(part, hitPos, hitNormal)
                if RB.SpawnDecalFromParticle then
                    RB.SpawnDecalFromParticle(hitPos, hitNormal, 4, part:GetVelocity())
                end
                part:SetDieTime(0)
            end)
        end
    end

    -- Дополнительный звук шипения тумана? Не нужен, но можно добавить очень тихий
end

function EFFECT:FallbackMist()
    local emitter = ParticleEmitter(self.Pos, false)
    if not emitter then return end
    for i=1, 10 do
        local particle = emitter:Add("effects/blood_core", self.Pos + VectorRand()*5)
        if particle then
            particle:SetVelocity(VectorRand():GetNormalized() * math.Rand(50,200))
            particle:SetDieTime(math.Rand(0.5,1.2))
            particle:SetLifeTime(0)
            particle:SetStartAlpha(180)
            particle:SetEndAlpha(0)
            particle:SetStartSize(math.Rand(4,10))
            particle:SetEndSize(math.Rand(10,20))
            particle:SetGravity(Vector(0,0,0))
            particle:SetAirResistance(180)
            particle:SetColor(130,0,0)
        end
    end
    emitter:Finish()
end

function EFFECT:Think()
    if CurTime() > self.DieTime then
        if self.Emitter then
            self.Emitter:Finish()
            self.Emitter = nil
        end
        return false
    end
    return true
end

function EFFECT:Render()
    -- Частицы рендерятся движком
end
