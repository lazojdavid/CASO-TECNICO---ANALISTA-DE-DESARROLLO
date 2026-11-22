/* =====================================================================
   Datos y pruebas DML para RetoLotes.
   Requiere esquema.sql y procedimientos_actuales.sql ya ejecutados.
   Ejecutar solo en una base de pruebas: crea registros QA.
   ===================================================================== */

USE RetoLotes;
GO
SET NOCOUNT ON;

DECLARE @Tag VARCHAR(14) =
        CONVERT(CHAR(8), GETDATE(), 112)
        + RIGHT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 6);
DECLARE @ProyectoLomasId INT;
DECLARE @ProyectoVillaSolId INT;
DECLARE @AsesorId INT;
DECLARE @ClienteAId INT;
DECLARE @ClienteBId INT;
DECLARE @LoteDuplicadoCuotaId INT;
DECLARE @SeparacionDuplicadaCuotaId INT;

/* La etiqueta permite ejecutar el archivo varias veces sin reutilizar los
   documentos únicos ni el lote de la prueba de concurrencia. */
INSERT INTO dbo.Proyecto (Nombre, Ubicacion, Activo)
VALUES ('Residencial las lomas', 'Ubicación ficticia QA', 1);
SET @ProyectoLomasId = CONVERT(INT, SCOPE_IDENTITY());

INSERT INTO dbo.Proyecto (Nombre, Ubicacion, Activo)
VALUES ('Villa Sol', 'Ubicación ficticia QA', 1);
SET @ProyectoVillaSolId = CONVERT(INT, SCOPE_IDENTITY());

INSERT INTO dbo.Asesor (Nombres, Email, Activo)
VALUES (CONCAT('QA Asesor ', @Tag), CONCAT('qa+', @Tag, '@example.invalid'), 1);
SET @AsesorId = CONVERT(INT, SCOPE_IDENTITY());

INSERT INTO dbo.Cliente
    (TipoDocumento, NumeroDocumento, Nombres, Apellidos, Email, Telefono)
VALUES
    ('QA', CONCAT(@Tag, '1'), CONCAT('QA Cliente A ', @Tag), 'Prueba',
     CONCAT('cliente-a+', @Tag, '@example.invalid'), '900000001'),
    ('QA', CONCAT(@Tag, '2'), CONCAT('QA Cliente B ', @Tag), 'Prueba',
     CONCAT('cliente-b+', @Tag, '@example.invalid'), '900000002');

SELECT @ClienteAId = ClienteId
FROM dbo.Cliente
WHERE TipoDocumento = 'QA' AND NumeroDocumento = CONCAT(@Tag, '1');

SELECT @ClienteBId = ClienteId
FROM dbo.Cliente
WHERE TipoDocumento = 'QA' AND NumeroDocumento = CONCAT(@Tag, '2');

/* C y D pertenecen a Residencial las lomas.
   Z y M pertenecen a Villa Sol. */
INSERT INTO dbo.Lote (ProyectoId, Manzana, Numero, AreaM2, PrecioSoles, Estado)
VALUES
    (@ProyectoLomasId, 'C', 1, 100.00, 100000.00, 'DISPONIBLE'),
    (@ProyectoLomasId, 'D', 1, 100.00, 100000.00, 'SEPARADO'),
    (@ProyectoVillaSolId, 'Z', 1, 100.00, 100000.00, 'DISPONIBLE'),
    (@ProyectoVillaSolId, 'M', 1, 100.00, 100000.00, 'DISPONIBLE');

/* Error esperado: el documento ya existe (UQ_Cliente_Documento). */
BEGIN TRY
    INSERT INTO dbo.Cliente
        (TipoDocumento, NumeroDocumento, Nombres, Apellidos)
    VALUES ('QA', CONCAT(@Tag, '1'), 'QA Duplicado', 'Prueba');
    PRINT 'ERROR: se aceptó un documento duplicado.';
