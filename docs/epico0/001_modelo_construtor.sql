/* =============================================================================
   Épico 0 - Fundação: modelo do construtor low-code (Cadastro de Produtos)
   Convenção: todo objeto da plataforma usa o prefixo PF_ (tabelas, funções, procs,
   formulários, customs, dashboards e webapps).
   Modelo EAV: PF_PreFichaValor guarda (código da pré-ficha, campo, valor); criar um
   campo novo NÃO altera a estrutura do banco.

   Premissas:
     - SQL Server 2017+ (tabelas temporais, OPENJSON, STRING_AGG).
     - Usuários são os do próprio Cosmos; aqui só guardamos o ID (UsuarioCosmosId).
       O ID deve ser preenchido pelo servidor Cosmos a partir da sessão/token,
       nunca informado pelo cliente (webapp).
     - O fornecedor é uma "área" do tipo FORNECEDOR, assim a matriz campo x área
       serve para os dois (o que é do fornecedor, obrigatório e editável).
     - Pré-ficha e ficha completa são visíveis a todas as áreas internas. O fornecedor
       só vê campos marcados (VisivelFornecedor) ou que ele mesmo preenche.
     - Status da ficha = fase em que ela está (não a área).
   ============================================================================= */

/* ---------- 1. Áreas ---------- */
CREATE TABLE dbo.PF_Area (
    AreaId      INT IDENTITY(1,1) CONSTRAINT PK_PF_Area PRIMARY KEY,
    Codigo      VARCHAR(20)   NOT NULL CONSTRAINT UQ_PF_Area_Codigo UNIQUE,
    Nome        NVARCHAR(100) NOT NULL,
    Tipo        VARCHAR(10)   NOT NULL CONSTRAINT DF_PF_Area_Tipo DEFAULT 'INTERNA',
    Ordem       INT           NOT NULL CONSTRAINT DF_PF_Area_Ordem DEFAULT 0,
    Ativo       BIT           NOT NULL CONSTRAINT DF_PF_Area_Ativo DEFAULT 1,
    SysIni      DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    SysFim      DATETIME2 GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME (SysIni, SysFim),
    CONSTRAINT CK_PF_Area_Tipo CHECK (Tipo IN ('FORNECEDOR','INTERNA'))
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.PF_AreaHist));

-- Só existe uma "área" fornecedor
CREATE UNIQUE INDEX UX_PF_Area_UnicoFornecedor ON dbo.PF_Area (Tipo) WHERE Tipo = 'FORNECEDOR';

INSERT dbo.PF_Area (Codigo, Nome, Tipo, Ordem) VALUES ('FORN', N'Fornecedor', 'FORNECEDOR', 0);

/* ---------- 2. Perfil e vínculo do usuário Cosmos ---------- */
CREATE TABLE dbo.PF_PerfilPlataforma (
    UsuarioCosmosId INT         NOT NULL CONSTRAINT PK_PF_PerfilPlataforma PRIMARY KEY,
    Perfil          VARCHAR(10) NOT NULL,
    Ativo           BIT         NOT NULL CONSTRAINT DF_PF_Perfil_Ativo DEFAULT 1,
    CONSTRAINT CK_PF_Perfil CHECK (Perfil IN ('FORNECEDOR','AREA','ADMIN'))
);

-- Um usuário pode estar em várias áreas; o fornecedor é vinculado à área FORN.
CREATE TABLE dbo.PF_UsuarioArea (
    UsuarioCosmosId INT NOT NULL,
    AreaId          INT NOT NULL,
    Ativo           BIT NOT NULL CONSTRAINT DF_PF_UsuarioArea_Ativo DEFAULT 1,
    CONSTRAINT PK_PF_UsuarioArea PRIMARY KEY (UsuarioCosmosId, AreaId),
    CONSTRAINT FK_PF_UsuarioArea_Perfil FOREIGN KEY (UsuarioCosmosId) REFERENCES dbo.PF_PerfilPlataforma (UsuarioCosmosId),
    CONSTRAINT FK_PF_UsuarioArea_Area   FOREIGN KEY (AreaId)          REFERENCES dbo.PF_Area (AreaId)
);

/* ---------- 3. Campos ----------
   Tipos simples (compatíveis com ERP):
     TEXTO_CURTO  1..255 caracteres (tamanho informado no cadastro)
     TEXTO_LONGO  5000 caracteres (tamanho fixo)
     NUMERO       decimal(18,4), com CasasDecimais 0..4 definidas no cadastro
     LISTA        valor escolhido entre PF_CampoListaValor (até 255 caracteres)
   Campo com valor gravado é imutável (trigger). Para mudar: cancelar (Ativo = 0)
   e criar um campo novo, que vale para as próximas fichas. */
