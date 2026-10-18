-- Four Fit - dados iniciais (rodar depois do schema.sql)
-- Troque os emails pelos reais. Emails SEMPRE em minusculo.
-- Cada treinador precisa de um usuario em Authentication > Users > Add user
-- com o mesmo email (marcar "Auto Confirm User").

with c as (
  insert into companies (name) values ('Four Fit Consultoria') returning id
)
insert into trainers (company_id, name, email)
select c.id, t.name, t.email
from c, (values
  ('Roberto Oliveira', 'roberto.oliveira@fourfit.exemplo.com'),
  ('Mariana Costa',    'mariana.costa@fourfit.exemplo.com'),
  ('Felipe Andrade',   'felipe.andrade@fourfit.exemplo.com'),
  ('Juliana Ramos',    'juliana.ramos@fourfit.exemplo.com'),
  ('Thiago Moreira',   'thiago.moreira@fourfit.exemplo.com')
) as t(name, email);