END TRY
BEGIN CATCH
    PRINT CONCAT('Duplicado de cliente rechazado: ', ERROR_MESSAGE());
END CATCH;

/* Error esperado: la ubicación del lote ya existe (UQ_Lote_Ubicacion). */
BEGIN TRY
    INSERT INTO dbo.Lote (ProyectoId, Manzana, Numero, AreaM2, PrecioSoles)
    VALUES (@ProyectoLomasId, 'C', 1, 100.00, 100000.00);
    PRINT 'ERROR: se aceptó una ubicación de lote duplicada.';
END TRY
BEGIN CATCH
    PRINT CONCAT('Duplicado de lote rechazado: ', ERROR_MESSAGE());
END CATCH;

/* Error esperado: estado fuera del CHECK de dbo.Lote. */
BEGIN TRY
    INSERT INTO dbo.Lote (ProyectoId, Manzana, Numero, AreaM2, PrecioSoles, Estado)
    VALUES (@ProyectoLomasId, 'E', 1, 100.00, 100000.00, 'RESERVADO');
    PRINT 'ERROR: se aceptó un estado de lote inválido.';
END TRY
BEGIN CATCH
    PRINT CONCAT('Estado inválido rechazado: ', ERROR_MESSAGE());
END CATCH;

/* Este esquema no tiene UNIQUE (SeparacionId, NumeroCuota).
   La segunda fila duplicada se inserta para evidenciar el caso que pasa
   inadvertido en los procedimientos actuales. */
SELECT @LoteDuplicadoCuotaId = LoteId
FROM dbo.Lote
WHERE ProyectoId = @ProyectoLomasId AND Manzana = 'D' AND Numero = 1;

INSERT INTO dbo.Separacion
    (LoteId, ClienteId, AsesorId, FechaSeparacion, PrecioVenta,
     MontoSeparacion, NumeroCuotas, Estado)
VALUES
    (@LoteDuplicadoCuotaId, @ClienteAId, @AsesorId, CAST(GETDATE() AS DATE),
     100000.00, 10000.00, 12, 'VIGENTE');
SET @SeparacionDuplicadaCuotaId = CONVERT(INT, SCOPE_IDENTITY());

/* Segundo cliente separa el mismo lote D-1: caso que debe aparecer en
   la consulta de lotes separados por clientes diferentes. */
INSERT INTO dbo.Separacion
    (LoteId, ClienteId, AsesorId, FechaSeparacion, PrecioVenta,
     MontoSeparacion, NumeroCuotas, Estado)
VALUES
    (@LoteDuplicadoCuotaId, @ClienteBId, @AsesorId, CAST(GETDATE() AS DATE),
     100000.00, 10000.00, 12, 'VIGENTE');

INSERT INTO dbo.Cuota (SeparacionId, NumeroCuota, FechaVencimiento, Monto, Estado)
VALUES
    (@SeparacionDuplicadaCuotaId, 1, DATEADD(MONTH, 1, CAST(GETDATE() AS DATE)),
     7500.00, 'PENDIENTE'),
    (@SeparacionDuplicadaCuotaId, 1, DATEADD(MONTH, 1, CAST(GETDATE() AS DATE)),
     7500.00, 'PENDIENTE');

SELECT @Tag AS EtiquetaDeEstaEjecucion,
       @ProyectoLomasId AS ProyectoResidencialLasLomasId,
       @ProyectoVillaSolId AS ProyectoVillaSolId,
       @LoteDuplicadoCuotaId AS LoteIdConCuotaDuplicada,
       @SeparacionDuplicadaCuotaId AS SeparacionIdConCuotaDuplicada;

SELECT SeparacionId, NumeroCuota, COUNT(*) AS VecesRegistrada
FROM dbo.Cuota
WHERE SeparacionId = @SeparacionDuplicadaCuotaId
GROUP BY SeparacionId, NumeroCuota
HAVING COUNT(*) > 1;
GO

