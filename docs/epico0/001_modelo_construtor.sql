/* =============================================================================
   Épico 0 - Fundação: modelo do construtor low-code (Cadastro de Produtos)
   Premissas:
     - SQL Server 2016+ (tabelas temporais, OPENJSON, STRING_AGG exige 2017+).
     - Usuários são os do próprio Cosmos; aqui só guardamos o ID (UsuarioCosmosId).
       Se existir tabela de usuários acessível no mesmo banco, trocar por FK real.
     - O fornecedor é tratado como uma "área" do tipo FORNECEDOR, assim a matriz
       campo x área serve para os dois (o que é do fornecedor, o que é obrigatório,
       o que é editável).
     - Pré-ficha e ficha completa são visíveis a todos; só a edição é restrita.
   ============================================================================= */

/* ---------- 1. Áreas ---------- */
CREATE TABLE dbo.Area (
    AreaId      INT IDENTITY(1,1) CONSTRAINT PK_Area PRIMARY KEY,
    Codigo      VARCHAR(20)   NOT NULL CONSTRAINT UQ_Area_Codigo UNIQUE,
    Nome        NVARCHAR(100) NOT NULL,
    Tipo        VARCHAR(10)   NOT NULL CONSTRAINT DF_Area_Tipo DEFAULT 'INTERNA',
    Ordem       INT           NOT NULL CONSTRAINT DF_Area_Ordem DEFAULT 0,
    Ativo       BIT           NOT NULL CONSTRAINT DF_Area_Ativo DEFAULT 1,
    SysIni      DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    SysFim      DATETIME2 GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME (SysIni, SysFim),
    CONSTRAINT CK_Area_Tipo CHECK (Tipo IN ('FORNECEDOR','INTERNA'))
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.AreaHist));

-- Só existe uma "área" fornecedor
CREATE UNIQUE INDEX UX_Area_UnicoFornecedor ON dbo.Area (Tipo) WHERE Tipo = 'FORNECEDOR';

INSERT dbo.Area (Codigo, Nome, Tipo, Ordem) VALUES ('FORN', N'Fornecedor', 'FORNECEDOR', 0);

/* ---------- 2. Perfil e vínculo do usuário Cosmos ---------- */
CREATE TABLE dbo.PerfilPlataforma (
    UsuarioCosmosId INT         NOT NULL CONSTRAINT PK_PerfilPlataforma PRIMARY KEY,
    Perfil          VARCHAR(10) NOT NULL,
    Ativo           BIT         NOT NULL CONSTRAINT DF_Perfil_Ativo DEFAULT 1,
    CONSTRAINT CK_Perfil CHECK (Perfil IN ('FORNECEDOR','AREA','ADMIN'))
);

-- Um usuário pode estar em várias áreas; o fornecedor é vinculado à área FORN.
CREATE TABLE dbo.UsuarioArea (
    UsuarioCosmosId INT NOT NULL,
    AreaId          INT NOT NULL,
    Ativo           BIT NOT NULL CONSTRAINT DF_UsuarioArea_Ativo DEFAULT 1,
    CONSTRAINT PK_UsuarioArea PRIMARY KEY (UsuarioCosmosId, AreaId),
    CONSTRAINT FK_UsuarioArea_Perfil FOREIGN KEY (UsuarioCosmosId) REFERENCES dbo.PerfilPlataforma (UsuarioCosmosId),
    CONSTRAINT FK_UsuarioArea_Area   FOREIGN KEY (AreaId)          REFERENCES dbo.Area (AreaId)
);