CREATE TABLE dbo.PF_Campo (
    CampoId             INT IDENTITY(1,1) CONSTRAINT PK_PF_Campo PRIMARY KEY,
    -- Unicidade pela descrição, sem diferenciar maiúscula/minúscula nem acento.
    -- Vale entre pré-ficha E ficha completa: se existe na pré-ficha, ninguém recria.
    Descricao             NVARCHAR(200) COLLATE Latin1_General_100_CI_AI NOT NULL,
    Tipo                  VARCHAR(12)   NOT NULL,
    Tamanho               INT           NULL,
    CasasDecimais         TINYINT       NULL,
    Etapa                 VARCHAR(15)   NOT NULL,
    AreaCriadoraId        INT           NOT NULL,
    Ordem                 INT           NOT NULL CONSTRAINT DF_PF_Campo_Ordem DEFAULT 0,
    VisivelFornecedor     BIT           NOT NULL CONSTRAINT DF_PF_Campo_VisForn DEFAULT 0,
    AparecerWorkflowFinal BIT           NOT NULL CONSTRAINT DF_PF_Campo_WF DEFAULT 1,
    Ativo                 BIT           NOT NULL CONSTRAINT DF_PF_Campo_Ativo DEFAULT 1,
    SysIni      DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    SysFim      DATETIME2 GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME (SysIni, SysFim),
    CONSTRAINT UQ_PF_Campo_Descricao UNIQUE (Descricao),
    CONSTRAINT FK_PF_Campo_Area FOREIGN KEY (AreaCriadoraId) REFERENCES dbo.PF_Area (AreaId),
    CONSTRAINT CK_PF_Campo_Tipo  CHECK (Tipo  IN ('TEXTO_CURTO','TEXTO_LONGO','NUMERO','LISTA')),
    CONSTRAINT CK_PF_Campo_Etapa CHECK (Etapa IN ('PRE_FICHA','FICHA_COMPLETA')),
    CONSTRAINT CK_PF_Campo_Tamanho CHECK (
           (Tipo = 'TEXTO_CURTO' AND Tamanho BETWEEN 1 AND 255)
        OR (Tipo = 'TEXTO_LONGO' AND Tamanho = 5000)
        OR (Tipo IN ('NUMERO','LISTA') AND Tamanho IS NULL)),
    CONSTRAINT CK_PF_Campo_Casas CHECK (
           (Tipo = 'NUMERO' AND CasasDecimais BETWEEN 0 AND 4)
        OR (Tipo <> 'NUMERO' AND CasasDecimais IS NULL))
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.PF_CampoHist));

-- Valores possíveis quando Tipo = 'LISTA' (a grid da tela do construtor)
CREATE TABLE dbo.PF_CampoListaValor (
    CampoListaValorId INT IDENTITY(1,1) CONSTRAINT PK_PF_CampoListaValor PRIMARY KEY,
    CampoId           INT           NOT NULL,
    Valor             NVARCHAR(255) NOT NULL,
    Ordem             INT           NOT NULL CONSTRAINT DF_PF_CLV_Ordem DEFAULT 0,
    Ativo             BIT           NOT NULL CONSTRAINT DF_PF_CLV_Ativo DEFAULT 1,
    CONSTRAINT FK_PF_CLV_Campo FOREIGN KEY (CampoId) REFERENCES dbo.PF_Campo (CampoId),
    CONSTRAINT UQ_PF_CLV UNIQUE (CampoId, Valor)
);

/* ---------- 4. Matriz campo x área (propriedades por participante) ---------- */
CREATE TABLE dbo.PF_CampoArea (
    CampoId     INT NOT NULL,
    AreaId      INT NOT NULL,
    Obrigatorio BIT NOT NULL CONSTRAINT DF_PF_CA_Obrig DEFAULT 0,
    Editavel    BIT NOT NULL CONSTRAINT DF_PF_CA_Edit  DEFAULT 0,
    SysIni      DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    SysFim      DATETIME2 GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME (SysIni, SysFim),
    CONSTRAINT PK_PF_CampoArea PRIMARY KEY (CampoId, AreaId),
    CONSTRAINT FK_PF_CA_Campo FOREIGN KEY (CampoId) REFERENCES dbo.PF_Campo (CampoId),
    CONSTRAINT FK_PF_CA_Area  FOREIGN KEY (AreaId)  REFERENCES dbo.PF_Area (AreaId),
    -- Obrigar quem não pode editar não faz sentido
    CONSTRAINT CK_PF_CA_ObrigEdit CHECK (Obrigatorio = 0 OR Editavel = 1)
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.PF_CampoAreaHist));

/* ---------- 5. Pré-ficha / ficha: status, aprovação e valores ----------
   Status = fase da ficha:
     PRE_FICHA_PREENCHIMENTO -> PRE_FICHA_APROVACAO -> FICHA_COMPLETA -> CONCLUIDA
     (REJEITADA e CANCELADA encerram a ficha)
   Na ficha completa todas as áreas atuam em paralelo. */
