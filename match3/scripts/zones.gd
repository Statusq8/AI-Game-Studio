extends RefCounted
## Зоны зоопарка и задания ремонта (GDD «Зоопарк мечты», раздел 8).
## pos — место предмета в долях экрана зоны (x 0..1, y 0..1). kind — как рисовать предмет (заглушка до ИИ-графики).

const ZONES := [
	{"name": "Вход и касса", "helper": "Енот Тоша", "animal": "Павлин", "tasks": [
		{"name": "Ворота", "kind": "gate", "cost": 2, "pos": Vector2(0.50, 0.33)},
		{"name": "Касса", "kind": "booth", "cost": 2, "pos": Vector2(0.20, 0.47)},
		{"name": "Забор", "kind": "fence", "cost": 1, "pos": Vector2(0.80, 0.50)},
		{"name": "Фонари", "kind": "lamp", "cost": 1, "pos": Vector2(0.33, 0.62)},
		{"name": "Клумба", "kind": "flowers", "cost": 1, "pos": Vector2(0.68, 0.66)},
	]},
	{"name": "Бамбуковая роща", "helper": "Обезьянка Чика", "animal": "Красная панда", "tasks": [
		{"name": "Бамбук", "kind": "tree", "cost": 1, "pos": Vector2(0.18, 0.36)},
		{"name": "Домик панды", "kind": "house", "cost": 3, "pos": Vector2(0.55, 0.34)},
		{"name": "Мостик", "kind": "bridge", "cost": 2, "pos": Vector2(0.30, 0.55)},
		{"name": "Пруд", "kind": "pond", "cost": 2, "pos": Vector2(0.72, 0.53)},
		{"name": "Скамейка", "kind": "bench", "cost": 1, "pos": Vector2(0.48, 0.68)},
		{"name": "Фонарики", "kind": "lamp", "cost": 1, "pos": Vector2(0.84, 0.70)},
	]},
	{"name": "Вольер слонов", "helper": "Слонёнок Бим", "animal": "Слон", "tasks": [
		{"name": "Ограда", "kind": "fence", "cost": 1, "pos": Vector2(0.50, 0.30)},
		{"name": "Бассейн", "kind": "pond", "cost": 2, "pos": Vector2(0.25, 0.45)},
		{"name": "Навес", "kind": "house", "cost": 2, "pos": Vector2(0.72, 0.42)},
		{"name": "Дерево", "kind": "tree", "cost": 1, "pos": Vector2(0.15, 0.62)},
		{"name": "Табличка", "kind": "sign", "cost": 1, "pos": Vector2(0.45, 0.60)},
		{"name": "Кормушка", "kind": "booth", "cost": 2, "pos": Vector2(0.80, 0.63)},
		{"name": "Фонтан", "kind": "fountain", "cost": 3, "pos": Vector2(0.55, 0.74)},
	]},
	{"name": "Обезьяний остров", "helper": "Попугай Кеша", "animal": "Обезьяны", "tasks": [
		{"name": "Пальмы", "kind": "tree", "cost": 1, "pos": Vector2(0.15, 0.32)},
		{"name": "Хижина", "kind": "house", "cost": 2, "pos": Vector2(0.50, 0.30)},
		{"name": "Канатный мост", "kind": "bridge", "cost": 2, "pos": Vector2(0.80, 0.38)},
		{"name": "Остров", "kind": "pond", "cost": 3, "pos": Vector2(0.35, 0.48)},
		{"name": "Горка", "kind": "gate", "cost": 2, "pos": Vector2(0.70, 0.55)},
		{"name": "Лодка", "kind": "bench", "cost": 1, "pos": Vector2(0.20, 0.64)},
		{"name": "Табличка", "kind": "sign", "cost": 1, "pos": Vector2(0.50, 0.68)},
		{"name": "Фонари", "kind": "lamp", "cost": 1, "pos": Vector2(0.85, 0.72)},
	]},
	{"name": "Пруд с фламинго", "helper": "Фламинго Роза", "animal": "Фламинго", "tasks": [
		{"name": "Пруд", "kind": "pond", "cost": 3, "pos": Vector2(0.50, 0.40)},
		{"name": "Кувшинки", "kind": "flowers", "cost": 1, "pos": Vector2(0.28, 0.33)},
		{"name": "Беседка", "kind": "house", "cost": 2, "pos": Vector2(0.80, 0.32)},
		{"name": "Мостик", "kind": "bridge", "cost": 2, "pos": Vector2(0.18, 0.52)},
		{"name": "Камыши", "kind": "tree", "cost": 1, "pos": Vector2(0.80, 0.52)},
		{"name": "Фонари", "kind": "lamp", "cost": 1, "pos": Vector2(0.35, 0.65)},
		{"name": "Скамейки", "kind": "bench", "cost": 1, "pos": Vector2(0.62, 0.64)},
		{"name": "Фонтан", "kind": "fountain", "cost": 3, "pos": Vector2(0.18, 0.74)},
		{"name": "Цветы", "kind": "flowers", "cost": 1, "pos": Vector2(0.82, 0.74)},
	]},
]

## Три варианта дизайна каждого предмета (основной цвет).
const DESIGNS := [Color("#c98a4b"), Color("#4fa3e0"), Color("#e0566b")]
const DESIGN_NAMES := ["Дерево", "Небо", "Ягода"]
