# «Три в ряд» (панда и зоопарк) — стиль и промпты

Решение №26: объёмный мультяшный стиль. Владелец генерирует по промптам (Nano Banana), Claude обрабатывает и встраивает.
Не добавлять в промпты названия чужих игр, персонажей и художников.

## Единый стиль (в конце каждого промпта)
`Stylized 3D cartoon render, casual mobile puzzle game asset, soft studio lighting, glossy smooth materials, vibrant saturated colors, chunky rounded shapes, subtle rim light, high detail, centered, plain solid white background, no text, no ground shadow`

## Правила
- Фишки и особые фишки — 1:1, один предмет по центру, вид спереди, чуть сверху.
- Сначала утверждаем эталон панды, потом эмоции/позы по нему как по референсу.
- Фон белый — я вырежу его сам.

## Пачка 1 — эталон стиля

### Панда (эталон героя), 1:1
`Full body game mascot character, cute chubby young panda zookeeper, big friendly eyes, small round ears, wearing a green zookeeper vest with a paw-print badge and a tan safari hat, standing upright, front 3/4 view, arms slightly open in a welcoming pose, happy smile, Stylized 3D cartoon render, casual mobile puzzle game asset, soft studio lighting, glossy smooth materials, vibrant saturated colors, chunky rounded shapes, subtle rim light, high detail, centered, plain solid white background, no text, no ground shadow, 1:1`

### Фишки, 1:1 (по одной картинке)
1. Красная: `Single game tile icon, shiny red apple with one green leaf, Stylized 3D cartoon render, casual mobile puzzle game asset, soft studio lighting, glossy smooth materials, vibrant saturated colors, chunky rounded shapes, subtle rim light, high detail, centered, plain solid white background, no text, no ground shadow, 1:1`
2. Синяя: `Single game tile icon, cute plump blue fish, simple rounded shape, Stylized 3D cartoon render, casual mobile puzzle game asset, soft studio lighting, glossy smooth materials, vibrant saturated colors, chunky rounded shapes, subtle rim light, high detail, centered, plain solid white background, no text, no ground shadow, 1:1`
3. Зелёная: `Single game tile icon, bright green bamboo leaf bundle of three leaves, Stylized 3D cartoon render, casual mobile puzzle game asset, soft studio lighting, glossy smooth materials, vibrant saturated colors, chunky rounded shapes, subtle rim light, high detail, centered, plain solid white background, no text, no ground shadow, 1:1`
4. Жёлтая: `Single game tile icon, single curved yellow banana, Stylized 3D cartoon render, casual mobile puzzle game asset, soft studio lighting, glossy smooth materials, vibrant saturated colors, chunky rounded shapes, subtle rim light, high detail, centered, plain solid white background, no text, no ground shadow, 1:1`
5. Фиолетовая: `Single game tile icon, compact bunch of purple grapes, Stylized 3D cartoon render, casual mobile puzzle game asset, soft studio lighting, glossy smooth materials, vibrant saturated colors, chunky rounded shapes, subtle rim light, high detail, centered, plain solid white background, no text, no ground shadow, 1:1`
6. Оранжевая (на будущее): `Single game tile icon, orange carrot with green top, Stylized 3D cartoon render, casual mobile puzzle game asset, soft studio lighting, glossy smooth materials, vibrant saturated colors, chunky rounded shapes, subtle rim light, high detail, centered, plain solid white background, no text, no ground shadow, 1:1`

### Особые фишки, 1:1
7. Ракета: `Single game booster icon, small horizontal toy rocket, red and white body, round porthole, orange flame at the back, Stylized 3D cartoon render, casual mobile puzzle game asset, soft studio lighting, glossy smooth materials, vibrant saturated colors, chunky rounded shapes, subtle rim light, high detail, centered, plain solid white background, no text, no ground shadow, 1:1`
8. Бомба: `Single game booster icon, round cartoon bomb, dark navy body with a golden band, lit fuse with a bright spark, Stylized 3D cartoon render, casual mobile puzzle game asset, soft studio lighting, glossy smooth materials, vibrant saturated colors, chunky rounded shapes, subtle rim light, high detail, centered, plain solid white background, no text, no ground shadow, 1:1`
9. Радужный шар: `Single game booster icon, glowing magic sphere with swirling rainbow colors inside, sparkles around it, Stylized 3D cartoon render, casual mobile puzzle game asset, soft studio lighting, glossy smooth materials, vibrant saturated colors, chunky rounded shapes, subtle rim light, high detail, centered, plain solid white background, no text, no ground shadow, 1:1`
10. Пропеллер: `Single game booster icon, toy propeller with three bright yellow blades and a red center cap, Stylized 3D cartoon render, casual mobile puzzle game asset, soft studio lighting, glossy smooth materials, vibrant saturated colors, chunky rounded shapes, subtle rim light, high detail, centered, plain solid white background, no text, no ground shadow, 1:1`