CREATE TABLE dbo.PF_PreFicha (
    PreFichaCodigo      INT IDENTITY(1,1) CONSTRAINT PK_PF_PreFicha PRIMARY KEY,
    FornecedorUsuarioId INT         NOT NULL,
    Status              VARCHAR(25) NOT NULL CONSTRAINT DF_PF_PreFicha_Status DEFAULT 'PRE_FICHA_PREENCHIMENTO',
    CriadaEm            DATETIME2   NOT NULL CONSTRAINT DF_PF_PreFicha_Criada DEFAULT SYSUTCDATETIME(),
    AtualizadaEm        DATETIME2   NOT NULL CONSTRAINT DF_PF_PreFicha_Atual  DEFAULT SYSUTCDATETIME(),
    CONSTRAINT CK_PF_PreFicha_Status CHECK (Status IN
        ('PRE_FICHA_PREENCHIMENTO','PRE_FICHA_APROVACAO','FICHA_COMPLETA','CONCLUIDA','REJEITADA','CANCELADA'))
);

/* Áreas que aprovam a pré-ficha, escolhidas no momento da aprovação.
   Ordem igual  = aprovação simultânea; Ordem diferente = sequencial (menor primeiro).
   Ex.: Compras(1), GC(1), Fiscal(2) -> Compras e GC juntas, depois Fiscal. */
CREATE TABLE dbo.PF_PreFichaAprovacao (
    PreFichaAprovacaoId INT IDENTITY(1,1) CONSTRAINT PK_PF_PreFichaAprovacao PRIMARY KEY,
    PreFichaCodigo      INT           NOT NULL,
    AreaId              INT           NOT NULL,
    Ordem               INT           NOT NULL,
    Situacao            VARCHAR(10)   NOT NULL CONSTRAINT DF_PF_PFA_Situacao DEFAULT 'PENDENTE',
    DecididoPor         INT           NULL,
    DecididoEm          DATETIME2     NULL,
    Motivo              NVARCHAR(500) NULL,
    CONSTRAINT FK_PF_PFA_Ficha FOREIGN KEY (PreFichaCodigo) REFERENCES dbo.PF_PreFicha (PreFichaCodigo),
    CONSTRAINT FK_PF_PFA_Area  FOREIGN KEY (AreaId)         REFERENCES dbo.PF_Area (AreaId),
    CONSTRAINT UQ_PF_PFA UNIQUE (PreFichaCodigo, AreaId),
    CONSTRAINT CK_PF_PFA_Situacao CHECK (Situacao IN ('PENDENTE','APROVADO','REJEITADO'))
);

/* Valores tipados: texto OU número, nunca os dois. Sem conversão implícita. */
CREATE TABLE dbo.PF_PreFichaValor (
    PreFichaCodigo  INT            NOT NULL,
    CampoId         INT            NOT NULL,
    ValorTexto      NVARCHAR(MAX)  NULL,
    ValorNumero     DECIMAL(18,4)  NULL,
    AlteradoPor     INT            NOT NULL,
    AlteradoEm      DATETIME2      NOT NULL CONSTRAINT DF_PF_PFV_Em DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_PF_PreFichaValor PRIMARY KEY (PreFichaCodigo, CampoId),
    CONSTRAINT FK_PF_PFV_Ficha FOREIGN KEY (PreFichaCodigo) REFERENCES dbo.PF_PreFicha (PreFichaCodigo),
    CONSTRAINT FK_PF_PFV_Campo FOREIGN KEY (CampoId)        REFERENCES dbo.PF_Campo (CampoId),
    CONSTRAINT CK_PF_PFV_UmTipo CHECK (ValorTexto IS NULL OR ValorNumero IS NULL),
    CONSTRAINT CK_PF_PFV_Tamanho CHECK (ValorTexto IS NULL OR LEN(ValorTexto) <= 5000)
);

-- Log de cada alteração de valor
CREATE TABLE dbo.PF_PreFichaValorLog (
    PreFichaValorLogId BIGINT IDENTITY(1,1) CONSTRAINT PK_PF_PreFichaValorLog PRIMARY KEY,
    PreFichaCodigo     INT           NOT NULL,
    CampoId            INT           NOT NULL,
    ValorAnterior      NVARCHAR(MAX) NULL,
    ValorNovo          NVARCHAR(MAX) NULL,
    UsuarioCosmosId    INT           NOT NULL,
    Em                 DATETIME2     NOT NULL CONSTRAINT DF_PF_PFVL_Em DEFAULT SYSUTCDATETIME()
);
CREATE INDEX IX_PF_PFVL_Ficha ON dbo.PF_PreFichaValorLog (PreFichaCodigo, CampoId);

/* ---------- 6. Integrações (ERP, e-commerce, ...) ----------
   Etapa do construtor: para cada integração, quais campos são enviados e com que
   nome no destino. O envio acontece após a aprovação (ficha CONCLUIDA). */
