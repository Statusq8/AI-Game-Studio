extends RefCounted
## Формулы и данные баланса «Охотника за Вратами» (минимальная версия).

const WAVES_PER_GATE := 10
const BOSS_TIME := 30.0
const BOSS_EXTRA_TIME := 15.0
const BUFF_SECONDS := 300.0
const OFFLINE_CAP_SECONDS := 8 * 3600
const OFFLINE_MIN_SECONDS := 60

const BIOMES := [
	{"name": "Лесные Врата", "bg": Color(0.07, 0.15, 0.11), "monster": "Корнеед", "boss": "Древний Корень", "color": Color(0.35, 0.72, 0.42)},
	{"name": "Пещерные Врата", "bg": Color(0.11, 0.10, 0.16), "monster": "Каменный клык", "boss": "Король Сталактитов", "color": Color(0.62, 0.56, 0.74)},
	{"name": "Песчаные Врата", "bg": Color(0.21, 0.15, 0.07), "monster": "Дюнный скорпион", "boss": "Пожиратель Барханов", "color": Color(0.92, 0.72, 0.36)},
	{"name": "Ледяные Врата", "bg": Color(0.06, 0.12, 0.21), "monster": "Морозный волк", "boss": "Владыка Метели", "color": Color(0.56, 0.82, 1.0)},
	{"name": "Руины Врат", "bg": Color(0.15, 0.05, 0.11), "monster": "Безликий страж", "boss": "Падший Хранитель", "color": Color(0.92, 0.36, 0.56)},
]

const HUNTERS := [
	{"name": "Мечник Рэн", "base_dps": 2.0, "base_cost": 25.0, "color": Color(0.32, 0.52, 1.0)},
	{"name": "Лучница Мира", "base_dps": 9.0, "base_cost": 300.0, "color": Color(1.0, 0.62, 0.22)},
	{"name": "Маг Сэй", "base_dps": 40.0, "base_cost": 3500.0, "color": Color(0.72, 0.42, 1.0)},
]

const RANKS := ["E", "D", "C"]
## Сколько Врат нужно закрыть для ранга.
const RANK_GATES := [0, 5, 10]
const RANK_MULT := [1.0, 1.5, 2.25]


static func biome(gate: int) -> Dictionary:
	return BIOMES[(gate - 1) % BIOMES.size()]


static func is_boss(wave: int) -> bool:
	return wave > WAVES_PER_GATE


static func monster_hp(gate: int, wave: int) -> float:
	var w: int = mini(wave, WAVES_PER_GATE)
	var hp := 10.0 * pow(1.6, gate - 1) * (1.0 + 0.15 * (w - 1))
	if is_boss(wave):
		hp *= 8.0
	return ceilf(hp)


static func gold_reward(gate: int, wave: int) -> float:
	var w: int = mini(wave, WAVES_PER_GATE)
	var g := 2.0 * pow(1.5, gate - 1) * (1.0 + 0.1 * (w - 1))
	if is_boss(wave):
		g *= 10.0
	return ceilf(g)


static func tap_damage(level: int) -> float:
	return (1.0 + level) * pow(1.06, level)


static func tap_cost(level: int) -> float:
	return ceilf(5.0 * pow(1.14, level))


static func hunter_dps(index: int, level: int) -> float:
	if level <= 0:
		return 0.0
	return float(HUNTERS[index]["base_dps"]) * level * pow(1.05, level - 1)


static func hunter_cost(index: int, level: int) -> float:
	return ceilf(float(HUNTERS[index]["base_cost"]) * pow(1.15, level))


static func rank_for(gates_cleared: int) -> int:
	var r := 0
	for i in RANKS.size():
		if gates_cleared >= int(RANK_GATES[i]):
			r = i
	return r


static func format_num(value: float) -> String:
	if value < 1000.0:
		return str(int(floorf(value)))
	var suffixes := ["K", "M", "B", "T", "aa", "ab", "ac", "ad", "ae", "af"]
	var v := value
	var i := -1
	while v >= 1000.0 and i < suffixes.size() - 1:
		v /= 1000.0
		i += 1
	if v < 100.0:
		return "%.1f%s" % [v, suffixes[i]]
	return "%d%s" % [int(v), suffixes[i]]