/* ---------- 3. Campos ---------- */
CREATE TABLE dbo.Campo (
    CampoId             INT IDENTITY(1,1) CONSTRAINT PK_Campo PRIMARY KEY,
    -- Unicidade pela descrição, sem diferenciar maiúscula/minúscula nem acento.
    -- Vale entre pré-ficha E ficha completa: se existe na pré-ficha, ninguém recria.
    Descricao           NVARCHAR(200) COLLATE Latin1_General_100_CI_AI NOT NULL,
    Tipo                VARCHAR(10)   NOT NULL,
    Tamanho             INT           NULL,
    Etapa               VARCHAR(15)   NOT NULL,
    AreaCriadoraId      INT           NOT NULL,
    Ordem               INT           NOT NULL CONSTRAINT DF_Campo_Ordem DEFAULT 0,
    EnviaIntegracao     BIT           NOT NULL CONSTRAINT DF_Campo_Integ DEFAULT 0,
    AparecerWorkflowFinal BIT         NOT NULL CONSTRAINT DF_Campo_WF DEFAULT 1,
    Ativo               BIT           NOT NULL CONSTRAINT DF_Campo_Ativo DEFAULT 1,
    SysIni      DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    SysFim      DATETIME2 GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME (SysIni, SysFim),
    CONSTRAINT UQ_Campo_Descricao UNIQUE (Descricao),
    CONSTRAINT FK_Campo_Area FOREIGN KEY (AreaCriadoraId) REFERENCES dbo.Area (AreaId),
    CONSTRAINT CK_Campo_Tipo  CHECK (Tipo  IN ('TEXTO','NUMERO','DATA','BOOLEANO','LISTA','IMAGEM','HTML')),
    CONSTRAINT CK_Campo_Etapa CHECK (Etapa IN ('PRE_FICHA','FICHA_COMPLETA')),
    -- Texto exige tamanho; os demais tipos não usam tamanho
    CONSTRAINT CK_Campo_Tamanho CHECK (
        (Tipo = 'TEXTO' AND Tamanho > 0) OR (Tipo <> 'TEXTO' AND Tamanho IS NULL))
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.CampoHist));

-- Valores possíveis quando Tipo = 'LISTA' (a grid da tela do construtor)
CREATE TABLE dbo.CampoListaValor (
    CampoListaValorId INT IDENTITY(1,1) CONSTRAINT PK_CampoListaValor PRIMARY KEY,
    CampoId           INT           NOT NULL,
    Valor             NVARCHAR(200) NOT NULL,
    Ordem             INT           NOT NULL CONSTRAINT DF_CLV_Ordem DEFAULT 0,
    Ativo             BIT           NOT NULL CONSTRAINT DF_CLV_Ativo DEFAULT 1,
    CONSTRAINT FK_CLV_Campo FOREIGN KEY (CampoId) REFERENCES dbo.Campo (CampoId),
    CONSTRAINT UQ_CLV UNIQUE (CampoId, Valor)
);

/* ---------- 4. Matriz campo x área (propriedades por participante) ---------- */
CREATE TABLE dbo.CampoArea (
    CampoId     INT NOT NULL,
    AreaId      INT NOT NULL,
    Obrigatorio BIT NOT NULL CONSTRAINT DF_CA_Obrig DEFAULT 0,
    Editavel    BIT NOT NULL CONSTRAINT DF_CA_Edit  DEFAULT 0,
    SysIni      DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    SysFim      DATETIME2 GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME (SysIni, SysFim),
    CONSTRAINT PK_CampoArea PRIMARY KEY (CampoId, AreaId),
    CONSTRAINT FK_CA_Campo FOREIGN KEY (CampoId) REFERENCES dbo.Campo (CampoId),
    CONSTRAINT FK_CA_Area  FOREIGN KEY (AreaId)  REFERENCES dbo.Area (AreaId),
    -- Obrigar quem não pode editar não faz sentido
    CONSTRAINT CK_CA_ObrigEdit CHECK (Obrigatorio = 0 OR Editavel = 1)
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.CampoAreaHist));

/* ---------- 5. Ficha e valores ---------- */
CREATE TABLE dbo.Ficha (
    FichaId             INT IDENTITY(1,1) CONSTRAINT PK_Ficha PRIMARY KEY,
    FornecedorUsuarioId INT         NOT NULL,
    Etapa               VARCHAR(15) NOT NULL CONSTRAINT DF_Ficha_Etapa DEFAULT 'PRE_FICHA',
    CriadaEm            DATETIME2   NOT NULL CONSTRAINT DF_Ficha_Criada DEFAULT SYSUTCDATETIME(),
    AtualizadaEm        DATETIME2   NOT NULL CONSTRAINT DF_Ficha_Atual  DEFAULT SYSUTCDATETIME(),
    CONSTRAINT CK_Ficha_Etapa CHECK (Etapa IN ('PRE_FICHA','FICHA_COMPLETA'))
);

