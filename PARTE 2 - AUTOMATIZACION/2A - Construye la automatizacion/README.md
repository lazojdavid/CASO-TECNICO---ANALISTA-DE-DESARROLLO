# Automatización de cartera de cuotas vencidas

## Requisitos
- Python 3.11 o superior.
- Dependencias indicadas en `requirements.txt`.

## Estructura de carpetas
Coloca los archivos así, usando la carpeta donde está `main.py` como raíz:

```text
automatizacion_cartera/
├── main.py
├── requirements.txt
├── data/
│   └── cartera_cuotas.csv       # Debes crear esta carpeta y proporcionar el CSV
├── output/                      # Se crea automáticamente al generar el reporte
└── logs/                        # Se crea automáticamente al iniciar el programa
```

El programa lee por defecto `data/cartera_cuotas.csv`, guarda el Excel en
`output/reporte_cuotas_vencidas.xlsx` y escribe cada ejecución en un log
independiente con fecha y hora, por ejemplo `logs/ejecucion_20261122_084158_745000.log`.
Por ello, solo es necesario crear `data/` y colocar allí
el CSV; `output/` y `logs/` se crean si no existen. El CSV debe estar codificado
en UTF-8 y separado por punto y coma (`;`). Sus columnas obligatorias son:
`SeparacionId`, `EstadoSeparacion`, `Proyecto`, `Manzana`, `Lote`, `Cliente`,
`Asesor`, `NumeroCuota`, `FechaVencimiento`, `Monto` y `EstadoCuota`.
`FechaVencimiento` debe tener formato `DD/MM/AAAA`; los estados válidos son
`VIGENTE`/`ANULADA` para la separación y `PENDIENTE`/`PAGADA` para la cuota.

## Instalación
Desde esta carpeta:

```bash
python -m venv .venv
```

Windows PowerShell:

```powershell
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

## Ejecución
Al ejecutar, el programa preguntará la fecha de corte en formato `DD/MM/AAAA`.
La fecha de hoy aparecerá como valor predeterminado; presiona Enter para usarla.
Si se ingresa una fecha inválida, también se utilizará la fecha de hoy.
Ejecuta `python main.py` desde la terminal integrada de VS Code o PowerShell
para poder responder al `input`; evita ejecutar una copia temporal como
`tempCodeRunnerFile.py`.

```powershell
python main.py
```

También se puede proporcionar la fecha como argumento:

```powershell
python main.py --fecha-corte 01/12/2026
```

También se puede indicar otra ruta de entrada y salida. Al nombre del Excel
se le agrega automáticamente la fecha de generación en formato `AAAAMMDD`;
por ejemplo, `output/reporte_20261201.xlsx`:

```powershell
python main.py --archivo data/cartera_cuotas.csv --fecha-corte 01/12/2026 --salida output/reporte.xlsx
```

## Reglas de negocio implementadas
- Solo se consideran separaciones `VIGENTE`.
- Solo se consideran cuotas `PENDIENTE`.
- Una cuota está vencida cuando `FechaVencimiento` es anterior a la fecha de corte.
- Los días de atraso son la diferencia en días calendario entre la fecha de corte y la fecha de vencimiento.
- Se utiliza `Monto` como importe pendiente porque la exportación no contiene una columna de saldo ni detalle de pagos parciales.
- Se eliminan duplicados exactos y se excluyen filas con campos obligatorios inválidos o claves de cuota repetidas con conflicto.
- Los asesores sin cuotas vencidas también reciben una hoja con el mensaje correspondiente.

## Salidas
- `output/reporte_cuotas_vencidas_AAAAMMDD.xlsx`: una hoja por asesor, con detalle y total pendiente. Las ejecuciones del mismo día actualizan el archivo de esa fecha.
- `logs/ejecucion_AAAAMMDD_HHMMSS_microsegundos.log`: validaciones, advertencias y errores de cada ejecución.

## Limitación detectada en el archivo entregado
`EmailAsesor` no está informado para Martín Quispe. El Excel se genera de todas formas, pero se debe completar ese dato antes de automatizar el envío de correos.