CREATE TABLE dbo.PF_Integracao (
    IntegracaoId INT IDENTITY(1,1) CONSTRAINT PK_PF_Integracao PRIMARY KEY,
    Codigo       VARCHAR(20)   NOT NULL CONSTRAINT UQ_PF_Integracao_Codigo UNIQUE,
    Nome         NVARCHAR(100) NOT NULL,
    Ativo        BIT           NOT NULL CONSTRAINT DF_PF_Integracao_Ativo DEFAULT 1
);

CREATE TABLE dbo.PF_IntegracaoCampo (
    IntegracaoId INT           NOT NULL,
    CampoId      INT           NOT NULL,
    NomeDestino  NVARCHAR(100) NOT NULL,   -- nome do campo no sistema destino
    CONSTRAINT PK_PF_IntegracaoCampo PRIMARY KEY (IntegracaoId, CampoId),
    CONSTRAINT FK_PF_IC_Integracao FOREIGN KEY (IntegracaoId) REFERENCES dbo.PF_Integracao (IntegracaoId),
    CONSTRAINT FK_PF_IC_Campo      FOREIGN KEY (CampoId)      REFERENCES dbo.PF_Campo (CampoId),
    CONSTRAINT UQ_PF_IC_Destino UNIQUE (IntegracaoId, NomeDestino)
);

-- Controle: um registro por ficha x integração
CREATE TABLE dbo.PF_IntegracaoEnvio (
    EnvioId             INT IDENTITY(1,1) CONSTRAINT PK_PF_IntegracaoEnvio PRIMARY KEY,
    PreFichaCodigo      INT         NOT NULL,
    IntegracaoId        INT         NOT NULL,
    Situacao            VARCHAR(10) NOT NULL CONSTRAINT DF_PF_IE_Situacao DEFAULT 'PENDENTE',
    Tentativas          INT         NOT NULL CONSTRAINT DF_PF_IE_Tent DEFAULT 0,
    CriadoEm            DATETIME2   NOT NULL CONSTRAINT DF_PF_IE_Criado DEFAULT SYSUTCDATETIME(),
    UltimaTentativaEm   DATETIME2   NULL,
    CONSTRAINT FK_PF_IE_Ficha      FOREIGN KEY (PreFichaCodigo) REFERENCES dbo.PF_PreFicha (PreFichaCodigo),
    CONSTRAINT FK_PF_IE_Integracao FOREIGN KEY (IntegracaoId)   REFERENCES dbo.PF_Integracao (IntegracaoId),
    CONSTRAINT UQ_PF_IE UNIQUE (PreFichaCodigo, IntegracaoId),
    CONSTRAINT CK_PF_IE_Situacao CHECK (Situacao IN ('PENDENTE','ENVIADO','ERRO'))
);

-- Log de cada tentativa: o que foi enviado e o que voltou
CREATE TABLE dbo.PF_IntegracaoEnvioLog (
    EnvioLogId       BIGINT IDENTITY(1,1) CONSTRAINT PK_PF_IntegracaoEnvioLog PRIMARY KEY,
    EnvioId          INT           NOT NULL,
    Tentativa        INT           NOT NULL,
    PayloadEnviado   NVARCHAR(MAX) NULL,
    RespostaRecebida NVARCHAR(MAX) NULL,
    CodigoRetorno    VARCHAR(20)   NULL,
    Sucesso          BIT           NOT NULL,
    Mensagem         NVARCHAR(500) NULL,
    Em               DATETIME2     NOT NULL CONSTRAINT DF_PF_IEL_Em DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_PF_IEL_Envio FOREIGN KEY (EnvioId) REFERENCES dbo.PF_IntegracaoEnvio (EnvioId)
);
GO

/* =============================================================================
   Imutabilidade: campo com valor gravado não muda; valor de lista em uso não muda
   ============================================================================= */
CREATE TRIGGER dbo.PF_trg_Campo_Imutavel ON dbo.PF_Campo AFTER UPDATE AS
BEGIN
    IF EXISTS (
        SELECT 1 FROM inserted i JOIN deleted d ON d.CampoId = i.CampoId
        WHERE (i.Descricao <> d.Descricao OR i.Tipo <> d.Tipo
               OR ISNULL(i.Tamanho, -1) <> ISNULL(d.Tamanho, -1)
               OR ISNULL(i.CasasDecimais, -1) <> ISNULL(d.CasasDecimais, -1)
               OR i.Etapa <> d.Etapa)
          AND EXISTS (SELECT 1 FROM dbo.PF_PreFichaValor v WHERE v.CampoId = i.CampoId))
        THROW 50020, 'Campo com valor gravado não pode ser alterado. Cancele o campo (Ativo = 0) e crie um novo.', 1;
