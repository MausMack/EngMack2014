# PRD – MVP do Cadastro de Produtos (Cosmos, prefixo `PF_`)

**Status:** rascunho para revisão · **Base:** reunião de levantamento, `docs/epico0/001_modelo_construtor.sql` e `docs/epico0/002_sequencia_atividades.md`

## 1. Problema

O Cadastro de Produtos (Cosmos) é um portal em que fornecedores solicitam produtos e várias áreas (Compras, GC, Cadastro, Fiscal, Web, Regulatório, Pricing) aprovam e complementam a ficha. Hoje o fluxo é rígido e frágil:

- as áreas e as permissões por campo são fixas no código, e qualquer mudança exige desenvolvimento;
- o espelho final não traz todos os campos preenchidos ao longo do fluxo, o que compromete a integração;
- o vínculo é com pessoas, não com áreas: quando um comprador sai, a ficha trava;
- não há prazo de espera depois de uma rejeição, e o mesmo produto pode voltar na hora;
- nada impede solicitar um produto que já existe no ERP.

Quem sente: fornecedores (retrabalho e falta de visibilidade), áreas (dependência de pessoas) e gestão (sem controle nem autonomia para configurar). Não resolver mantém o time de TI como gargalo de toda mudança e perpetua fichas travadas e cadastros duplicados.

## 2. Objetivos

| # | Objetivo | Como saberemos |
|---|---|---|
| G1 | Configurar áreas, campos e permissões **sem desenvolvimento e sem alterar o banco** | Um campo ou área novos entram em uso só pelo construtor |
| G2 | Eliminar a dependência de uma pessoa por área | Qualquer usuário da área atende uma ficha; nenhuma ficha parada por desligamento |
| G3 | Ficha final completa e integrável | 100% dos campos marcados para integração chegam ao destino, com log |
| G4 | Impedir cadastro duplicado | 0 solicitações aceitas para EAN já existente no ERP ou já em andamento |
| G5 | Reduzir o retorno imediato de produtos rejeitados | EAN rejeitado só volta após o prazo definido ou por liberação do gestor |

## 3. Fora do escopo (não-objetivos)

- **Tipos data, imagem, HTML e lookup genérico com PBS/RP.** O MVP usa texto curto, texto longo, número e lista; lookup é o Épico 4.
- **Regras entre campos** (ex.: "se tem display, então EAN display é obrigatório"). É o Épico 5.
- **Controle de edição simultânea.** Vale o último a gravar, com log de quem alterou; aviso de conflito fica para a v2.
- **Fluxo de aprovação diferente por ficha.** A ordem das áreas é configurada uma vez e vale para toda ficha.
- **Remoção de produtos da base do ERP pela planilha.** A carga só inclui e atualiza.

## 4. Perfis e histórias de usuário

Acesso restrito: a aplicação roda no tenant do cliente, com usuários do próprio Cosmos e três perfis (Fornecedor, Área, Gestor/Administrador).

### Fornecedor
- Como fornecedor, quero informar o EAN e ser avisado na hora se o produto já existe ou está bloqueado, para não perder tempo preenchendo uma ficha que será recusada.
- Como fornecedor, quero preencher a pré-ficha e depois a minha parte da ficha completa, para concluir a solicitação.
- Como fornecedor, quero ver, quando minha ficha for devolvida, exatamente quais campos foram reprovados e por quê, para corrigir só o necessário.
- Como fornecedor, quero acompanhar o status das minhas solicitações, para saber o que está pendente.
- Como fornecedor, quero ver somente os campos que são pertinentes a mim, para não acessar informação interna.

### Área (vários usuários por área)
- Como usuário de uma área, quero ver os dados do fornecedor e das outras áreas, para decidir com contexto.
- Como usuário de uma área, quero editar apenas os campos liberados para a minha área, para evitar alterações indevidas.
- Como usuário de uma área, quero aprovar, devolver por campo ou rejeitar uma pré-ficha, para dar o parecer da minha área.
- Como usuário de uma área, quero que meus colegas de área possam atender a mesma ficha, para não depender de uma pessoa.

### Gestor/Administrador
- Como gestor, quero criar, ordenar e desativar áreas, para refletir a organização sem pedir desenvolvimento.
- Como gestor, quero criar campos (tipo, tamanho, lista de valores) e definir por área o que é obrigatório e editável, para adaptar o cadastro.
- Como gestor, quero definir a ordem e o paralelismo das áreas que aprovam a pré-ficha, para refletir o processo.
- Como gestor, quero definir quais campos vão para cada integração (ERP, e-commerce), para enviar só o necessário.
- Como gestor, quero carregar por planilha os produtos que já existem no ERP, para impedir duplicidade desde o primeiro dia.
- Como gestor, quero liberar excepcionalmente um EAN rejeitado dentro do prazo de bloqueio, para tratar casos de negócio.
- Como gestor, quero vincular usuários do Cosmos a perfis e áreas, para controlar quem acessa o quê.

