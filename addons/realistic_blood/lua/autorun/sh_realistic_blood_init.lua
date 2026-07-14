--[[ 
    Realistic Blood - Shared v1.2 MEGA UPDATE
    Добавлено 35+ новых настроек и функций:
    - Высыхание крови (drying) красно-коричневое
    - Скольжение на лужах
    - Система ран (wounds) + кровопотеря
    - Бинты (bandage)
    - Разбрызгивание на соседних NPC
    - Пятна на оружии / игроке
    - Расчленёнка (gibs) при сильном уроне
    - Кровь в воде, смешивание луж
    - Зомби / пришельцы кастом цвета
    - Артериальный фонтан (пульсирующий)
    - Динамическое качество по FPS
    - Low violence режим
    Полностью прокомментирован.
--]]

RB = RB or {}
RB.Version = "1.2.0 MEGA (35+ settings)"

local function RB_Log(msg) print("[Realistic Blood] " .. msg) end

if SERVER then
    AddCSLuaFile("autorun/client/cl_realistic_blood.lua")
    AddCSLuaFile("effects/rb_blood_impact/init.lua")
    AddCSLuaFile("effects/rb_blood_mist/init.lua")
end

------------------------------------------------------------
-- 1. CONVARS - БАЗОВЫЕ (v1.0-v1.1)
------------------------------------------------------------
if SERVER then
    CreateConVar("rb_enabled", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Включить мод целиком")
    CreateConVar("rb_particle_multiplier", "1.0", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Множитель частиц 0.1-5.0", 0.1, 5.0)
    CreateConVar("rb_quality", "2", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "0 низк,1 сред,2 высок", 0, 2)
    CreateConVar("rb_gore_level", "2", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "1 мин,2 сред,3 макс", 1, 3)
    CreateConVar("rb_decal_lifetime", "300", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Время жизни декалей 10-600", 10, 600)
    CreateConVar("rb_decal_max", "500", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Макс декалей 50-2000", 50, 2000)
    CreateConVar("rb_puddle_enabled", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Лужи")
    CreateConVar("rb_puddle_size", "1.0", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Размер луж 0.5-3.0", 0.5, 3.0)
    CreateConVar("rb_trails_enabled", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Следы")
    CreateConVar("rb_wall_drips", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Потёки")
    CreateConVar("rb_sound_enabled", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Звуки")
    CreateConVar("rb_sound_volume", "0.8", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Громкость 0-1", 0, 1)
    CreateConVar("rb_color_r", "130", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "R крови", 0, 255)
    CreateConVar("rb_color_g", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "G крови", 0, 255)
    CreateConVar("rb_color_b", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "B крови", 0, 255)
    CreateConVar("rb_robot_black_blood", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Чёрная кровь роботов")
    CreateConVar("rb_robot_color_r", "20", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "R роботов", 0, 255)
    CreateConVar("rb_robot_color_g", "20", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "G роботов", 0, 255)
    CreateConVar("rb_robot_color_b", "20", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "B роботов", 0, 255)
    CreateConVar("rb_corpse_blood", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Кровь на трупах")

    ------------------------------------------------------------
    -- 1.1 НОВЫЕ НАСТРОЙКИ v1.2 (35+)
    ------------------------------------------------------------
    -- Высыхание крови
    CreateConVar("rb_blood_drying", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Высыхание крови - коричневеет со временем")
    CreateConVar("rb_blood_drying_time", "120", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Время высыхания в сек 30-600", 30, 600)
    CreateConVar("rb_blood_drying_dark", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Темнеет при высыхании")

    -- Скольжение
    CreateConVar("rb_blood_slip", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Скольжение на лужах")
    CreateConVar("rb_blood_slip_intensity", "0.5", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Сила скольжения 0.1-2.0", 0.1, 2.0)

    -- Кровопотеря и раны
    CreateConVar("rb_wound_system", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Система ран - каждая рана кровоточит отдельно")
    CreateConVar("rb_wound_max", "5", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Макс ран на игроке 1-10", 1, 10)
    CreateConVar("rb_bleed_damage", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Кровотечение наносит урон")
    CreateConVar("rb_bleed_damage_interval", "2.0", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Интервал урона кровопотери 0.5-10", 0.5, 10)
    CreateConVar("rb_bleed_damage_amount", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Урон за тик кровопотери 1-10", 1, 10)
    CreateConVar("rb_bandage_enabled", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Бинты - команда rb_bandage останавливает кровь")
    CreateConVar("rb_blood_loss_slow", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Замедление при сильной кровопотере")

    -- Разбрызгивание на соседей
    CreateConVar("rb_splatter_on_nearby", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Брызги пачкают nearby NPC")
    CreateConVar("rb_splatter_range", "120", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Радиус загрязнения соседей 50-400", 50, 400)

    -- Пятна на игроке / оружии
    CreateConVar("rb_blood_on_weapon", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Пятна на оружии при близком уроне")
    CreateConVar("rb_blood_stain_player", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Игрок пачкается в крови")
    CreateConVar("rb_stain_time", "30", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Время пятен на игроке 10-300", 10, 300)

    -- Расчленёнка
    CreateConVar("rb_dismember", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Расчленёнка при сильном уроне (требует gore 3)")
    CreateConVar("rb_dismember_threshold", "150", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Порог урона для расчленёнки 50-500", 50, 500)

    -- Вода / смешивание луж
    CreateConVar("rb_blood_in_water", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Кровь растворяется в воде (эффект)")
    CreateConVar("rb_pool_merge", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Лужи сливаются если рядом")
    CreateConVar("rb_pool_merge_dist", "100", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Дистанция сливания луж 30-300", 30, 300)

    -- Зомби / пришельцы кастом цвета
    CreateConVar("rb_zombie_blood", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Отдельный цвет для зомби")
    CreateConVar("rb_zombie_color_r", "80", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "R зомби", 0, 255)
    CreateConVar("rb_zombie_color_g", "100", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "G зомби", 0, 255)
    CreateConVar("rb_zombie_color_b", "20", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "B зомби", 0, 255)
    CreateConVar("rb_alien_blood", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Отдельный цвет для alien/antlion")
    CreateConVar("rb_alien_color_r", "60", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "R alien", 0, 255)
    CreateConVar("rb_alien_color_g", "200", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "G alien", 0, 255)
    CreateConVar("rb_alien_color_b", "20", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "B alien", 0, 255)

    -- Артериальный фонтан
    CreateConVar("rb_arterial_spray", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Артериальный пульсирующий фонтан при ранении груди/шеи")
    CreateConVar("rb_arterial_interval", "0.8", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Интервал пульса 0.3-2.0", 0.3, 2.0)

    -- Динамическое качество
    CreateConVar("rb_dynamic_quality", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Авто-понижение качества если FPS низкий")
    CreateConVar("rb_fps_threshold", "50", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "FPS порог для динамического качества 20-90", 20, 90)

    -- Доп
    CreateConVar("rb_low_violence", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Low violence - искры вместо крови (для стримов)")
    CreateConVar("rb_footstep_sound", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Хлюпанье при ходьбе по лужам")
    CreateConVar("rb_blood_on_vehicle_wheels", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Следы крови от колёс машины после наезда")
    CreateConVar("rb_custom_config", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Загружать кастомные цвета из data/realistic_blood_custom.json если есть")

    -- Net
    util.AddNetworkString("RB_BloodImpact")
    util.AddNetworkString("RB_BloodPuddle")
    util.AddNetworkString("RB_BloodTrail")
    util.AddNetworkString("RB_ClearBlood")
    util.AddNetworkString("RB_ScreenBlood")
    util.AddNetworkString("RB_BloodDrip")
    util.AddNetworkString("RB_Bandage")
    util.AddNetworkString("RB_ArterialSpray")
    util.AddNetworkString("RB_Dismember")
    util.AddNetworkString("RB_StainPlayer")
    util.AddNetworkString("RB_SplatterNearby")

    RB_Log("ConVars v1.2 (40+) и net зарегистрированы")
else
    RB_Log("Клиент инициализирован v"..RB.Version)
end

------------------------------------------------------------
-- 2. ПРОФИЛИ ОРУЖИЯ
------------------------------------------------------------
RB.WeaponProfiles = {
    ["pistol"] = {label="Пистолеты", particles=12, speedMin=180, speedMax=320, decalSizeMin=8, decalSizeMax=18, spread=0.35, hasExitWound=false, goreMult=1.0},
    ["smg"] = {label="SMG", particles=10, speedMin=200, speedMax=350, decalSizeMin=6, decalSizeMax=16, spread=0.4, hasExitWound=false, goreMult=0.9},
    ["rifle"] = {label="Винтовки", particles=20, speedMin=300, speedMax=550, decalSizeMin=12, decalSizeMax=28, spread=0.3, hasExitWound=true, exitMult=1.5, goreMult=1.3},
    ["sniper"] = {label="Снайперки", particles=28, speedMin=400, speedMax=700, decalSizeMin=15, decalSizeMax=35, spread=0.25, hasExitWound=true, exitMult=2.0, goreMult=1.6},
    ["shotgun"] = {label="Дробовики", particles=36, speedMin=180, speedMax=400, decalSizeMin=5, decalSizeMax=14, spread=1.2, hasExitWound=false, goreMult=1.4},
    ["explosive"] = {label="Взрывчатка", particles=85, speedMin=400, speedMax=800, decalSizeMin=18, decalSizeMax=45, spread=2.0, hasExitWound=false, goreMult=2.5},
    ["melee"] = {label="Ближний бой", particles=8, speedMin=80, speedMax=180, decalSizeMin=10, decalSizeMax=22, spread=0.6, hasExitWound=false, goreMult=1.0, delayed=true},
    ["generic"] = {label="Стандарт", particles=15, speedMin=200, speedMax=400, decalSizeMin=8, decalSizeMax=20, spread=0.5, hasExitWound=false, goreMult=1.0},
    ["crush"] = {label="Давление/Машина", particles=25, speedMin=100, speedMax=400, decalSizeMin=12, decalSizeMax=40, spread=0.9, hasExitWound=false, goreMult=1.6},
    ["flame"] = {label="Огонь", particles=8, speedMin=50, speedMax=150, decalSizeMin=6, decalSizeMax=12, spread=0.6, hasExitWound=false, goreMult=0.8, noDecal=true},
    ["crossbow"] = {label="Арбалет", particles=22, speedMin=200, speedMax=500, decalSizeMin=10, decalSizeMax=30, spread=0.2, hasExitWound=true, exitMult=2.2, goreMult=1.5}
}

------------------------------------------------------------
-- 3. ХИТГРУППЫ
------------------------------------------------------------
RB.HitGroupMultipliers = {
    [HITGROUP_HEAD]=2.5, [HITGROUP_CHEST]=1.3, [HITGROUP_STOMACH]=1.1,
    [HITGROUP_LEFTARM]=0.7, [HITGROUP_RIGHTARM]=0.7, [HITGROUP_LEFTLEG]=0.7, [HITGROUP_RIGHTLEG]=0.7,
    [HITGROUP_GEAR]=0.5, [0]=1.0
}
RB.HitGroupNames = {
    [HITGROUP_HEAD]="Голова", [HITGROUP_CHEST]="Грудь", [HITGROUP_STOMACH]="Живот",
    [HITGROUP_LEFTARM]="Левая рука", [HITGROUP_RIGHTARM]="Правая рука",
    [HITGROUP_LEFTLEG]="Левая нога", [HITGROUP_RIGHTLEG]="Правая нога"
}

------------------------------------------------------------
-- 4. ТЕКСТУРЫ
------------------------------------------------------------
RB.ParticleMaterials = {"effects/blood_core","effects/blood_drop","effects/blood2","effects/blood","particle/blood/blood-1","particle/blood/blood-2","effects/blood3","decals/blood1"}
RB.DecalMaterials = {"Blood","ManhackCut","Impact.Blood","Flesh","Blood1","Blood2","Blood3","Gunshot","PaintBall","Dark"}
RB.FloorDecalTypes = {"Blood","Blood1","ManhackCut"}
RB.WallDecalTypes = {"Blood","Impact.Blood","ManhackCut","Flesh"}

------------------------------------------------------------
-- 5. ЗВУКИ
------------------------------------------------------------
RB.FleshSounds = {"physics/flesh/flesh_impact_bullet1.wav","physics/flesh/flesh_impact_bullet2.wav","physics/flesh/flesh_impact_bullet3.wav","physics/flesh/flesh_impact_hard1.wav","physics/flesh/flesh_impact_hard2.wav","physics/flesh/flesh_squishy_impact_hard1.wav","physics/flesh/flesh_squishy_impact_hard2.wav","physics/flesh/flesh_bloody_impact_hard1.wav"}
RB.DripSounds = {"ambient/water/drip1.wav","ambient/water/drip2.wav","ambient/water/drip3.wav","ambient/water/drip4.wav"}
RB.PuddleSounds = {"ambient/water/water_splash1.wav","ambient/water/water_splash2.wav"}
RB.SquishSounds = {"physics/flesh/flesh_squishy_impact_hard2.wav","physics/flesh/flesh_bloody_impact_hard1.wav"}
RB.BandageSounds = {"items/battery_pickup.wav","items/medshot4.wav"}

------------------------------------------------------------
-- 6. РОБОТЫ / ЗОМБИ / ПРИШЕЛЬЦЫ - ОПРЕДЕЛЕНИЕ
------------------------------------------------------------
RB.RobotKeywords = {"combine","metropolice","police","robot","droid","android","cyborg","bionicle","clank","mech","turret","drone","bot","terminator","mechwarrior","assassin_droid","sentry","roller","hunter","strider"}
RB.ZombieKeywords = {"zombie","zombine","poison","fastzombie","ghoul","undead","walker","shambler"}
RB.AlienKeywords = {"antlion","vortigaunt","alien","headcrab","barnacle","xeno","bullsquid","houndeye","gonarch","nihilanth","leech","ichthyosaur"}

function RB.IsRobot(ent)
    if not IsValid(ent) then return false end
    local cn = string.lower(ent:GetClass() or "") local md = string.lower(ent:GetModel() or "")
    if string.find(cn,"combine") or string.find(cn,"metropolice") or string.find(cn,"turret") or string.find(cn,"roller") or string.find(cn,"droid") or string.find(cn,"robot") or string.find(cn,"android") or string.find(cn,"drone") then return true end
    for _,k in ipairs(RB.RobotKeywords) do if string.find(md,k,1,true) or string.find(cn,k,1,true) then return true end end
    if ent.RB_IsRobot then return true end
    return false
end
function RB.IsZombie(ent)
    if not IsValid(ent) then return false end
    local cn = string.lower(ent:GetClass() or "") local md = string.lower(ent:GetModel() or "")
    for _,k in ipairs(RB.ZombieKeywords) do if string.find(md,k,1,true) or string.find(cn,k,1,true) then return true end end
    if ent.RB_IsZombie then return true end
    return false
end
function RB.IsAlien(ent)
    if not IsValid(ent) then return false end
    local cn = string.lower(ent:GetClass() or "") local md = string.lower(ent:GetModel() or "")
    for _,k in ipairs(RB.AlienKeywords) do if string.find(md,k,1,true) or string.find(cn,k,1,true) then return true end end
    if ent.RB_IsAlien then return true end
    return false
end

-- Кастомные цвета из файла (если включён custom_config)
RB.CustomBloodMap = RB.CustomBloodMap or {}
function RB.LoadCustomConfig()
    if not file.Exists("realistic_blood_custom.json","DATA") then return end
    local json = file.Read("realistic_blood_custom.json","DATA")
    if not json then return end
    local data = util.JSONToTable(json)
    if not data then return end
    RB.CustomBloodMap = data
    RB_Log("Загружен кастомный конфиг realistic_blood_custom.json ("..table.Count(data).." записей)")
end
if CLIENT then timer.Simple(2, RB.LoadCustomConfig) else RB.LoadCustomConfig() end

function RB.GetCustomColor(ent)
    if not RB.CustomBloodMap then return nil end
    if not IsValid(ent) then return nil end
    local model = string.lower(ent:GetModel() or "")
    local class = string.lower(ent:GetClass() or "")
    for key, col in pairs(RB.CustomBloodMap) do
        local lkey = string.lower(key)
        if string.find(model,lkey,1,true) or string.find(class,lkey,1,true) then
            return Color(col.r or 130,col.g or 0,col.b or 0)
        end
    end
    return nil
end

------------------------------------------------------------
-- 7. GETCONFIG РАСШИРЕННЫЙ
------------------------------------------------------------
function RB.GetConfig()
    local function F(n,d) local cv=GetConVar(n) if cv then return cv:GetFloat() end return d end
    local function I(n,d) local cv=GetConVar(n) if cv then return cv:GetInt() end return d end
    return {
        enabled = I("rb_enabled",1)==1,
        particleMult = F("rb_particle_multiplier",1.0),
        decalLifetime = F("rb_decal_lifetime",300),
        decalMax = I("rb_decal_max",500),
        puddleEnabled = I("rb_puddle_enabled",1)==1,
        puddleSize = F("rb_puddle_size",1.0),
        trailsEnabled = I("rb_trails_enabled",1)==1,
        wallDrips = I("rb_wall_drips",1)==1,
        soundEnabled = I("rb_sound_enabled",1)==1,
        soundVolume = F("rb_sound_volume",0.8),
        colorR = I("rb_color_r",130), colorG=I("rb_color_g",0), colorB=I("rb_color_b",0),
        quality = I("rb_quality",2), goreLevel=I("rb_gore_level",2),
        robotBlackBlood = I("rb_robot_black_blood",1)==1, robotColorR=I("rb_robot_color_r",20), robotColorG=I("rb_robot_color_g",20), robotColorB=I("rb_robot_color_b",20),
        corpseBlood = I("rb_corpse_blood",1)==1,
        -- новые
        drying = I("rb_blood_drying",1)==1, dryingTime=F("rb_blood_drying_time",120), dryingDark=I("rb_blood_drying_dark",1)==1,
        slip = I("rb_blood_slip",0)==1, slipIntensity=F("rb_blood_slip_intensity",0.5),
        woundSystem = I("rb_wound_system",1)==1, woundMax=I("rb_wound_max",5),
        bleedDamage = I("rb_bleed_damage",0)==1, bleedInterval=F("rb_bleed_damage_interval",2.0), bleedAmount=I("rb_bleed_damage_amount",1),
        bandage = I("rb_bandage_enabled",1)==1, bloodLossSlow=I("rb_blood_loss_slow",0)==1,
        splatterNearby = I("rb_splatter_on_nearby",1)==1, splatterRange=F("rb_splatter_range",120),
        bloodOnWeapon = I("rb_blood_on_weapon",0)==1, stainPlayer=I("rb_blood_stain_player",1)==1, stainTime=F("rb_stain_time",30),
        dismember = I("rb_dismember",0)==1, dismemberThreshold=F("rb_dismember_threshold",150),
        bloodInWater = I("rb_blood_in_water",1)==1, poolMerge=I("rb_pool_merge",1)==1, poolMergeDist=F("rb_pool_merge_dist",100),
        zombieBlood = I("rb_zombie_blood",1)==1, zombieR=I("rb_zombie_color_r",80), zombieG=I("rb_zombie_color_g",100), zombieB=I("rb_zombie_color_b",20),
        alienBlood = I("rb_alien_blood",0)==1, alienR=I("rb_alien_color_r",60), alienG=I("rb_alien_color_g",200), alienB=I("rb_alien_color_b",20),
        arterial = I("rb_arterial_spray",1)==1, arterialInterval=F("rb_arterial_interval",0.8),
        dynamicQuality = false, -- отключено: постоянно меняет качество, вызывает мерцание fpsThreshold=I("rb_fps_threshold",50),
        lowViolence = I("rb_low_violence",0)==1, footstepSound=I("rb_footstep_sound",1)==1,
        bloodOnVehicleWheels = I("rb_blood_on_vehicle_wheels",1)==1, customConfig=I("rb_custom_config",1)==1
    }
end

function RB.GetBloodColorForEntity(ent, randomize)
    local cfg = RB.GetConfig()
    local custom = RB.GetCustomColor and RB.GetCustomColor(ent)
    local r,g,b
    if custom then r,g,b = custom.r, custom.g, custom.b
    elseif cfg.customConfig and RB.CustomBloodMap and next(RB.CustomBloodMap)~=nil then
        -- уже проверено в GetCustom
    end

    if not r then
        if cfg.lowViolence then r,g,b = 255,255,255 -- low violence - белые искры, но цвет не важен
        elseif cfg.robotBlackBlood and RB.IsRobot(ent) then r,g,b = cfg.robotColorR,cfg.robotColorG,cfg.robotColorB
        elseif cfg.zombieBlood and RB.IsZombie(ent) then r,g,b = cfg.zombieR,cfg.zombieG,cfg.zombieB
        elseif cfg.alienBlood and RB.IsAlien(ent) then r,g,b = cfg.alienR,cfg.alienG,cfg.alienB
        else r,g,b = cfg.colorR,cfg.colorG,cfg.colorB end
    end

    if randomize then
        if r<50 and g<50 and b<50 then -- чёрная - малая вариация
            r=math.Clamp(r+math.random(-8,8),0,255) g=math.Clamp(g+math.random(-8,8),0,255) b=math.Clamp(b+math.random(-8,8),0,255)
        else
            r=math.Clamp(r+math.random(-15,15),0,255) g=math.Clamp(g+math.random(-10,10),0,255) b=math.Clamp(b+math.random(-10,10),0,255)
        end
    end
    return Color(r,g,b)
end
function RB.GetBloodColor(rand) return RB.GetBloodColorForEntity(nil,rand) end

function RB.GetWeaponType(weaponEntity, dmgType)
    if dmgType then
        if bit.band(dmgType, DMG_BLAST)~=0 or bit.band(dmgType, DMG_BLAST_SURFACE)~=0 then return "explosive" end
        if bit.band(dmgType, DMG_BUCKSHOT)~=0 then return "shotgun" end
        if bit.band(dmgType, DMG_CLUB)~=0 or bit.band(dmgType, DMG_SLASH)~=0 then return "melee" end
        if bit.band(dmgType, DMG_BURN)~=0 then return "flame" end
        if bit.band(dmgType, DMG_CRUSH)~=0 or bit.band(dmgType, DMG_VEHICLE)~=0 then return "crush" end
    end
    if not IsValid(weaponEntity) then return "generic" end
    local cn = string.lower(weaponEntity:GetClass() or "")
    if string.find(cn,"shotgun") or string.find(cn,"m3") or string.find(cn,"xm1014") or string.find(cn,"nova") then return "shotgun"
    elseif string.find(cn,"rpg") or string.find(cn,"grenade") or string.find(cn,"frag") or string.find(cn,"explos") or string.find(cn,"slam") then return "explosive"
    elseif string.find(cn,"sniper") or string.find(cn,"awp") or string.find(cn,"scout") or string.find(cn,"sg550") or string.find(cn,"g3sg1") then return "sniper"
    elseif string.find(cn,"ak47") or string.find(cn,"m4") or string.find(cn,"aug") or string.find(cn,"famas") or string.find(cn,"galil") or string.find(cn,"rifle") then return "rifle"
    elseif string.find(cn,"smg") or string.find(cn,"mp5") or string.find(cn,"ump") or string.find(cn,"p90") or string.find(cn,"mac10") or string.find(cn,"mp7") then return "smg"
    elseif string.find(cn,"pistol") or string.find(cn,"deagle") or string.find(cn,"glock") or string.find(cn,"usp") then return "pistol"
    elseif string.find(cn,"crowbar") or string.find(cn,"knife") or string.find(cn,"melee") or string.find(cn,"fist") or string.find(cn,"sword") then return "melee"
    elseif string.find(cn,"crossbow") or string.find(cn,"ar2") and string.find(cn,"bolt") then return "crossbow"
    elseif string.find(cn,"flame") or string.find(cn,"fire") or string.find(cn,"molotov") then return "flame"
    else
        local hold = weaponEntity.GetHoldType and weaponEntity:GetHoldType() or ""
        hold = string.lower(hold)
        if hold=="shotgun" then return "shotgun" elseif hold=="rpg" then return "explosive" elseif hold=="ar2" or hold=="smg" then return "smg" elseif hold=="pistol" then return "pistol" elseif hold=="melee" then return "melee" end
    end
    return "generic"
end

function RB.CheckCompatibility()
    local conflicts={}
    if _G["BloodMod"] or _G["WICKED_BLOOD"] then table.insert(conflicts,"другой мод крови") end
    if #conflicts>0 then RB_Log("Внимание: "..table.concat(conflicts,", ")) end
end
RB.CheckCompatibility()
RB_Log("Shared v1.2 MEGA загружен - "..table.Count(RB.WeaponProfiles).." профилей оружия, 40+ ConVars")