CREATE TABLE dbo.FichaValor (
    FichaId         INT            NOT NULL,
    CampoId         INT            NOT NULL,
    Valor           NVARCHAR(MAX)  NULL,
    AlteradoPor     INT            NOT NULL,
    AlteradoEm      DATETIME2      NOT NULL CONSTRAINT DF_FV_Em DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_FichaValor PRIMARY KEY (FichaId, CampoId),
    CONSTRAINT FK_FV_Ficha FOREIGN KEY (FichaId) REFERENCES dbo.Ficha (FichaId),
    CONSTRAINT FK_FV_Campo FOREIGN KEY (CampoId) REFERENCES dbo.Campo (CampoId)
);

-- Log de cada alteração de valor (base do histórico e do espelho final)
CREATE TABLE dbo.FichaValorLog (
    FichaValorLogId BIGINT IDENTITY(1,1) CONSTRAINT PK_FichaValorLog PRIMARY KEY,
    FichaId         INT           NOT NULL,
    CampoId         INT           NOT NULL,
    ValorAnterior   NVARCHAR(MAX) NULL,
    ValorNovo       NVARCHAR(MAX) NULL,
    UsuarioCosmosId INT           NOT NULL,
    Em              DATETIME2     NOT NULL CONSTRAINT DF_FVL_Em DEFAULT SYSUTCDATETIME()
);
CREATE INDEX IX_FVL_Ficha ON dbo.FichaValorLog (FichaId, CampoId);
GO

/* =============================================================================
   CUSTOM VIEW 1 - Campos que o usuário enxerga e o que pode fazer em cada um
   Parâmetros: @UsuarioCosmosId, @Etapa ('PRE_FICHA' | 'FICHA_COMPLETA' | NULL = ambas)
   - Todos veem todos os campos ativos.
   - Editavel/Obrigatorio vêm da(s) área(s) do usuário (MAX entre as áreas).
   - ADMIN edita tudo; Obrigatorio considera qualquer área.
   ============================================================================= */
CREATE FUNCTION dbo.fn_PerfilUsuario (@UsuarioCosmosId INT)
RETURNS VARCHAR(10) AS
BEGIN
    RETURN (SELECT Perfil FROM dbo.PerfilPlataforma WHERE UsuarioCosmosId = @UsuarioCosmosId AND Ativo = 1);
END;
GO

CREATE FUNCTION dbo.fn_CamposUsuario (@UsuarioCosmosId INT, @Etapa VARCHAR(15))
RETURNS TABLE AS RETURN
(
    SELECT c.CampoId, c.Descricao, c.Tipo, c.Tamanho, c.Etapa, c.Ordem,
           CAST(CASE WHEN dbo.fn_PerfilUsuario(@UsuarioCosmosId) = 'ADMIN' THEN 1
                     ELSE ISNULL(x.Editavel, 0) END AS BIT) AS Editavel,
           CAST(ISNULL(x.Obrigatorio, 0) AS BIT)            AS Obrigatorio
    FROM dbo.Campo c
    OUTER APPLY (
        SELECT MAX(CAST(ca.Editavel AS INT))    AS Editavel,
               MAX(CAST(ca.Obrigatorio AS INT)) AS Obrigatorio
        FROM dbo.CampoArea ca
        WHERE ca.CampoId = c.CampoId
          AND (dbo.fn_PerfilUsuario(@UsuarioCosmosId) = 'ADMIN'
               OR ca.AreaId IN (SELECT ua.AreaId FROM dbo.UsuarioArea ua
                                WHERE ua.UsuarioCosmosId = @UsuarioCosmosId AND ua.Ativo = 1))
    ) x
    WHERE c.Ativo = 1
      AND dbo.fn_PerfilUsuario(@UsuarioCosmosId) IS NOT NULL
      AND (@Etapa IS NULL OR c.Etapa = @Etapa)
);
GO

