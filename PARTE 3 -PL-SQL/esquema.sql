/* =====================================================================
   Reto Técnico - Analista de Desarrollo
   esquema.sql : tablas del sistema actual (base de datos RetoLotes)
   Se entrega como referencia; no es necesario ejecutarlo.
   ===================================================================== */

IF DB_ID('RetoLotes') IS NULL
    CREATE DATABASE RetoLotes;
GO

USE RetoLotes;
GO

IF OBJECT_ID('dbo.Cuota', 'U')      IS NOT NULL DROP TABLE dbo.Cuota;
IF OBJECT_ID('dbo.Separacion', 'U') IS NOT NULL DROP TABLE dbo.Separacion;
IF OBJECT_ID('dbo.Lote', 'U')       IS NOT NULL DROP TABLE dbo.Lote;
IF OBJECT_ID('dbo.Cliente', 'U')    IS NOT NULL DROP TABLE dbo.Cliente;
IF OBJECT_ID('dbo.Asesor', 'U')     IS NOT NULL DROP TABLE dbo.Asesor;
IF OBJECT_ID('dbo.Proyecto', 'U')   IS NOT NULL DROP TABLE dbo.Proyecto;
GO

CREATE TABLE dbo.Proyecto (
    ProyectoId   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Proyecto PRIMARY KEY,
    Nombre       VARCHAR(100)      NOT NULL,
    Ubicacion    VARCHAR(150)      NOT NULL,
    Activo       BIT               NOT NULL CONSTRAINT DF_Proyecto_Activo DEFAULT (1)
);
GO

CREATE TABLE dbo.Asesor (
    AsesorId     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Asesor PRIMARY KEY,
    Nombres      VARCHAR(100)      NOT NULL,
    Email        VARCHAR(150)      NOT NULL,
    Activo       BIT               NOT NULL CONSTRAINT DF_Asesor_Activo DEFAULT (1)
);
GO

CREATE TABLE dbo.Cliente (
    ClienteId        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Cliente PRIMARY KEY,
    TipoDocumento    VARCHAR(10)       NOT NULL,   -- DNI, CE, RUC
    NumeroDocumento  VARCHAR(15)       NOT NULL,
    Nombres          VARCHAR(100)      NOT NULL,
    Apellidos        VARCHAR(100)      NOT NULL,
    Email            VARCHAR(150)      NULL,
    Telefono         VARCHAR(20)       NULL,
    FechaRegistro    DATETIME          NOT NULL CONSTRAINT DF_Cliente_FechaRegistro DEFAULT (GETDATE()),
    CONSTRAINT UQ_Cliente_Documento UNIQUE (TipoDocumento, NumeroDocumento)
);
GO

CREATE TABLE dbo.Lote (
    LoteId       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Lote PRIMARY KEY,
    ProyectoId   INT               NOT NULL CONSTRAINT FK_Lote_Proyecto REFERENCES dbo.Proyecto (ProyectoId),
    Manzana      VARCHAR(5)        NOT NULL,
    Numero       INT               NOT NULL,
    AreaM2       DECIMAL(10,2)     NOT NULL,
    PrecioSoles  DECIMAL(13,2)     NOT NULL,
    Estado       VARCHAR(15)       NOT NULL CONSTRAINT DF_Lote_Estado DEFAULT ('DISPONIBLE'),
    CONSTRAINT CK_Lote_Estado CHECK (Estado IN ('DISPONIBLE', 'SEPARADO', 'VENDIDO')),
    CONSTRAINT UQ_Lote_Ubicacion UNIQUE (ProyectoId, Manzana, Numero)
);
GO

CREATE TABLE dbo.Separacion (
    SeparacionId     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Separacion PRIMARY KEY,
    LoteId           INT               NOT NULL CONSTRAINT FK_Separacion_Lote    REFERENCES dbo.Lote (LoteId),
    ClienteId        INT               NOT NULL CONSTRAINT FK_Separacion_Cliente REFERENCES dbo.Cliente (ClienteId),
    AsesorId         INT               NOT NULL CONSTRAINT FK_Separacion_Asesor  REFERENCES dbo.Asesor (AsesorId),
    FechaSeparacion  DATE              NOT NULL,
    PrecioVenta      DECIMAL(12,2)     NOT NULL,
    MontoSeparacion  DECIMAL(12,2)     NOT NULL,
    NumeroCuotas     INT               NOT NULL,
    Estado           VARCHAR(15)       NOT NULL CONSTRAINT DF_Separacion_Estado DEFAULT ('VIGENTE'),
    FechaRegistro    DATETIME          NOT NULL CONSTRAINT DF_Separacion_FechaRegistro DEFAULT (GETDATE()),
    CONSTRAINT CK_Separacion_Estado CHECK (Estado IN ('VIGENTE', 'ANULADA', 'CONVERTIDA'))
);
GO

CREATE TABLE dbo.Cuota (
    CuotaId           INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Cuota PRIMARY KEY,
    SeparacionId      INT               NOT NULL CONSTRAINT FK_Cuota_Separacion REFERENCES dbo.Separacion (SeparacionId),
    NumeroCuota       INT               NOT NULL,
    FechaVencimiento  DATE              NOT NULL,
    Monto             DECIMAL(12,2)     NOT NULL,
    Estado            VARCHAR(15)       NOT NULL CONSTRAINT DF_Cuota_Estado DEFAULT ('PENDIENTE'),
    FechaPago         DATE              NULL,
    CONSTRAINT CK_Cuota_Estado CHECK (Estado IN ('PENDIENTE', 'PAGADA'))
);
GO