/* =====================================================================
   PRUEBA DE CONCURRENCIA: ejecutar cada bloque en una ventana distinta
   de SSMS/Azure Data Studio, iniciándolos con menos de cinco segundos
   de diferencia. El WAITFOR intenta sincronizar ambas llamadas.
   Ambos usuarios intentan separar el lote C-1 de Residencial las lomas.
   La carrera no es
   determinista; repetir la prueba puede ser necesario para reproducirla.
   =====================================================================

-- VENTANA 1: cliente A
USE RetoLotes;
DECLARE @LoteId INT, @ClienteId INT, @AsesorId INT;
SELECT TOP (1) @LoteId = l.LoteId
FROM dbo.Lote AS l
JOIN dbo.Proyecto AS p ON p.ProyectoId = l.ProyectoId
WHERE p.Nombre = 'Residencial las lomas'
  AND p.ProyectoId = (
      SELECT MAX(ProyectoId) FROM dbo.Proyecto WHERE Nombre = 'Residencial las lomas'
  )
  AND l.Manzana = 'C' AND l.Numero = 1
ORDER BY p.ProyectoId DESC;
SELECT TOP (1) @ClienteId = ClienteId
FROM dbo.Cliente WHERE Nombres LIKE 'QA Cliente A %'
ORDER BY ClienteId DESC;
SELECT TOP (1) @AsesorId = AsesorId
FROM dbo.Asesor WHERE Nombres LIKE 'QA Asesor %'
ORDER BY AsesorId DESC;
WAITFOR DELAY '00:00:05';
EXEC dbo.usp_RegistrarSeparacion
    @LoteId = @LoteId, @ClienteId = @ClienteId, @AsesorId = @AsesorId,
    @MontoSeparacion = 10000.00, @NumeroCuotas = 12;

-- VENTANA 2: cliente B (ejecutar a la vez que la VENTANA 1)
USE RetoLotes;
DECLARE @LoteId INT, @ClienteId INT, @AsesorId INT;
SELECT TOP (1) @LoteId = l.LoteId
FROM dbo.Lote AS l
JOIN dbo.Proyecto AS p ON p.ProyectoId = l.ProyectoId
WHERE p.Nombre = 'Residencial las lomas'
  AND p.ProyectoId = (
      SELECT MAX(ProyectoId) FROM dbo.Proyecto WHERE Nombre = 'Residencial las lomas'
  )
  AND l.Manzana = 'C' AND l.Numero = 1
ORDER BY p.ProyectoId DESC;
SELECT TOP (1) @ClienteId = ClienteId
FROM dbo.Cliente WHERE Nombres LIKE 'QA Cliente B %'
ORDER BY ClienteId DESC;
SELECT TOP (1) @AsesorId = AsesorId
FROM dbo.Asesor WHERE Nombres LIKE 'QA Asesor %'
ORDER BY AsesorId DESC;
WAITFOR DELAY '00:00:05';
EXEC dbo.usp_RegistrarSeparacion
    @LoteId = @LoteId, @ClienteId = @ClienteId, @AsesorId = @AsesorId,
    @MontoSeparacion = 10000.00, @NumeroCuotas = 12;

-- Comprobar si el mismo lote terminó con más de una separación vigente:
SELECT s.LoteId, COUNT(*) AS SeparacionesVigentes
FROM dbo.Separacion AS s
JOIN dbo.Lote AS l ON l.LoteId = s.LoteId
JOIN dbo.Proyecto AS p ON p.ProyectoId = l.ProyectoId
WHERE s.Estado = 'VIGENTE'
  AND p.Nombre = 'Residencial las lomas'
  AND p.ProyectoId = (
      SELECT MAX(ProyectoId) FROM dbo.Proyecto WHERE Nombre = 'Residencial las lomas'
  )
  AND l.Manzana = 'C' AND l.Numero = 1
GROUP BY s.LoteId
HAVING COUNT(*) > 1;

===================================================================== */