END;
GO

CREATE TRIGGER dbo.PF_trg_CampoListaValor_Imutavel ON dbo.PF_CampoListaValor AFTER UPDATE, DELETE AS
BEGIN
    IF EXISTS (
        SELECT 1 FROM deleted d
        LEFT JOIN inserted i ON i.CampoListaValorId = d.CampoListaValorId
        WHERE (i.CampoListaValorId IS NULL OR i.Valor <> d.Valor OR i.CampoId <> d.CampoId)
          AND EXISTS (SELECT 1 FROM dbo.PF_PreFichaValor v WHERE v.CampoId = d.CampoId AND v.ValorTexto = d.Valor))
        THROW 50021, 'Valor de lista em uso não pode ser alterado ou excluído. Desative-o (Ativo = 0).', 1;
END;
GO

/* =============================================================================
   CUSTOM VIEW 1 - Campos que o usuário enxerga e o que pode fazer em cada um
   Parâmetros: @UsuarioCosmosId (vem da sessão, ver premissas),
               @Etapa ('PRE_FICHA' | 'FICHA_COMPLETA' | NULL = ambas),
               @SomenteAtivos (1 para montar ficha nova; 0 para exibir ficha existente)
   - Áreas internas e ADMIN veem todos os campos.
   - Fornecedor vê só campos com VisivelFornecedor = 1 ou que ele preenche (matriz FORN).
   - Campo cancelado (Ativo = 0) nunca é editável.
   - Editavel/Obrigatorio vêm da(s) área(s) do usuário (MAX entre as áreas).
   ============================================================================= */
CREATE FUNCTION dbo.PF_fn_PerfilUsuario (@UsuarioCosmosId INT)
RETURNS VARCHAR(10) AS
BEGIN
    RETURN (SELECT Perfil FROM dbo.PF_PerfilPlataforma WHERE UsuarioCosmosId = @UsuarioCosmosId AND Ativo = 1);
END;
GO

CREATE FUNCTION dbo.PF_fn_CamposUsuario (@UsuarioCosmosId INT, @Etapa VARCHAR(15), @SomenteAtivos BIT)
RETURNS TABLE AS RETURN
(
    SELECT c.CampoId, c.Descricao, c.Tipo, c.Tamanho, c.CasasDecimais, c.Etapa, c.Ordem, c.Ativo,
           CAST(CASE WHEN c.Ativo = 0 THEN 0
                     WHEN p.Perfil = 'ADMIN' THEN 1
                     ELSE ISNULL(x.Editavel, 0) END AS BIT) AS Editavel,
           CAST(CASE WHEN c.Ativo = 0 THEN 0 ELSE ISNULL(x.Obrigatorio, 0) END AS BIT) AS Obrigatorio
    FROM dbo.PF_Campo c
    CROSS APPLY (SELECT dbo.PF_fn_PerfilUsuario(@UsuarioCosmosId) AS Perfil) p
    OUTER APPLY (
        SELECT MAX(CAST(ca.Editavel AS INT))    AS Editavel,
               MAX(CAST(ca.Obrigatorio AS INT)) AS Obrigatorio
        FROM dbo.PF_CampoArea ca
        WHERE ca.CampoId = c.CampoId
          AND (p.Perfil = 'ADMIN'
               OR ca.AreaId IN (SELECT ua.AreaId FROM dbo.PF_UsuarioArea ua
                                WHERE ua.UsuarioCosmosId = @UsuarioCosmosId AND ua.Ativo = 1))
    ) x
    WHERE p.Perfil IS NOT NULL
      AND (@Etapa IS NULL OR c.Etapa = @Etapa)
      AND (@SomenteAtivos = 0 OR c.Ativo = 1)
      AND (p.Perfil <> 'FORNECEDOR'
           OR c.VisivelFornecedor = 1
           OR EXISTS (SELECT 1 FROM dbo.PF_CampoArea cf
                      JOIN dbo.PF_Area af ON af.AreaId = cf.AreaId AND af.Tipo = 'FORNECEDOR'
                      WHERE cf.CampoId = c.CampoId))
);
GO

/* =============================================================================
   CUSTOM VIEW 2 - Campos + valores já salvos da ficha
   - Fornecedor só acessa a própria ficha.
   - Campo cancelado só aparece se a ficha tem valor nele (somente leitura).
   ============================================================================= */
