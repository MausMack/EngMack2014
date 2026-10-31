# Sequência de atividades do MVP (prefixo PF_)

Tamanhos relativos: **P** (até 1 dia), **M** (2 a 3 dias), **G** (uma semana ou mais).
Modelo de referência: `001_modelo_construtor.sql`.

## Etapa 0 – Destravar o que ainda é dúvida (antes de construir)

| # | Atividade | Tam. | Por que vem primeiro |
|---|---|---|---|
| 0.1 | Confirmar versão do SQL Server do tenant (precisa 2017+) | P | O script usa tabelas temporais e `STRING_AGG` |
| 0.2 | Levantar a tabela/coluna de usuários do Cosmos | P | Trocar `UsuarioCosmosId` solto por chave estrangeira |
| 0.3 | Confirmar como a custom/webapp recebe o **usuário logado** (sessão/token) | M | Define a segurança de todas as customs; é o maior risco |
| 0.4 | Gestor define: prazo de bloqueio por rejeição, áreas iniciais e fluxo de aprovação (ordem) | P | Sem isso os seeds ficam de exemplo |
| 0.5 | Acesso ao MCP do Cosmos Pro (ou decidir criar objetos manualmente no início) | P | Define se a skill já nasce funcional |

## Etapa 1 – Banco de dados

| # | Atividade | Tam. |
|---|---|---|
| 1.1 | Rodar o script em ambiente de desenvolvimento e corrigir erros de sintaxe (ainda não foi executado) | M |
| 1.2 | Seeds: áreas reais, usuários de teste (1 fornecedor, 2 de área, 1 admin) e perfis/vínculos | P |
| 1.3 | Script de testes de aceite no banco (ver lista abaixo) | M |

Testes mínimos do banco:
- campo duplicado pela descrição é recusado (inclusive acento/maiúscula);
- campo com valor não aceita mudar tipo/tamanho; valor de lista em uso não muda;
- fornecedor não vê campo sem `VisivelFornecedor`;
- área só grava campo editável; erro de tipo, tamanho, caractere de controle, casas decimais e lista;
- EAN: inválido, já na base, ficha viva, rejeitado dentro do prazo, liberação de uso único;
- fornecedor não acessa ficha de outro.

## Etapa 2 – Esqueleto ponta a ponta (valida a arquitetura antes das telas)

Objetivo: um fornecedor entra, informa o EAN, preenche 3 campos e salva, e uma área de teste vê e edita o que pode. Tudo com seed, **sem** telas do construtor.

| # | Atividade | Tam. |
|---|---|---|
| 2.1 | Seed de 3 campos de teste (texto curto, número, lista) e matriz para 2 áreas | P |
| 2.2 | Custom view `PF_` de campos (`PF_fn_CamposUsuario`) | M |
| 2.3 | Custom view `PF_` de valores (`PF_fn_ValoresPreFicha`) | M |
| 2.4 | Custom action `PF_` criar pré-ficha (`PF_usp_CriarPreFicha`) | M |
| 2.5 | Custom action `PF_` salvar valores (`PF_usp_SalvarValoresPreFicha`) | M |
| 2.6 | Webapp mínimo do fornecedor: informar EAN, ver campos, salvar | M |
| 2.7 | Validar com 2 usuários: permissões, segurança do usuário logado e mensagens de erro | M |

**Ponto de decisão:** se algo da 0.3 ou do formato de retorno das customs não funcionar como o desenho espera, o ajuste acontece aqui, barato, e não depois das telas.

## Etapa 3 – Skill de criação de objetos PF_

Só depois do esqueleto, para a skill codificar o padrão que **funcionou**.

| # | Atividade | Tam. |
|---|---|---|
| 3.1 | Documentar o padrão validado (nomes `PF_`, como criar tabela, formulário, custom view, custom action) | M |
| 3.2 | Skill que gera/aplica o script de tabelas, formulários e customs via MCP Cosmos Pro | G |
| 3.3 | Rodar a skill em um ambiente limpo e comparar com o que foi feito à mão | M |

## Etapa 4 – Construtor (uma página por vez)

