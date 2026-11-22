USE RetoLotes;
GO

/* 1. Lotes y su proyecto */
SELECT
    p.Nombre AS Proyecto,
    l.LoteId,
    l.Manzana,
    l.Numero AS NumeroLote,
    l.AreaM2,
    l.PrecioSoles,
    l.Estado
FROM dbo.Lote AS l
JOIN dbo.Proyecto AS p ON p.ProyectoId = l.ProyectoId
ORDER BY p.Nombre, l.Manzana, l.Numero;
GO

/* 2. Clientes */
SELECT
    ClienteId,
    TipoDocumento,
    NumeroDocumento,
    Nombres,
    Apellidos,
    Email,
    Telefono,
    FechaRegistro
FROM dbo.Cliente
ORDER BY ClienteId DESC;
GO

/* 3. Separaciones con lote, proyecto, cliente y asesor */
SELECT
    s.SeparacionId,
    p.Nombre AS Proyecto,
    l.Manzana,
    l.Numero AS NumeroLote,
    c.TipoDocumento,
    c.NumeroDocumento,
    CONCAT(c.Nombres, ' ', c.Apellidos) AS Cliente,
    a.Nombres AS Asesor,
    s.FechaSeparacion,
    s.PrecioVenta,
    s.MontoSeparacion,
    s.NumeroCuotas,
    s.Estado
FROM dbo.Separacion AS s
JOIN dbo.Lote AS l ON l.LoteId = s.LoteId
JOIN dbo.Proyecto AS p ON p.ProyectoId = l.ProyectoId
JOIN dbo.Cliente AS c ON c.ClienteId = s.ClienteId
JOIN dbo.Asesor AS a ON a.AsesorId = s.AsesorId
ORDER BY s.SeparacionId DESC;
GO

/* 4. Cuotas y estado de pago */
SELECT
    cu.CuotaId,
    cu.SeparacionId,
    cu.NumeroCuota,
    cu.FechaVencimiento,
    cu.Monto,
    cu.Estado,
    cu.FechaPago
FROM dbo.Cuota AS cu
ORDER BY cu.SeparacionId DESC, cu.NumeroCuota;
GO

/* 5. Cuotas pendientes vencidas */
SELECT
    a.Nombres AS Asesor,
    CONCAT(c.Nombres, ' ', c.Apellidos) AS Cliente,
    p.Nombre AS Proyecto,
    CONCAT(l.Manzana, '-', l.Numero) AS Lote,
    cu.NumeroCuota,
    cu.FechaVencimiento,
    DATEDIFF(DAY, cu.FechaVencimiento, CAST(GETDATE() AS DATE)) AS DiasAtraso,
    cu.Monto
FROM dbo.Cuota AS cu
JOIN dbo.Separacion AS s ON s.SeparacionId = cu.SeparacionId
JOIN dbo.Lote AS l ON l.LoteId = s.LoteId
JOIN dbo.Proyecto AS p ON p.ProyectoId = l.ProyectoId
JOIN dbo.Cliente AS c ON c.ClienteId = s.ClienteId
JOIN dbo.Asesor AS a ON a.AsesorId = s.AsesorId
WHERE cu.Estado = 'PENDIENTE'
  AND cu.FechaVencimiento < CAST(GETDATE() AS DATE)
ORDER BY a.Nombres, cu.FechaVencimiento;
GO

/* 6. Lotes de los dos proyectos insertados por PRUEBAS_DML_RetoLotes.sql */
SELECT
    p.Nombre AS Proyecto,
    l.LoteId,
    l.Manzana,
    l.Numero AS NumeroLote,
    l.Estado
FROM dbo.Proyecto AS p
JOIN dbo.Lote AS l ON l.ProyectoId = p.ProyectoId
WHERE p.Nombre IN ('Residencial las lomas', 'Villa Sol')
  AND p.ProyectoId IN (
      SELECT MAX(ProyectoId)
      FROM dbo.Proyecto
      WHERE Nombre IN ('Residencial las lomas', 'Villa Sol')
      GROUP BY Nombre
  )
ORDER BY p.ProyectoId DESC, l.Manzana;
GO

/* 7. Cuotas duplicadas para una misma separación y número */
SELECT
    SeparacionId,
    NumeroCuota,
    COUNT(*) AS VecesRegistrada
FROM dbo.Cuota
GROUP BY SeparacionId, NumeroCuota
HAVING COUNT(*) > 1
ORDER BY SeparacionId, NumeroCuota;
GO

/* 8. Lotes con más de una separación vigente (posible carrera concurrente) */
SELECT
    s.LoteId,
    p.Nombre AS Proyecto,
    l.Manzana,
    l.Numero AS NumeroLote,
    COUNT(*) AS SeparacionesVigentes
FROM dbo.Separacion AS s
JOIN dbo.Lote AS l ON l.LoteId = s.LoteId
JOIN dbo.Proyecto AS p ON p.ProyectoId = l.ProyectoId
WHERE s.Estado = 'VIGENTE'
GROUP BY s.LoteId, p.Nombre, l.Manzana, l.Numero
HAVING COUNT(*) > 1
ORDER BY p.Nombre, l.Manzana, l.Numero;
GO

/* 9. Lotes con separaciones vigentes realizadas por clientes diferentes */
;WITH LotesConClientesDistintos AS (
    SELECT LoteId
    FROM dbo.Separacion
    WHERE Estado = 'VIGENTE'
    GROUP BY LoteId
    HAVING COUNT(DISTINCT ClienteId) > 1
)
SELECT
    p.Nombre AS Proyecto,
    l.LoteId,
    l.Manzana,
    l.Numero AS NumeroLote,
    s.SeparacionId,
    c.ClienteId,
    CONCAT(c.Nombres, ' ', c.Apellidos) AS Cliente,
    s.FechaSeparacion,
    s.Estado AS EstadoSeparacion
FROM dbo.Separacion AS s
JOIN LotesConClientesDistintos AS d ON d.LoteId = s.LoteId
JOIN dbo.Lote AS l ON l.LoteId = s.LoteId
JOIN dbo.Proyecto AS p ON p.ProyectoId = l.ProyectoId
JOIN dbo.Cliente AS c ON c.ClienteId = s.ClienteId
WHERE s.Estado = 'VIGENTE'
ORDER BY p.Nombre, l.Manzana, l.Numero, s.FechaSeparacion, s.SeparacionId;
GO



/* dos clientes separaron el mismo lote, conflicto