CREATE FUNCTION dbo.PF_fn_ValoresPreFicha (@PreFichaCodigo INT, @UsuarioCosmosId INT, @Etapa VARCHAR(15))
RETURNS TABLE AS RETURN
(
    SELECT cu.CampoId, cu.Descricao, cu.Tipo, cu.Tamanho, cu.CasasDecimais, cu.Etapa, cu.Ordem,
           cu.Ativo, cu.Editavel, cu.Obrigatorio,
           v.ValorTexto, v.ValorNumero, v.AlteradoPor, v.AlteradoEm
    FROM dbo.PF_fn_CamposUsuario(@UsuarioCosmosId, @Etapa, 0) cu
    LEFT JOIN dbo.PF_PreFichaValor v ON v.PreFichaCodigo = @PreFichaCodigo AND v.CampoId = cu.CampoId
    WHERE (cu.Ativo = 1 OR v.CampoId IS NOT NULL)
      AND EXISTS (SELECT 1 FROM dbo.PF_PreFicha f
                  WHERE f.PreFichaCodigo = @PreFichaCodigo
                    AND (dbo.PF_fn_PerfilUsuario(@UsuarioCosmosId) <> 'FORNECEDOR'
                         OR f.FornecedorUsuarioId = @UsuarioCosmosId))
);
GO

/* Aprovações que podem ser decididas agora (grupo pendente de menor Ordem) */
CREATE FUNCTION dbo.PF_fn_AprovacoesLiberadas (@PreFichaCodigo INT)
RETURNS TABLE AS RETURN
(
    SELECT a.PreFichaAprovacaoId, a.AreaId, a.Ordem
    FROM dbo.PF_PreFichaAprovacao a
    WHERE a.PreFichaCodigo = @PreFichaCodigo
      AND a.Situacao = 'PENDENTE'
      AND a.Ordem = (SELECT MIN(b.Ordem) FROM dbo.PF_PreFichaAprovacao b
                     WHERE b.PreFichaCodigo = @PreFichaCodigo AND b.Situacao = 'PENDENTE')
);
GO

/* Payload de uma integração: só os campos marcados, com o nome do destino */
CREATE FUNCTION dbo.PF_fn_PayloadIntegracao (@PreFichaCodigo INT, @IntegracaoId INT)
RETURNS TABLE AS RETURN
(
    SELECT ic.NomeDestino, c.CampoId, c.Tipo, v.ValorTexto, v.ValorNumero
    FROM dbo.PF_IntegracaoCampo ic
    JOIN dbo.PF_Campo c ON c.CampoId = ic.CampoId
    LEFT JOIN dbo.PF_PreFichaValor v ON v.PreFichaCodigo = @PreFichaCodigo AND v.CampoId = ic.CampoId
    WHERE ic.IntegracaoId = @IntegracaoId
);
GO

/* =============================================================================
   CUSTOM ACTION - Persistência dos valores
   @ValoresJson: [{"campoId":1,"valor":"texto"}, ...]  (número com ponto decimal)
   @ValidarObrigatorios = 1 ao concluir a fase (valida o que falta preencher)
   Regras:
     - ficha encerrada (CONCLUIDA/REJEITADA/CANCELADA) não aceita alteração
     - fornecedor não altera durante a aprovação da pré-ficha
     - campo da ficha completa só é aceito na fase FICHA_COMPLETA
     - campo precisa estar acessível, ativo e editável para o usuário
     - texto: tamanho do campo e sem caracteres de controle (seguro para ERP)
     - número: ponto decimal, até CasasDecimais, dentro de decimal(18,4)
     - lista: valor ativo da lista
     - grava só o que mudou e registra em PF_PreFichaValorLog
   Tudo ou nada: qualquer erro cancela a gravação.
   ============================================================================= */