## 5. Requisitos

### P0 – Obrigatórios para o MVP

**R1. Perfis e acesso**
Três perfis sobre usuários do Cosmos; um usuário pode pertencer a mais de uma área; o fornecedor só acessa as próprias fichas.
- Dado um fornecedor, quando ele consulta a ficha de outro fornecedor, então recebe erro de acesso.
- O usuário usado em toda consulta vem da sessão autenticada, nunca de parâmetro enviado pelo cliente.

**R2. Construtor de áreas**
Criar, editar, ordenar e desativar áreas; o fornecedor é uma área especial única.
- Dada uma área desativada, então ela deixa de aparecer em novos fluxos e permanece no histórico.

**R3. Construtor de campos**
Tipos: texto curto (1 a 255), texto longo (5000), número (0 a 4 casas decimais) e lista (grid de valores). Cada campo pertence à pré-ficha ou à ficha completa.
- Dado um campo "Descrição do produto" já existente, quando outra área tenta criar campo com a mesma descrição (ignorando maiúsculas e acentos), então é recusado.
- Dado um campo com valor gravado em alguma ficha, quando alguém tenta alterar tipo, tamanho ou etapa, então é recusado; o campo só pode ser cancelado e substituído por outro para as próximas fichas.
- Dado um campo cancelado, então fichas que já têm valor nele o exibem somente leitura e novas fichas não o mostram.
- Valores de lista em uso só podem ser desativados.

**R4. Matriz campo × área**
Por campo e área: obrigatório e editável (obrigatório implica editável). Os campos da pré-ficha são visíveis na ficha completa. O fornecedor só vê campos marcados como visíveis a ele ou que ele preenche.
- Dado um campo sem permissão de edição para a área, quando o usuário tenta gravá-lo, então a gravação é recusada no servidor.

**R5. Pré-ficha e EAN**
O EAN é a chave do produto, normalizado em 14 dígitos. A solicitação é recusada quando o EAN é inválido, já existe na base do ERP, já tem ficha em andamento ou concluída, ou foi rejeitado e está dentro do prazo (sem liberação).
- Dado um EAN existente na base do ERP, quando o fornecedor o informa, então a solicitação é barrada com mensagem clara.

**R6. Gravação e validação de valores**
Valores tipados (texto ou número, sem conversão implícita). Textos não aceitam caracteres de controle; números usam ponto decimal e respeitam as casas do campo; lista só aceita valor ativo. Gravação atômica: qualquer erro cancela tudo. Toda alteração fica registrada (quem, quando, valor anterior e novo).

**R7. Aprovação da pré-ficha**
O fluxo (áreas e ordem) é definido na configuração: ordem igual é simultâneo, ordem diferente é sequencial. Cada ficha recebe uma cópia do fluxo vigente no momento do envio.
- Dado um fluxo Compras e GC (ordem 1) e Fiscal (ordem 2), então Compras e GC decidem juntas e Fiscal só é liberada depois das duas aprovarem.

**R8. Devolução e rejeição**
- *Devolução* (total ou parcial): a ficha volta ao fornecedor (`EM_AJUSTE`); em devolução parcial ele edita **apenas os campos reprovados**; a cada reenvio abre-se um novo ciclo de aprovação.
- *Rejeição definitiva* do produto: status final; grava a data de liberação calculada pelo parâmetro geral de dias de bloqueio.
- *Liberação do gestor*: exceção de uso único para um EAN bloqueado, com motivo obrigatório.

**R9. Ficha completa**
Todas as áreas atuam em paralelo, cada uma nos seus campos. Concluída a ficha, o status é final.

**R10. Base de produtos do ERP**
Carga por planilha (somente gestor), chave EAN, que inclui e atualiza; EAN inválido não derruba a carga e é devolvido numa lista; cada carga fica registrada (totais).

**R11. Integrações**
Cadastro de integrações (ERP, e-commerce etc.); por integração, quais campos são enviados e com qual nome no destino. Após a conclusão da ficha, o envio é enfileirado por integração; cada tentativa registra o payload enviado e a resposta.

**R12. Auditoria da configuração**
Histórico de alterações de áreas, campos, matriz, fluxo de aprovação e parâmetros.

