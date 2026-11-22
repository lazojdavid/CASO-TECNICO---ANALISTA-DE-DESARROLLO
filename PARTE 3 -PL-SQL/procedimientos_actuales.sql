/* =====================================================================
   Sistema de Ventas de Lotes - procedimientos en producción
   Versión exportada para revisión. No es necesario ejecutarlos.
   ===================================================================== */

USE RetoLotes;
GO

/* ---------------------------------------------------------------------
   Lista los lotes de un proyecto, opcionalmente filtrados por estado.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_ListarLotes
    @ProyectoId INT,
    @Estado     VARCHAR(15) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT l.LoteId, l.Manzana, l.Numero, l.AreaM2, l.PrecioSoles, l.Estado
    FROM dbo.Lote l
    WHERE l.ProyectoId = @ProyectoId
      AND (@Estado IS NULL OR l.Estado = @Estado)
    ORDER BY l.Manzana, l.Numero;
END
GO

/* ---------------------------------------------------------------------
   Genera el cronograma de cuotas mensuales de una separación.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_GenerarCronograma
    @SeparacionId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Saldo        DECIMAL(12,2),
            @NumeroCuotas INT,
            @Fecha        DATE;

    SELECT @Saldo        = PrecioVenta - MontoSeparacion,
           @NumeroCuotas = NumeroCuotas,
           @Fecha        = FechaSeparacion
    FROM dbo.Separacion
    WHERE SeparacionId = @SeparacionId;

    DECLARE @MontoCuota DECIMAL(12,2) = ROUND(@Saldo / @NumeroCuotas, 2);
    DECLARE @i INT = 1;

    WHILE @i <= @NumeroCuotas
    BEGIN
        INSERT INTO dbo.Cuota (SeparacionId, NumeroCuota, FechaVencimiento, Monto, Estado)
        VALUES (@SeparacionId, @i, DATEADD(MONTH, @i, @Fecha), @MontoCuota, 'PENDIENTE');

        SET @i = @i + 1;
    END
END
GO

/* ---------------------------------------------------------------------
   Registra la separación de un lote y genera su cronograma.
   Lo invoca la pantalla "Nueva separación".
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_RegistrarSeparacion
    @LoteId           INT,
    @ClienteId        INT,
    @AsesorId         INT,
    @MontoSeparacion  DECIMAL(12,2),
    @NumeroCuotas     INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Estado VARCHAR(15),
            @Precio DECIMAL(12,2);

    SELECT @Estado = Estado,
           @Precio = PrecioSoles
    FROM dbo.Lote
    WHERE LoteId = @LoteId;

    IF @Estado <> 'DISPONIBLE'
    BEGIN
        RAISERROR('El lote seleccionado no está disponible.', 16, 1);
        RETURN;
    END

    INSERT INTO dbo.Separacion (LoteId, ClienteId, AsesorId, FechaSeparacion,
                                PrecioVenta, MontoSeparacion, NumeroCuotas, Estado)
    VALUES (@LoteId, @ClienteId, @AsesorId, CAST(GETDATE() AS DATE),
            @Precio, @MontoSeparacion, @NumeroCuotas, 'VIGENTE');

    DECLARE @SeparacionId INT = SCOPE_IDENTITY();

    EXEC dbo.usp_GenerarCronograma @SeparacionId;

    UPDATE dbo.Lote
       SET Estado = 'SEPARADO'
     WHERE LoteId = @LoteId;

    SELECT @SeparacionId AS SeparacionId;
END
GO

/* ---------------------------------------------------------------------
   Reporte diario de cuotas vencidas por asesor.
   Lo ejecuta un job del SQL Server Agent a las 07:00 y el resultado
   se envía por correo al área comercial.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_ReporteCuotasVencidas
AS
BEGIN
    SET NOCOUNT ON;

    SELECT a.Nombres                                   AS Asesor,
           a.Email                                     AS EmailAsesor,
           c.Nombres + ' ' + c.Apellidos               AS Cliente,
           p.Nombre                                    AS Proyecto,
           l.Manzana + '-' + CAST(l.Numero AS VARCHAR) AS Lote,
           cu.NumeroCuota,
           cu.FechaVencimiento,
           DATEDIFF(DAY, cu.FechaVencimiento, GETDATE()) AS DiasAtraso,
           cu.Monto
    FROM dbo.Cuota cu
    JOIN dbo.Separacion s ON s.SeparacionId = cu.SeparacionId
    JOIN dbo.Lote       l ON l.LoteId       = s.LoteId
    JOIN dbo.Proyecto   p ON p.ProyectoId   = l.ProyectoId
    JOIN dbo.Cliente    c ON c.ClienteId    = s.ClienteId
    JOIN dbo.Asesor     a ON a.AsesorId     = s.AsesorId
    WHERE cu.Estado = 'PENDIENTE'
      AND cu.FechaVencimiento <= GETDATE()
    ORDER BY a.Nombres, DiasAtraso DESC;
END
GO