/* =============================================================================
   CUSTOM VIEW 2 - Campos + valores já salvos da ficha
   Fornecedor só acessa a própria ficha.
   ============================================================================= */
CREATE FUNCTION dbo.fn_ValoresFicha (@FichaId INT, @UsuarioCosmosId INT, @Etapa VARCHAR(15))
RETURNS TABLE AS RETURN
(
    SELECT cu.CampoId, cu.Descricao, cu.Tipo, cu.Tamanho, cu.Etapa, cu.Ordem,
           cu.Editavel, cu.Obrigatorio,
           v.Valor, v.AlteradoPor, v.AlteradoEm
    FROM dbo.fn_CamposUsuario(@UsuarioCosmosId, @Etapa) cu
    LEFT JOIN dbo.FichaValor v ON v.FichaId = @FichaId AND v.CampoId = cu.CampoId
    WHERE EXISTS (SELECT 1 FROM dbo.Ficha f
                  WHERE f.FichaId = @FichaId
                    AND (dbo.fn_PerfilUsuario(@UsuarioCosmosId) <> 'FORNECEDOR'
                         OR f.FornecedorUsuarioId = @UsuarioCosmosId))
);
GO

/* =============================================================================
   CUSTOM ACTION - Persistência dos valores
   @ValoresJson: [{"campoId":1,"valor":"texto"}, ...]
   @ValidarObrigatorios = 1 ao concluir a etapa (valida o que falta preencher)
   Regras:
     - campo precisa existir/estar ativo e ser editável para o usuário
     - ficha em PRE_FICHA não aceita campos de FICHA_COMPLETA
     - valida tipo, tamanho e valores de lista
     - grava só o que mudou e registra em FichaValorLog
   Tudo ou nada: qualquer erro cancela a gravação.
   ============================================================================= */
