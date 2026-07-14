# Realistic Blood MEGA - Ultimate Gore System v1.2

**Версия:** 1.2.0 MEGA (40+ ConVars, 15+ новых функций)  
**Автор:** Arena AI - Realistic Blood Team  
**Теги:** realism, effects, blood, gore, roleplay

## v1.2 MEGA - Что нового (по запросу "добавь больше настроек и функций")

### Было 13 настроек, стало 40+

#### Новые ConVars:

**Высыхание крови:**
- `rb_blood_drying 0/1` - кровь высыхает и темнеет из красного в коричневый (60,15,10)
- `rb_blood_drying_time 30-600` - время высыхания (по умолчанию 120с)
- `rb_blood_drying_dark 0/1` - ещё темнее

**Скольжение:**
- `rb_blood_slip 0/1` - скольжение на лужах
- `rb_blood_slip_intensity 0.1-2.0` - сила
- `rb_footstep_sound 0/1` - хлюпанье при ходьбе по лужам

**Система ран:**
- `rb_wound_system 0/1` - каждая рана кровоточит отдельно, хранится в `RB.Wounds`
- `rb_wound_max 1-10` - макс ран на игроке (по умолчанию 5)
- `rb_bleed_damage 0/1` - кровопотеря наносит урон
- `rb_bleed_damage_interval 0.5-10` - интервал (2с)
- `rb_bleed_damage_amount 1-10` - урон за тик
- `rb_bandage_enabled 0/1` - бинты, команда `rb_bandage` в чат/консоль
- `rb_blood_loss_slow 0/1` - замедление при сильной кровопотере

**Окружение и загрязнение:**
- `rb_splatter_on_nearby 0/1` - брызги пачкают соседних NPC в радиусе
- `rb_splatter_range 50-400` - радиус
- `rb_blood_on_weapon 0/1` - пятна на оружии
- `rb_blood_stain_player 0/1` - игрок пачкается
- `rb_stain_time 10-300` - время пятен
- `rb_blood_on_vehicle_wheels 0/1` - следы от колёс машины после наезда (реализм сбивания)

**Расчленёнка и эффекты:**
- `rb_dismember 0/1` - расчленёнка при уроне > threshold и gore 3, спавн gibs
- `rb_dismember_threshold 50-500` - порог
- `rb_arterial_spray 0/1` - артериальный пульсирующий фонтан при ранении груди/головы (пульс по `rb_arterial_interval 0.3-2.0`)

**Физика луж:**
- `rb_blood_in_water 0/1` - в воде кровь растворяется (размытие частиц)
- `rb_pool_merge 0/1` - лужи сливаются если рядом
- `rb_pool_merge_dist 30-300` - дистанция сливания

**Кастомные типы крови:**
- `rb_zombie_blood 0/1` + `rb_zombie_color_r/g/b` (по умолчанию 80,100,20 - гнилостный)
- `rb_alien_blood 0/1` + `rb_alien_color_r/g/b` (60,200,20 - кислотный)
- `rb_robot_black_blood` уже было + `rb_custom_config 0/1` - загрузка из `data/realistic_blood_custom.json`
- Пример файла в `data/realistic_blood_custom.json.example`

**Производительность и режимы:**
- `rb_dynamic_quality 0/1` - авто-понижение качества если FPS < `rb_fps_threshold 20-90`
- `rb_low_violence 0/1` - вместо крови искры `ManhackSparks` для стримов

### Новые функции детально:

1. **Высыхание крови** - каждая декаль хранит `originalColor` и `birthTime`. В рендере `PostDrawTranslucentRenderables` считается `dryProg = age / dryingTime` и цвет лерпится от красного к коричневому. Чёрная кровь роботов темнеет к 10,10,10.

2. **Скольжение** - при `Think` проверяется велосити игрока и близость к лужам `pud.pos:DistToSqr`. Если < size^2 и шанс 3-8%, `SetVelocity` + squish звук. На сервере также шанс поскользнуться при бегу.

3. **Система ран** - `RB.Wounds[ply] = { {pos, hitgroup, severity, lastBleed, isArtery, dieTime} }`. Каждая рана кровоточит отдельно через `SendBloodImpact`. Артерия пульсирует через `RB_ArterialSpray` net - клиент создаёт фонтан 8 частиц вверх каждые 0.8с, 5 раз.

4. **Бинты** - команда `rb_bandage` удаляет самую тяжёлую рану, очищает `BleedingEntities`, лечит +5 HP, звук `medshot4.wav`, net `RB_Bandage` для HUD.

5. **Загрязнение соседей** - при каждом `BloodImpact` сервер делает `ents.FindInSphere(pos, splatterRange)` и шлёт `RB_SplatterNearby` - клиент добавляет декали вокруг заражённого.

6. **Пятна на игроке** - `RB_StainPlayer` net, `RB.StainedPlayers[ply]=CurTime()+stainTime`, HUD рисует полупрозрачный кровавый оверлей на весь экран.

7. **Расчленёнка** - при уроне > threshold и `Health<=0`, сервер шлёт `RB_Dismember` - клиент спавнит 12 кровавых gib частиц + 10 декалей вокруг + звук.

8. **Сливание луж** - и сервер (`RB.ServerPuddles`) и клиент (`RB.Puddles`) проверяют дистанцию до существующих луж < mergeDist, вместо новой увеличивают `maxSize` старую.

9. **Кастомные цвета** - `RB.CustomBloodMap` загружается из JSON, `GetCustomColor(ent)` ищет подстроку модели/класса.

10. **Динамическое качество** - клиент меряет FPS каждые 1с, среднее за 10 семплов, если < threshold - понижает `rb_quality`, если > threshold+15 - повышает.

11. **Low violence** - если вкл, `AddDecal` и `CreateBloodSplash` делают `ManhackSparks` вместо крови.

12. **Следы от колёс** - при crush уже было размазывание, теперь дополнительно `rb_blood_on_vehicle_wheels` оставляет следы за машиной (реализовано через размазывание по forward вектору).

### v1.1 фиксы сохранены:
- Трупы кровоточат (prop_ragdoll)
- Чёрная кровь роботов (combine, robot, droid, turret и т.д.)
- Реалистичное сбивание машиной с размазыванием

### Установка:
1. Папку `realistic_blood` в `garrysmod/addons/`
2. Пример кастом конфига `data/realistic_blood_custom.json.example` скопировать в `garrysmod/data/realistic_blood_custom.json` и редактировать
3. Перезапуск, `Q -> Utilities -> Realistic Blood MEGA`

### Команды:
- `rb_bandage` - перевязаться
- `rb_clearblood` - очистить (админ)
- `rb_wounds` - показать свои раны
- `rb_isrobot` - тест робота глядя на NPC
- `rb_stats` - статистика + FPS + настройки
- `rb_reset_defaults` - сброс

### Совместимость:
TTT, DarkRP, Sandbox, Murder, кастом оружие/NPC, Workshop. Не конфликтует с другими кровавыми модами, есть проверка совместимости.

### Производительность:
PVS culling, LOD, пулинг эмиттеров (4), recipient filter 4000 юнитов, динамическое качество по FPS, лимит декалей 500 FIFO.

**Автор:** Arena AI