| # | Página | Depende de | Tam. |
|---|---|---|---|
| 4.1 | Áreas (cadastro, ordem, ativar/desativar) | Etapa 2 | M |
| 4.2 | Vínculo usuário Cosmos × perfil × áreas | 4.1 | M |
| 4.3 | Campos (tipo, tamanho, etapa, visível ao fornecedor) com grid de valores da lista | 4.1 | G |
| 4.4 | Matriz campo × área (obrigatório/editável) | 4.3 | G |
| 4.5 | Fluxo de aprovação da pré-ficha (`PF_AprovacaoConfig`) e parâmetros gerais (`PF_Parametro`) | 4.1 | M |
| 4.6 | Integrações: cadastro e campos enviados com nome no destino | 4.3 | M |

4.1 e 4.2 podem andar em paralelo com a Etapa 5.

## Etapa 5 – Workflow (custom actions)

| # | Atividade | Tam. |
|---|---|---|
| 5.1 | Enviar para aprovação (copia a configuração para `PF_PreFichaAprovacao`, valida obrigatórios) | M |
| 5.2 | Aprovar por área (respeitando simultâneo/sequencial) e avançar para ficha completa | G |
| 5.3 | Devolver ao fornecedor (parcial = por campo, total) → `EM_AJUSTE`, e reenviar (novo ciclo) | G |
| 5.4 | Rejeitar o produto (grava `BloqueadoAte` pelo parâmetro) | M |
| 5.5 | Concluir a ficha completa (áreas em paralelo) → `CONCLUIDA` e enfileirar integrações | M |

## Etapa 6 – Webapp do fornecedor (fases por página)

| # | Página | Tam. |
|---|---|---|
| 6.1 | Dashboard de acompanhamento (suas fichas por status) | M |
| 6.2 | Nova solicitação (EAN) e pré-ficha | M |
| 6.3 | Ajuste de ficha devolvida (mostra os campos reprovados e o motivo) | M |
| 6.4 | Ficha completa (campos do fornecedor) | M |
| 6.5 | E-mails e alertas de mudança de status | G |

## Etapa 7 – Webapp das áreas

| # | Página | Tam. |
|---|---|---|
| 7.1 | Caixa de tarefas da área (pré-fichas para aprovar, fichas completas) | M |
| 7.2 | Tela de aprovação (ver ficha, aprovar, devolver por campo, rejeitar) | G |
| 7.3 | Ficha completa (campos editáveis da área, status por área) | M |

## Etapa 8 – Gestão

| # | Atividade | Tam. |
|---|---|---|
| 8.1 | Carga da planilha da base de produtos (leitura do arquivo e envio em lotes) | M |
| 8.2 | Liberação de EAN rejeitado (exceção do gestor) | P |
| 8.3 | Dashboard do gestor (fichas por status, tempo por fase, rejeições) | M |

## Etapa 9 – Integração de saída

| # | Atividade | Tam. |
|---|---|---|
| 9.1 | Processo de envio por integração (payload, chamada, log de tentativa e resposta) | G |
| 9.2 | Reenvio de falhas e tela de acompanhamento dos envios | M |

## Etapa 10 – Homologação

| # | Atividade | Tam. |
|---|---|---|
| 10.1 | Fluxo completo com dados reais de 2 ou 3 áreas | M |
| 10.2 | Revisão de segurança (usuário logado, fornecedor isolado, campos ocultos) | M |
| 10.3 | Carga da base inicial real e ajuste dos parâmetros | P |
| 10.4 | Go-live assistido | M |

## Caminho crítico

`0.3 → 1.1 → Etapa 2 → Etapa 3 → 4.3 → 4.4 → Etapa 5 → Etapas 6 e 7 → 10`

## Paralelismo possível
- Etapa 3 (skill) e 4.1/4.2 depois que a Etapa 2 estiver validada.
- Etapas 6 e 7 em paralelo, depois da Etapa 5.
- 8.1 e 8.2 em qualquer momento depois da Etapa 2.
- 9.x só depende de 4.6 e 5.5.

## Se precisar cortar escopo do MVP (sugestão)
Do mais fácil de adiar para o mais difícil: 6.5 (e-mails e alertas), 8.3 (dashboard do gestor), 9.2 (tela de reenvio). O resto compõe o fluxo mínimo.