CREATE PROCEDURE dbo.usp_SalvarValoresFicha
    @FichaId             INT,
    @UsuarioCosmosId     INT,
    @ValoresJson         NVARCHAR(MAX),
    @ValidarObrigatorios BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @EtapaFicha VARCHAR(15), @Fornecedor INT;
    SELECT @EtapaFicha = Etapa, @Fornecedor = FornecedorUsuarioId FROM dbo.Ficha WHERE FichaId = @FichaId;

    IF @EtapaFicha IS NULL THROW 50001, 'Ficha não encontrada.', 1;
    IF dbo.fn_PerfilUsuario(@UsuarioCosmosId) IS NULL THROW 50002, 'Usuário sem perfil na plataforma.', 1;
    IF dbo.fn_PerfilUsuario(@UsuarioCosmosId) = 'FORNECEDOR' AND @Fornecedor <> @UsuarioCosmosId
        THROW 50003, 'Fornecedor só pode alterar a própria ficha.', 1;

    SELECT CampoId, Valor
    INTO #In
    FROM OPENJSON(@ValoresJson) WITH (CampoId INT '$.campoId', Valor NVARCHAR(MAX) '$.valor');

    -- Valor vazio = NULL
    UPDATE #In SET Valor = NULL WHERE LTRIM(RTRIM(Valor)) = '';

    CREATE TABLE #Erros (Msg NVARCHAR(400));

    INSERT #Erros
    SELECT CONCAT(N'Campo ', i.CampoId, N' inexistente ou inativo.')
    FROM #In i WHERE NOT EXISTS (SELECT 1 FROM dbo.Campo c WHERE c.CampoId = i.CampoId AND c.Ativo = 1);

    INSERT #Erros
    SELECT CONCAT(cu.Descricao, N': sem permissão de edição.')
    FROM #In i JOIN dbo.fn_CamposUsuario(@UsuarioCosmosId, NULL) cu ON cu.CampoId = i.CampoId
    WHERE cu.Editavel = 0;

    INSERT #Erros
    SELECT CONCAT(cu.Descricao, N': campo da ficha completa não pode ser preenchido na pré-ficha.')
    FROM #In i JOIN dbo.fn_CamposUsuario(@UsuarioCosmosId, NULL) cu ON cu.CampoId = i.CampoId
    WHERE cu.Etapa = 'FICHA_COMPLETA' AND @EtapaFicha = 'PRE_FICHA';

    INSERT #Erros
    SELECT CONCAT(cu.Descricao, N': tamanho máximo de ', cu.Tamanho, N' caracteres excedido.')
    FROM #In i JOIN dbo.fn_CamposUsuario(@UsuarioCosmosId, NULL) cu ON cu.CampoId = i.CampoId
    WHERE cu.Tipo = 'TEXTO' AND LEN(i.Valor) > cu.Tamanho;

    INSERT #Erros
    SELECT CONCAT(cu.Descricao, N': valor inválido para o tipo ', cu.Tipo, N'.')
    FROM #In i JOIN dbo.fn_CamposUsuario(@UsuarioCosmosId, NULL) cu ON cu.CampoId = i.CampoId
    WHERE i.Valor IS NOT NULL AND (
          (cu.Tipo = 'NUMERO'   AND TRY_CAST(i.Valor AS DECIMAL(18,4)) IS NULL)
       OR (cu.Tipo = 'DATA'     AND TRY_CAST(i.Valor AS DATE) IS NULL)
       OR (cu.Tipo = 'BOOLEANO' AND i.Valor NOT IN ('0','1')));

    INSERT #Erros
    SELECT CONCAT(cu.Descricao, N': valor não consta na lista.')
    FROM #In i JOIN dbo.fn_CamposUsuario(@UsuarioCosmosId, NULL) cu ON cu.CampoId = i.CampoId
    WHERE cu.Tipo = 'LISTA' AND i.Valor IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM dbo.CampoListaValor l
                      WHERE l.CampoId = i.CampoId AND l.Ativo = 1 AND l.Valor = i.Valor);

    IF @ValidarObrigatorios = 1
        INSERT #Erros
        SELECT CONCAT(cu.Descricao, N': preenchimento obrigatório.')
        FROM dbo.fn_CamposUsuario(@UsuarioCosmosId, NULL) cu
        LEFT JOIN #In i ON i.CampoId = cu.CampoId
        LEFT JOIN dbo.FichaValor v ON v.FichaId = @FichaId AND v.CampoId = cu.CampoId
        WHERE cu.Obrigatorio = 1 AND cu.Editavel = 1
          AND (@EtapaFicha = 'FICHA_COMPLETA' OR cu.Etapa = 'PRE_FICHA')
          AND COALESCE(CASE WHEN i.CampoId IS NOT NULL THEN i.Valor ELSE v.Valor END, N'') = N'';

    IF EXISTS (SELECT 1 FROM #Erros)
    BEGIN
        DECLARE @Msg NVARCHAR(MAX) = (SELECT STRING_AGG(Msg, N' | ') FROM #Erros);
        THROW 50010, @Msg, 1;
    END

    BEGIN TRAN;

    MERGE dbo.FichaValor AS t
    USING #In AS s ON t.FichaId = @FichaId AND t.CampoId = s.CampoId
    WHEN MATCHED AND ISNULL(t.Valor, N'') <> ISNULL(s.Valor, N'') THEN
        UPDATE SET Valor = s.Valor, AlteradoPor = @UsuarioCosmosId, AlteradoEm = SYSUTCDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (FichaId, CampoId, Valor, AlteradoPor) VALUES (@FichaId, s.CampoId, s.Valor, @UsuarioCosmosId)
    OUTPUT @FichaId, inserted.CampoId, deleted.Valor, inserted.Valor, @UsuarioCosmosId
        INTO dbo.FichaValorLog (FichaId, CampoId, ValorAnterior, ValorNovo, UsuarioCosmosId);

    UPDATE dbo.Ficha SET AtualizadaEm = SYSUTCDATETIME() WHERE FichaId = @FichaId;

    COMMIT;
END;
GO