### Фон уровня, 9:16
11. `Vertical mobile game background 9:16, sunny cheerful cartoon zoo, green lawn, wooden fences, palm trees and bamboo, a small pond, colorful animal enclosures in the distance, soft blurred depth of field, bright blue sky, empty calm center area, no characters, no text. Stylized 3D cartoon render, soft studio lighting, vibrant saturated colors`

Пачка 1 встроена в игру 2026-11-13 (версия 0.3.0): панда, 6 фишек, ракета, бомба, радужный шар, пропеллер, фон зоопарка. Белый фон вырезан скриптом, фишки 192 px.

## Пачка 2 — фишки «кристаллы-лапки» (решение 2026-11-13: фрукты и рыба не та тема)
Одинаковое построение у всех: крупная простая форма, одна выпуклая лапка в центре, без лишних деталей — чтобы на маленьком поле сразу читался цвет и форма.
1. Красный — круглый: `Single game tile icon, round red ruby gemstone with smooth large facets and an embossed glossy paw print in the center, simple bold silhouette, no extra decorations, Stylized 3D cartoon render, casual mobile puzzle game asset, soft studio lighting, glossy smooth materials, vibrant saturated colors, chunky rounded shapes, subtle rim light, high detail, centered, plain solid white background, no text, no ground shadow, 1:1`
2. Синий — капля: `Single game tile icon, teardrop-shaped blue sapphire gemstone with smooth large facets and an embossed glossy paw print in the center, simple bold silhouette, no extra decorations, Stylized 3D cartoon render, casual mobile puzzle game asset, soft studio lighting, glossy smooth materials, vibrant saturated colors, chunky rounded shapes, subtle rim light, high detail, centered, plain solid white background, no text, no ground shadow, 1:1`
3. Зелёный — шестигранник: `Single game tile icon, hexagonal green emerald gemstone with smooth large facets and an embossed glossy paw print in the center, simple bold silhouette, no extra decorations, Stylized 3D cartoon render, casual mobile puzzle game asset, soft studio lighting, glossy smooth materials, vibrant saturated colors, chunky rounded shapes, subtle rim light, high detail, centered, plain solid white background, no text, no ground shadow, 1:1`
4. Жёлтый — звезда: `Single game tile icon, five-pointed star-shaped yellow topaz gemstone with rounded tips with smooth large facets and an embossed glossy paw print in the center, simple bold silhouette, no extra decorations, Stylized 3D cartoon render, casual mobile puzzle game asset, soft studio lighting, glossy smooth materials, vibrant saturated colors, chunky rounded shapes, subtle rim light, high detail, centered, plain solid white background, no text, no ground shadow, 1:1`
5. Фиолетовый — ромб: `Single game tile icon, diamond-shaped (rhombus) purple amethyst gemstone with smooth large facets and an embossed glossy paw print in the center, simple bold silhouette, no extra decorations, Stylized 3D cartoon render, casual mobile puzzle game asset, soft studio lighting, glossy smooth materials, vibrant saturated colors, chunky rounded shapes, subtle rim light, high detail, centered, plain solid white background, no text, no ground shadow, 1:1`
6. Оранжевый — квадрат: `Single game tile icon, rounded square orange citrine gemstone with smooth large facets and an embossed glossy paw print in the center, simple bold silhouette, no extra decorations, Stylized 3D cartoon render, casual mobile puzzle game asset, soft studio lighting, glossy smooth materials, vibrant saturated colors, chunky rounded shapes, subtle rim light, high detail, centered, plain solid white background, no text, no ground shadow, 1:1`
