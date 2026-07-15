# LivroCaixa — Sistema de Fluxo de Caixa

Sistema web (HTML/CSS/JS + Supabase) que digitaliza a lógica da planilha
`Fluxo_de_Caixa.xlsm`: cadastros → lançamentos com status → relatórios e
dashboards calculados automaticamente. Pensado para ser o "sistema filho"
que futuramente alimenta um sistema mãe de consultoria.

## Estrutura do repositório

```
fluxocaixa/
├── index.html              # Login
├── pages/
│   └── dashboard.html      # Shell autenticado com menu superior em cascata
├── css/
│   └── design-system.css   # Tokens de cor/tipografia + componentes
├── js/
│   └── supabase-client.js  # Cliente único do Supabase + helpers de sessão
└── supabase/
    └── schema.sql          # Schema completo (tabelas, RLS, auditoria)
```

## Como a lógica da planilha virou banco de dados

| Planilha (abas)                          | Tabela Supabase                        |
|-------------------------------------------|-----------------------------------------|
| 201/202/203_PC (plano de contas)          | `plano_contas`                          |
| 204_grupo                                 | `grupos_empresariais`                   |
| 205_conta (contas bancárias)              | `contas_bancarias`                      |
| 206_cc (centro de custo)                  | `centros_custo`                         |
| 207_fav (favorecidos)                     | `favorecidos`                           |
| Abas 1 a 12 (lançamentos por mês)         | `lancamentos` (uma tabela só, filtrada por `data`) |
| 6.x Budget/Forecast                       | `orcamentos`                            |
| — (não existia na planilha)               | `usuarios`, `perfis_acesso`, `auditoria`, `configuracoes`, `tenants` |

Os relatórios (4.x Fluxo de Caixa, 5.x CAR/CAP, 701-705 Dashboards) deixam de
ser fórmulas de planilha e passam a ser **queries/views** sobre `lancamentos`,
filtradas por `status` (pago / em_aberto / inadimplente) — exatamente a mesma
lógica da coluna Status das abas 1-12.

## Multi-tenant e segurança

- Cada **cliente da consultoria** é uma linha em `tenants`.
- Dentro de um tenant, pode haver múltiplos **grupos empresariais** (como
  IPLAMM/KRATOS/DÍLSON na planilha original).
- **Row Level Security (RLS)** garante que cada usuário só veja dados do
  próprio tenant — isso é o que torna seguro múltiplos clientes dividindo o
  mesmo projeto Supabase.
- **Auditoria**: trigger automático grava toda alteração em `lancamentos`
  (quem, quando, valor antes/depois). O mesmo padrão de trigger deve ser
  replicado nas demais tabelas sensíveis conforme formos avançando.
- **Níveis de acesso**: tabela `perfis_acesso` guarda um JSON de permissões
  por módulo (ex: `{"lancamentos":"rw","usuarios":"none"}"`), atribuído a
  cada usuário.

## Como colocar no ar

1. **Supabase**: crie um projeto, rode `supabase/schema.sql` no SQL Editor,
   ative o provedor de e-mail/senha em Authentication.
2. Copie a `Project URL` e a `anon public key` para `js/supabase-client.js`.
3. **GitHub**: suba esta pasta como está — é HTML/CSS/JS puro, não precisa
   de build. Pode virar GitHub Pages para teste, ou ser servido por qualquer
   host estático.
4. Crie o primeiro `tenant`, `usuario` (vinculado a um usuário criado no
   Supabase Auth) e comece a cadastrar plano de contas.

## Próximos passos (o que vamos desenhando nas próximas rodadas)

- [ ] Tela de **Novo Lançamento** (formulário completo com todos os campos)
- [ ] Tela de **Cadastros** (Plano de Contas, Grupos, Contas, Centro de Custo, Favorecidos) com CRUD
- [ ] Telas de **Relatórios** (Fluxo Diário/Mensal, CAR/CAP, Budget x Forecast)
- [ ] Tela de **Usuários e Níveis de Acesso**
- [ ] Tela de **Auditoria** (consulta ao log)
- [ ] Tela de **Configurações**
- [ ] Views/RPCs no Supabase para os cálculos de saldo acumulado, taxa de
      realização (Budget x Realizado) e inadimplência
- [ ] Menu mobile (drawer) para o menu superior em telas pequenas