/* =====================================================================
   PRUEBAS OPCIONALES DEL PROCEDIMIENTO:
   Selecciona y ejecuta estos bloques por separado. La prueba de cero cuotas
   puede dejar una separación parcial; no ejecutar en producción.
   =====================================================================

-- CASO: cero cuotas. Debe fallar al dividir entre cero, pero puede quedar
-- creada la separación porque usp_RegistrarSeparacion no usa transacción.
USE RetoLotes;
DECLARE @LoteZ INT, @ClienteA INT, @AsesorZ INT;
SELECT TOP (1) @LoteZ = l.LoteId
FROM dbo.Lote AS l
JOIN dbo.Proyecto AS p ON p.ProyectoId = l.ProyectoId
WHERE p.Nombre = 'Villa Sol'
  AND p.ProyectoId = (SELECT MAX(ProyectoId) FROM dbo.Proyecto WHERE Nombre = 'Villa Sol')
  AND l.Manzana = 'Z' AND l.Numero = 1
ORDER BY p.ProyectoId DESC;
SELECT TOP (1) @ClienteA = ClienteId
FROM dbo.Cliente WHERE Nombres LIKE 'QA Cliente A %'
ORDER BY ClienteId DESC;
SELECT TOP (1) @AsesorZ = AsesorId
FROM dbo.Asesor WHERE Nombres LIKE 'QA Asesor %'
ORDER BY AsesorId DESC;
BEGIN TRY
    EXEC dbo.usp_RegistrarSeparacion
        @LoteId = @LoteZ, @ClienteId = @ClienteA, @AsesorId = @AsesorZ,
        @MontoSeparacion = 10000.00, @NumeroCuotas = 0;
END TRY
BEGIN CATCH
    SELECT ERROR_MESSAGE() AS ErrorEsperado;
END CATCH;
SELECT s.SeparacionId, s.Estado, l.Estado AS EstadoLote
FROM dbo.Separacion AS s
JOIN dbo.Lote AS l ON l.LoteId = s.LoteId
WHERE l.LoteId = @LoteZ;

-- CASO: monto de separación mayor que el precio. El procedimiento actual
-- puede generar cuotas negativas porque no valida los importes.
DECLARE @LoteM INT, @ClienteB INT, @AsesorM INT;
SELECT TOP (1) @LoteM = l.LoteId
FROM dbo.Lote AS l
JOIN dbo.Proyecto AS p ON p.ProyectoId = l.ProyectoId
WHERE p.Nombre = 'Villa Sol'
  AND p.ProyectoId = (SELECT MAX(ProyectoId) FROM dbo.Proyecto WHERE Nombre = 'Villa Sol')
  AND l.Manzana = 'M' AND l.Numero = 1
ORDER BY p.ProyectoId DESC;
SELECT TOP (1) @ClienteB = ClienteId
FROM dbo.Cliente WHERE Nombres LIKE 'QA Cliente B %'
ORDER BY ClienteId DESC;
SELECT TOP (1) @AsesorM = AsesorId
FROM dbo.Asesor WHERE Nombres LIKE 'QA Asesor %'
ORDER BY AsesorId DESC;
EXEC dbo.usp_RegistrarSeparacion
    @LoteId = @LoteM, @ClienteId = @ClienteB, @AsesorId = @AsesorM,
    @MontoSeparacion = 150000.00, @NumeroCuotas = 2;
SELECT cu.*
FROM dbo.Cuota AS cu
JOIN dbo.Separacion AS s ON s.SeparacionId = cu.SeparacionId
WHERE s.LoteId = @LoteM AND cu.Monto <= 0;

-- CASO: cronograma de una separación inexistente; el procedimiento puede
-- finalizar sin informar que no encontró la separación.
EXEC dbo.usp_GenerarCronograma @SeparacionId = -999999;

   No ejecutar estas pruebas contra datos de producción.
   ===================================================================== */
