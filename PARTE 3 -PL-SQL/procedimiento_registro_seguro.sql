/* =====================================================================
   Registro transaccional de separaciones.
   Atiende INC-0412, INC-0431 e INC-0447 del incidencias_log.txt.
   No modifica los procedimientos existentes.
   ===================================================================== */

USE RetoLotes;
GO

CREATE OR ALTER PROCEDURE dbo.usp_RegistrarSeparacionSeguro
    @LoteId          INT,
    @ClienteId       INT,
    @AsesorId        INT,
    @MontoSeparacion DECIMAL(12,2),
    @NumeroCuotas    INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @LoteId IS NULL OR @ClienteId IS NULL OR @AsesorId IS NULL
        THROW 51000, 'Lote, cliente y asesor son obligatorios.', 1;

    IF @MontoSeparacion IS NULL OR @MontoSeparacion <= 0
        THROW 51001, 'El monto de separación debe ser mayor que cero.', 1;

    IF @NumeroCuotas IS NULL OR @NumeroCuotas < 0
        THROW 51002, 'El número de cuotas no puede ser negativo.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Cliente WHERE ClienteId = @ClienteId)
        THROW 51003, 'El cliente indicado no existe.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Asesor WHERE AsesorId = @AsesorId)
        THROW 51004, 'El asesor indicado no existe.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @LoteActualizado TABLE (PrecioSoles DECIMAL(13,2));
        DECLARE @PrecioLote DECIMAL(13,2);
        DECLARE @Saldo DECIMAL(12,2);
        DECLARE @MontoCuotaBase DECIMAL(12,2);
        DECLARE @MontoCuota DECIMAL(12,2);
        DECLARE @FechaSeparacion DATE = CAST(GETDATE() AS DATE);
        DECLARE @SeparacionId INT;
        DECLARE @NumeroCuota INT = 1;

        /* La actualización condicional reserva el lote de forma atómica.
           Otra sesión no puede registrar el mismo lote como disponible. */
        UPDATE dbo.Lote WITH (UPDLOCK, HOLDLOCK)
        SET Estado = 'SEPARADO'
        OUTPUT INSERTED.PrecioSoles INTO @LoteActualizado (PrecioSoles)
        WHERE LoteId = @LoteId
          AND Estado = 'DISPONIBLE';

        IF @@ROWCOUNT = 0
            THROW 51005, 'El lote no existe o ya no está disponible.', 1;

        SELECT @PrecioLote = PrecioSoles
        FROM @LoteActualizado;

        IF EXISTS (
            SELECT 1
            FROM dbo.Separacion WITH (UPDLOCK, HOLDLOCK)
            WHERE LoteId = @LoteId
              AND Estado = 'VIGENTE'
        )
            THROW 51006, 'El lote ya tiene una separación vigente.', 1;

        IF @MontoSeparacion > @PrecioLote
            THROW 51007, 'El monto de separación no puede superar el precio del lote.', 1;

        SET @Saldo = CONVERT(DECIMAL(12,2), @PrecioLote - @MontoSeparacion);

        IF @NumeroCuotas > 0 AND @Saldo <= 0
            THROW 51008, 'Con saldo cero, registre la separación sin cuotas.', 1;

        IF @NumeroCuotas > @Saldo * 100
            THROW 51009, 'El saldo no alcanza para asignar al menos un céntimo a cada cuota.', 1;

        INSERT INTO dbo.Separacion
            (LoteId, ClienteId, AsesorId, FechaSeparacion, PrecioVenta,
             MontoSeparacion, NumeroCuotas, Estado)
        VALUES
            (@LoteId, @ClienteId, @AsesorId, @FechaSeparacion, @PrecioLote,
             @MontoSeparacion, @NumeroCuotas, 'VIGENTE');

        SET @SeparacionId = CONVERT(INT, SCOPE_IDENTITY());

        /* Cero cuotas es válido para un pago directo posterior: no crea
           cronograma, pero la separación y el cambio de estado sí se guardan. */
        IF @NumeroCuotas > 0
        BEGIN
            SET @MontoCuotaBase = CONVERT(
                DECIMAL(12,2),
                FLOOR((@Saldo * 100.00) / @NumeroCuotas) / 100.00
            );

            WHILE @NumeroCuota <= @NumeroCuotas
            BEGIN
                SET @MontoCuota =
                    CASE
                        WHEN @NumeroCuota = @NumeroCuotas
                            THEN @Saldo - (@MontoCuotaBase * (@NumeroCuotas - 1))
                        ELSE @MontoCuotaBase
                    END;

                INSERT INTO dbo.Cuota
                    (SeparacionId, NumeroCuota, FechaVencimiento, Monto, Estado)
                VALUES
                    (@SeparacionId, @NumeroCuota,
                     DATEADD(MONTH, @NumeroCuota, @FechaSeparacion),
                     @MontoCuota, 'PENDIENTE');

                SET @NumeroCuota += 1;
            END
        END

        COMMIT TRANSACTION;

        SELECT @SeparacionId AS SeparacionId;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH
END
GO