**R13. Acompanhamento básico do fornecedor**
Lista das solicitações do fornecedor com status e pendências.

### P1 – Fast follows
- E-mails e alertas de mudança de status para o fornecedor.
- Dashboard do gestor (fichas por status, tempo por fase, rejeições).
- Tela de acompanhamento e reenvio de falhas de integração.
- Validação do dígito verificador do GTIN.
- Alerta no construtor quando a descrição de um campo novo for muito parecida com a de um existente.
- Lista de caracteres proibidos configurável por integração/ERP.

### P2 – Considerar no desenho (não construir agora)
- Tipos data, imagem, HTML e lookup genérico (Épico 4).
- Regras e validações entre campos (Épico 5).
- Aviso de conflito de edição simultânea.
- Carência pós-rejeição configurável por rejeitador (hoje só o parâmetro geral).

## 6. Métricas de sucesso

Os alvos abaixo são hipóteses; precisam ser confirmados com uma linha de base do processo atual.

**Indicadores iniciais (semanas após o lançamento)**
- Tempo para criar um campo ou área novos pelo construtor: até 1 dia útil, sem envolver desenvolvimento (hoje: depende de release).
- % de fichas concluídas sem intervenção de TI: acima de 95%.
- Solicitações barradas por EAN existente ou bloqueado: medir o volume (indica duplicidade evitada).
- Erros de envio às integrações: abaixo de 2% das fichas concluídas, com reenvio resolvendo o restante.

**Indicadores de longo prazo (meses)**
- Redução do tempo médio da solicitação à conclusão da ficha.
- Redução de fichas paradas por indisponibilidade de uma pessoa: meta de zero.
- Redução de reenvios de produtos rejeitados dentro do prazo de bloqueio.
- Queda de chamados à TI para ajustes de campos e permissões.

Medição: consultas sobre `PF_PreFicha`, `PF_PreFichaValorLog`, `PF_IntegracaoEnvio` e `PF_IntegracaoEnvioLog`. Avaliação em 1 mês e em 1 trimestre.

## 7. Perguntas em aberto

**Bloqueantes (responder antes de construir)**
1. **[Engenharia/Cosmos]** O Cosmos Pro entrega o usuário logado às customs e ao webapp por sessão/token? Define toda a segurança.
2. **[Engenharia]** Versão do SQL Server do tenant (o desenho exige 2017 ou superior) e tabela/coluna de usuários do Cosmos para as chaves estrangeiras.
3. **[Gestor]** Qual é o prazo real de bloqueio por rejeição (o valor atual de 90 dias é só exemplo)?
4. **[Negócio]** Quem aciona "enviar para aprovação" e o que leva da aprovação da pré-ficha para a ficha completa (a última área aprovar, automático)?
5. **[Negócio]** Qual é o critério para concluir a ficha completa (cada área marca "pronto"? todos os obrigatórios preenchidos)?
6. **[Engenharia/Integração]** Contrato de cada integração (ERP, e-commerce): formato, autenticação e como o retorno é tratado.

**Não bloqueantes**
7. **[Negócio]** Reprovação parcial na ficha completa: as demais áreas continuam trabalhando enquanto o fornecedor ajusta?
8. **[Negócio]** Campo criado depois deve aparecer em fichas já abertas?
9. **[Dados]** Volume esperado de EANs na base e de fichas por mês; formato da planilha de carga.
10. **[Gestor]** A planilha de carga deve, no futuro, remover EANs ausentes?
11. **[Negócio]** Quais campos o fornecedor nunca deve ver (ponto de partida para a marcação no construtor)?

## 8. Considerações de cronograma e fases

Não há prazo fixo conhecido. Dependências: acesso ao MCP do Cosmos Pro (skill `PF_`), respostas às perguntas 1 e 2 e contratos de integração (pergunta 6).

Fases sugeridas (detalhe em `002_sequencia_atividades.md`):
1. **Destravar dúvidas e banco** (etapas 0 e 1).
2. **Esqueleto ponta a ponta** com 3 campos de seed (etapa 2), que valida a segurança do usuário logado antes das telas.
3. **Skill `PF_` e construtor**, uma página por vez (etapas 3 e 4).
4. **Workflow e webapps** do fornecedor e das áreas (etapas 5 a 7).
5. **Gestão, integração de saída e homologação** (etapas 8 a 10).

Caminho crítico: `0.3 → 1.1 → esqueleto → skill → campos → matriz → workflow → webapps → homologação`. Se for preciso cortar escopo, os primeiros candidatos são e-mails e alertas, dashboard do gestor e tela de reenvio de integrações.
