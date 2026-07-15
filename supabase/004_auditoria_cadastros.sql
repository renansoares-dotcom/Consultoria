-- ============================================================================
-- MIGRAÇÃO 004 — Auditoria estendida aos cadastros
-- Até aqui só "lancamentos" tinha o trigger de auditoria. Replica o mesmo
-- padrão (função fn_auditoria já existente no schema.sql) para as tabelas
-- de cadastro, para rastrear quem criou/editou/excluiu cada uma.
-- ============================================================================

create trigger trg_auditoria_plano_contas
  after insert or update or delete on plano_contas
  for each row execute function fn_auditoria();

create trigger trg_auditoria_contas_bancarias
  after insert or update or delete on contas_bancarias
  for each row execute function fn_auditoria();

create trigger trg_auditoria_centros_custo
  after insert or update or delete on centros_custo
  for each row execute function fn_auditoria();

create trigger trg_auditoria_favorecidos
  after insert or update or delete on favorecidos
  for each row execute function fn_auditoria();

create trigger trg_auditoria_grupos_empresariais
  after insert or update or delete on grupos_empresariais
  for each row execute function fn_auditoria();

create trigger trg_auditoria_orcamentos
  after insert or update or delete on orcamentos
  for each row execute function fn_auditoria();

create trigger trg_auditoria_usuarios
  after insert or update or delete on usuarios
  for each row execute function fn_auditoria();
