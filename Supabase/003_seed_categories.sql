begin;

insert into public.categories (slug, name_en, name_ru, sort_order)
values
  ('minimal', 'Minimal', 'Минимализм', 10),
  ('colorful', 'Colorful', 'Яркие', 20),
  ('pixel-art', 'Pixel Art', 'Пиксель-арт', 30),
  ('accessibility', 'Accessibility', 'Универсальный доступ', 40),
  ('professional', 'Professional', 'Профессиональные', 50),
  ('playful', 'Playful', 'Игровые', 60),
  ('animated', 'Animated', 'Анимированные', 70)
on conflict (slug) do update
set
  name_en = excluded.name_en,
  name_ru = excluded.name_ru,
  sort_order = excluded.sort_order,
  is_active = true;

insert into public.tags (slug, name_en, name_ru)
values
  ('dark', 'Dark', 'Тёмные'),
  ('light', 'Light', 'Светлые'),
  ('high-contrast', 'High Contrast', 'Высокая контрастность'),
  ('monochrome', 'Monochrome', 'Монохромные'),
  ('retina', 'Retina', 'Retina'),
  ('animated', 'Animated', 'Анимированные'),
  ('complete-set', 'Complete Set', 'Полный набор')
on conflict (slug) do update
set
  name_en = excluded.name_en,
  name_ru = excluded.name_ru,
  is_active = true;

commit;
