-- Four Fit - APAGA TUDO (tabelas, funcoes e logins). Rodar antes do schema.sql para recomecar do zero.
drop table if exists annotations, students, trainers, companies cascade;
drop function if exists public.my_trainer_id();
drop function if exists public.student_by_token(uuid);
drop function if exists public.save_annotations_by_token(uuid, integer, jsonb, jsonb);
delete from auth.users;
