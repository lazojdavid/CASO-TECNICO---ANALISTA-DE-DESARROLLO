"""Genera y da formato al reporte Excel de cuotas vencidas."""

from __future__ import annotations

import logging
import re
from datetime import datetime
from pathlib import Path

import pandas as pd
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter

OUTPUT_COLUMNS = [
    "Cliente", "Proyecto", "Lote", "Número de cuota",
    "Fecha de vencimiento", "Días de atraso", "Monto",
]


def safe_sheet_name(name: str, used: set[str]) -> str:
    cleaned = re.sub(r"[\\/*?:\[\]]", "_", str(name)).strip() or "Sin asesor"
    cleaned = cleaned[:31]
    candidate = cleaned
    suffix = 1
    while candidate.lower() in used:
        tail = f"_{suffix}"
        candidate = cleaned[: 31 - len(tail)] + tail
        suffix += 1
    used.add(candidate.lower())
    return candidate


def build_report(
    df: pd.DataFrame,
    cutoff: pd.Timestamp,
    output_path: Path,
) -> tuple[dict[str, object], Path]:
    # Solo se reportan cuotas pendientes de separaciones vigentes y vencidas antes del corte.
    overdue = df.loc[
        (df["EstadoSeparacion_norm"] == "VIGENTE")
        & (df["EstadoCuota_norm"] == "PENDIENTE")
        & (df["FechaVencimiento_dt"] < cutoff)
    ].copy()

    overdue["Días de atraso"] = (cutoff - overdue["FechaVencimiento_dt"]).dt.days
    overdue["Fecha de vencimiento"] = overdue["FechaVencimiento_dt"]
    overdue["Número de cuota"] = overdue["NumeroCuota_num"]
    overdue["Monto"] = overdue["Monto_num"]

    advisors = sorted(df["Asesor"].dropna().astype(str).unique(), key=str.casefold)
    if not advisors:
        raise ValueError("No se encontraron asesores válidos en el archivo.")

    try:
        totals = _write_workbook(overdue, advisors, output_path)
    except PermissionError:
        timestamp = datetime.now().strftime("%H%M%S_%f")
        alternate_path = output_path.with_name(
            f"{output_path.stem}_{timestamp}{output_path.suffix}"
        )
        logging.warning(
            "No se pudo sobrescribir %s (posiblemente está abierto). "
            "Se guardará el reporte en %s.",
            output_path,
            alternate_path,
        )
        output_path = alternate_path
        totals = _write_workbook(overdue, advisors, output_path)

    return (
        {
            "cuotas_vencidas": len(overdue),
            "asesores": len(advisors),
            "totales_por_asesor": totals,
            "total_general": float(overdue["Monto_num"].sum()),
        },
        output_path,
    )


def _write_workbook(
    overdue: pd.DataFrame,
    advisors: list[str],
    output_path: Path,
) -> dict[str, float]:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    used_names: set[str] = set()
    totals: dict[str, float] = {}

    with pd.ExcelWriter(output_path, engine="openpyxl", date_format="DD/MM/YYYY") as writer:
        for advisor in advisors:
            advisor_rows = overdue.loc[overdue["Asesor"] == advisor].copy()
            sheet = safe_sheet_name(advisor, used_names)

            if advisor_rows.empty:
                result = pd.DataFrame(columns=OUTPUT_COLUMNS)
                result.loc[0] = ["Sin cuotas vencidas"] + [""] * (len(OUTPUT_COLUMNS) - 1)
                total = 0.0
            else:
                result = advisor_rows[[
                    "Cliente", "Proyecto", "Lote", "Número de cuota",
                    "Fecha de vencimiento", "Días de atraso", "Monto",
                ]].sort_values(
                    by=["Fecha de vencimiento", "Cliente", "Número de cuota"]
                )
                total = float(advisor_rows["Monto_num"].sum())
            total_row = {col: "" for col in OUTPUT_COLUMNS}
            total_row["Cliente"] = "TOTAL PENDIENTE"
            total_row["Monto"] = total
            result = pd.concat([result, pd.DataFrame([total_row])], ignore_index=True)

            totals[advisor] = total
            result.to_excel(writer, sheet_name=sheet, index=False)

        # Formato legible de todas las hojas.
        for ws in writer.book.worksheets:
            ws.freeze_panes = "A2"
            ws.auto_filter.ref = ws.dimensions
            for cell in ws[1]:
                cell.font = Font(bold=True, color="FFFFFF")
                cell.fill = PatternFill("solid", fgColor="1F4E78")
                cell.alignment = Alignment(horizontal="center")
            for col_cells in ws.columns:
                max_len = max(len(str(c.value or "")) for c in col_cells)
                ws.column_dimensions[get_column_letter(col_cells[0].column)].width = min(max(max_len + 2, 14), 38)
            headers = {cell.value: cell.column for cell in ws[1]}
            if "Fecha de vencimiento" in headers:
                for row in range(2, ws.max_row + 1):
                    ws.cell(row, headers["Fecha de vencimiento"]).number_format = "DD/MM/YYYY"
            if "Monto" in headers:
                for row in range(2, ws.max_row + 1):
                    ws.cell(row, headers["Monto"]).number_format = '"S/ "#,##0.00'
            # Resaltar la fila del total.
            for row in range(2, ws.max_row + 1):
                if ws.cell(row, 1).value == "TOTAL PENDIENTE":
                    for cell in ws[row]:
                        cell.font = Font(bold=True)
                        cell.fill = PatternFill("solid", fgColor="D9EAF7")

    return totals