CREATE PROCEDURE dbo.PF_usp_SalvarValoresPreFicha
    @PreFichaCodigo      INT,
    @UsuarioCosmosId     INT,
    @ValoresJson         NVARCHAR(MAX),
    @ValidarObrigatorios BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status VARCHAR(25), @Fornecedor INT, @Perfil VARCHAR(10) = dbo.PF_fn_PerfilUsuario(@UsuarioCosmosId);
    SELECT @Status = Status, @Fornecedor = FornecedorUsuarioId FROM dbo.PF_PreFicha WHERE PreFichaCodigo = @PreFichaCodigo;

    IF @Status IS NULL THROW 50001, 'Ficha não encontrada.', 1;
    IF @Perfil IS NULL THROW 50002, 'Usuário sem perfil na plataforma.', 1;
    IF @Perfil = 'FORNECEDOR' AND @Fornecedor <> @UsuarioCosmosId
        THROW 50003, 'Fornecedor só pode alterar a própria ficha.', 1;
    IF @Status IN ('CONCLUIDA','REJEITADA','CANCELADA')
        THROW 50004, 'Ficha encerrada não aceita alterações.', 1;
    IF @Perfil = 'FORNECEDOR' AND @Status = 'PRE_FICHA_APROVACAO'
        THROW 50005, 'Pré-ficha em aprovação: o fornecedor não pode alterar.', 1;

    -- Valor vazio = NULL
    SELECT CampoId, NULLIF(LTRIM(RTRIM(Valor)), N'') AS Valor
    INTO #In
    FROM OPENJSON(@ValoresJson) WITH (CampoId INT '$.campoId', Valor NVARCHAR(MAX) '$.valor');

    CREATE TABLE #Erros (Msg NVARCHAR(400));

    INSERT #Erros
    SELECT CONCAT(N'Campo ', CampoId, N' informado mais de uma vez.')
    FROM #In GROUP BY CampoId HAVING COUNT(*) > 1;

    SELECT i.CampoId, i.Valor, cu.Descricao, cu.Tipo, cu.Tamanho, cu.CasasDecimais, cu.Etapa,
           cu.Ativo, cu.Editavel,
           CASE WHEN cu.Tipo = 'NUMERO' THEN TRY_CAST(i.Valor AS DECIMAL(28,10)) END AS NumeroLargo
    INTO #V
    FROM #In i
    LEFT JOIN dbo.PF_fn_CamposUsuario(@UsuarioCosmosId, NULL, 0) cu ON cu.CampoId = i.CampoId;

    INSERT #Erros SELECT CONCAT(N'Campo ', CampoId, N' inexistente ou sem acesso.') FROM #V WHERE Descricao IS NULL;
    INSERT #Erros SELECT CONCAT(Descricao, N': campo cancelado.') FROM #V WHERE Ativo = 0;
    INSERT #Erros SELECT CONCAT(Descricao, N': sem permissão de edição.') FROM #V WHERE Ativo = 1 AND Editavel = 0;
    INSERT #Erros SELECT CONCAT(Descricao, N': campo da ficha completa não pode ser preenchido antes dessa fase.')
    FROM #V WHERE Etapa = 'FICHA_COMPLETA' AND @Status <> 'FICHA_COMPLETA';

    -- Texto: tamanho e caracteres de controle (curto: nenhum; longo: permite tab, CR e LF)
    DECLARE @RxCurto NVARCHAR(40) = N'%[' + NCHAR(1) + N'-' + NCHAR(31) + N']%';
    DECLARE @RxLongo NVARCHAR(40) = N'%[' + NCHAR(1) + N'-' + NCHAR(8) + NCHAR(11) + NCHAR(12) + NCHAR(14) + N'-' + NCHAR(31) + N']%';

    INSERT #Erros SELECT CONCAT(Descricao, N': tamanho máximo de ', Tamanho, N' caracteres excedido.')
    FROM #V WHERE Tipo IN ('TEXTO_CURTO','TEXTO_LONGO') AND LEN(Valor) > Tamanho;

    INSERT #Erros SELECT CONCAT(Descricao, N': contém caracteres não permitidos.')
    FROM #V WHERE Valor IS NOT NULL AND (
           (Tipo = 'TEXTO_CURTO' AND PATINDEX(@RxCurto, Valor COLLATE Latin1_General_BIN2) > 0)
        OR (Tipo IN ('TEXTO_LONGO','LISTA') AND PATINDEX(@RxLongo, Valor COLLATE Latin1_General_BIN2) > 0));

    -- Número: ponto decimal, casas permitidas e limite de decimal(18,4)
    INSERT #Erros SELECT CONCAT(Descricao, N': número inválido (use ponto como separador decimal).')
    FROM #V WHERE Tipo = 'NUMERO' AND Valor IS NOT NULL AND NumeroLargo IS NULL;

    INSERT #Erros SELECT CONCAT(Descricao, N': mais casas decimais que o permitido (', CasasDecimais, N').')
    FROM #V WHERE Tipo = 'NUMERO' AND NumeroLargo IS NOT NULL AND ROUND(NumeroLargo, CasasDecimais) <> NumeroLargo;

    INSERT #Erros SELECT CONCAT(Descricao, N': número fora do limite permitido.')
    FROM #V WHERE Tipo = 'NUMERO' AND NumeroLargo IS NOT NULL AND ABS(NumeroLargo) >= 100000000000000;

    -- Lista
    INSERT #Erros SELECT CONCAT(v.Descricao, N': valor não consta na lista.')
    FROM #V v WHERE v.Tipo = 'LISTA' AND v.Valor IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM dbo.PF_CampoListaValor l
                      WHERE l.CampoId = v.CampoId AND l.Ativo = 1 AND l.Valor = v.Valor);

    IF @ValidarObrigatorios = 1
        INSERT #Erros
        SELECT CONCAT(cu.Descricao, N': preenchimento obrigatório.')
        FROM dbo.PF_fn_CamposUsuario(@UsuarioCosmosId, NULL, 1) cu
        LEFT JOIN #In i ON i.CampoId = cu.CampoId
        LEFT JOIN dbo.PF_PreFichaValor pv ON pv.PreFichaCodigo = @PreFichaCodigo AND pv.CampoId = cu.CampoId
        WHERE cu.Obrigatorio = 1 AND cu.Editavel = 1
          AND (cu.Etapa = 'PRE_FICHA' OR @Status = 'FICHA_COMPLETA')
          AND (CASE WHEN i.CampoId IS NOT NULL THEN CASE WHEN i.Valor IS NULL THEN 0 ELSE 1 END
                    WHEN pv.ValorTexto IS NOT NULL OR pv.ValorNumero IS NOT NULL THEN 1
                    ELSE 0 END) = 0;

    IF EXISTS (SELECT 1 FROM #Erros)
    BEGIN
        DECLARE @Msg NVARCHAR(MAX) = (SELECT STRING_AGG(Msg, N' | ') FROM #Erros);
        THROW 50010, @Msg, 1;
    END

    BEGIN TRAN;

    MERGE dbo.PF_PreFichaValor AS t
    USING (SELECT CampoId,
                  CASE WHEN Tipo <> 'NUMERO' THEN Valor END                        AS ValorTexto,
                  CASE WHEN Tipo = 'NUMERO' THEN CAST(NumeroLargo AS DECIMAL(18,4)) END AS ValorNumero
           FROM #V) AS s
      ON t.PreFichaCodigo = @PreFichaCodigo AND t.CampoId = s.CampoId
    WHEN MATCHED AND EXISTS (SELECT t.ValorTexto, t.ValorNumero EXCEPT SELECT s.ValorTexto, s.ValorNumero) THEN
        UPDATE SET ValorTexto = s.ValorTexto, ValorNumero = s.ValorNumero,
                   AlteradoPor = @UsuarioCosmosId, AlteradoEm = SYSUTCDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (PreFichaCodigo, CampoId, ValorTexto, ValorNumero, AlteradoPor)
        VALUES (@PreFichaCodigo, s.CampoId, s.ValorTexto, s.ValorNumero, @UsuarioCosmosId)
    OUTPUT @PreFichaCodigo, inserted.CampoId,
           COALESCE(deleted.ValorTexto,  CONVERT(NVARCHAR(40), deleted.ValorNumero)),
           COALESCE(inserted.ValorTexto, CONVERT(NVARCHAR(40), inserted.ValorNumero)),
           @UsuarioCosmosId
        INTO dbo.PF_PreFichaValorLog (PreFichaCodigo, CampoId, ValorAnterior, ValorNovo, UsuarioCosmosId);

    UPDATE dbo.PF_PreFicha SET AtualizadaEm = SYSUTCDATETIME() WHERE PreFichaCodigo = @PreFichaCodigo;

    COMMIT;
END;
GO

/* =============================================================================
   Enfileira o envio às integrações ativas (chamar quando a ficha virar CONCLUIDA).
   Só cria o controle (PENDENTE); o envio e o log de tentativa ficam no processo de
   integração (TODO).
   ============================================================================= */
CREATE PROCEDURE dbo.PF_usp_EnfileirarIntegracoes
    @PreFichaCodigo INT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.PF_PreFicha WHERE PreFichaCodigo = @PreFichaCodigo AND Status = 'CONCLUIDA')
        THROW 50030, 'Só é possível enfileirar integrações de ficha concluída.', 1;

    INSERT dbo.PF_IntegracaoEnvio (PreFichaCodigo, IntegracaoId)
    SELECT @PreFichaCodigo, i.IntegracaoId
    FROM dbo.PF_Integracao i
    WHERE i.Ativo = 1
      AND EXISTS (SELECT 1 FROM dbo.PF_IntegracaoCampo ic WHERE ic.IntegracaoId = i.IntegracaoId)
      AND NOT EXISTS (SELECT 1 FROM dbo.PF_IntegracaoEnvio e
                      WHERE e.PreFichaCodigo = @PreFichaCodigo AND e.IntegracaoId = i.IntegracaoId);
END;
GO

/* =============================================================================
   TODO (fora do desenho atual)
   - Skill + MCP Cosmos Pro para criar tabelas, formulários e customs PF_.
   - Resolver o usuário logado pela sessão/token do Cosmos (confirmar suporte).
   - Custom actions de workflow: enviar para aprovação (gravar PF_PreFichaAprovacao),
     aprovar/rejeitar por área, avançar Status, concluir.
   - Processo de envio das integrações: montar payload (PF_fn_PayloadIntegracao),
     enviar, gravar PF_IntegracaoEnvioLog e atualizar PF_IntegracaoEnvio; reenvio.
   - Concorrência de edição (v2).
   - Tipos DATA, IMAGEM, HTML e LOOKUP (Épico 4).
   - Lista de caracteres proibidos configurável por integração/ERP.
   - Regras entre campos (Épico 5) e carência pós-rejeição (Épico 6).
   - Notificações (e-mail/alertas) do fornecedor.
   - Decidir se campo novo aparece em fichas já abertas.
   - Telas do construtor: áreas, campos (grid da lista), matriz, vínculo de usuário,
     integrações (campos enviados e nome no destino).
   ============================================================================= */
