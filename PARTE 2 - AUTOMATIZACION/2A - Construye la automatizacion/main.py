#!/usr/bin/env python3
"""Genera un Excel con cuotas vencidas agrupadas por asesor."""

from __future__ import annotations

import argparse
import logging
import re
import sys
from datetime import date, datetime
from pathlib import Path

import pandas as pd
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter

from gmail_drafts import open_gmail_draft

REQUIRED_COLUMNS = [
    "SeparacionId", "EstadoSeparacion", "Proyecto", "Manzana", "Lote",
    "Cliente", "Asesor", "NumeroCuota", "FechaVencimiento", "Monto",
    "EstadoCuota",
]
OPTIONAL_COLUMNS = ["DocumentoCliente", "TelefonoCliente", "EmailAsesor", "FechaPago"]
OUTPUT_COLUMNS = [
    "Cliente", "Proyecto", "Lote", "Número de cuota",
    "Fecha de vencimiento", "Días de atraso", "Monto",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Genera un Excel de cuotas vencidas por asesor."
    )
    parser.add_argument(
        "--archivo", default="data/cartera_cuotas.csv",
        help="Ruta del CSV de entrada (por defecto: data/cartera_cuotas.csv).",
    )
    parser.add_argument(
        "--fecha-corte",
        help="Fecha de corte en formato DD/MM/AAAA. Si se omite, se solicitará por consola.",
    )
    parser.add_argument(
        "--salida", default="output/reporte_cuotas_vencidas.xlsx",
        help="Ruta del Excel de salida.",
    )
    return parser.parse_args()


def configure_logging(base_dir: Path) -> None:
    log_dir = base_dir / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
        handlers=[
            logging.FileHandler(log_dir / f"ejecucion_{timestamp}.log", encoding="utf-8"),
            logging.StreamHandler(sys.stdout),
        ],
        force=True,
    )


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


def load_and_validate(csv_path: Path) -> tuple[pd.DataFrame, list[str], dict[str, int]]:
    if not csv_path.exists():
        raise FileNotFoundError(f"No se encontró el archivo de entrada: {csv_path}")
    if csv_path.stat().st_size == 0:
        raise ValueError("El archivo CSV está vacío.")

    # La exportación entregada utiliza punto y coma y codificación UTF-8.
    df = pd.read_csv(csv_path, sep=";", encoding="utf-8-sig", dtype=str)
    if df.empty:
        raise ValueError("El CSV no contiene registros.")

    missing_columns = [c for c in REQUIRED_COLUMNS if c not in df.columns]
    if missing_columns:
        raise ValueError(
            "Faltan columnas obligatorias en el CSV: " + ", ".join(missing_columns)
        )

    # Quitar espacios en campos de texto para normalizar estados y evitar falsos distintos.
    for col in df.columns:
        if df[col].dtype == object:
            df[col] = df[col].map(lambda x: x.strip() if isinstance(x, str) else x)

    source_rows = len(df)
    duplicated_rows = int(df.duplicated(keep="first").sum())
    if duplicated_rows:
        logging.warning("Se detectaron %s filas completamente duplicadas; se conservará una copia.", duplicated_rows)
        df = df.drop_duplicates(keep="first").copy()

    # Convertir campos para validación.
    df["EstadoSeparacion_norm"] = df["EstadoSeparacion"].str.upper()
    df["EstadoCuota_norm"] = df["EstadoCuota"].str.upper()
    df["FechaVencimiento_dt"] = pd.to_datetime(
        df["FechaVencimiento"], format="%d/%m/%Y", errors="coerce"
    )
    df["Monto_num"] = pd.to_numeric(df["Monto"], errors="coerce")
    df["NumeroCuota_num"] = pd.to_numeric(df["NumeroCuota"], errors="coerce")

    required_nonempty = [
        "SeparacionId", "EstadoSeparacion", "Proyecto", "Manzana", "Lote",
        "Cliente", "Asesor", "NumeroCuota", "FechaVencimiento", "Monto", "EstadoCuota",
    ]
    blank_required = df[required_nonempty].isna().any(axis=1)
    for col in required_nonempty:
        blank_required |= df[col].astype(str).str.strip().eq("")

    invalid_date = df["FechaVencimiento_dt"].isna()
    invalid_amount = df["Monto_num"].isna() | (df["Monto_num"] <= 0)
    invalid_installment = (
        df["NumeroCuota_num"].isna()
        | (df["NumeroCuota_num"] <= 0)
        | (df["NumeroCuota_num"] % 1 != 0)
    )
    invalid_separation_status = ~df["EstadoSeparacion_norm"].isin(["VIGENTE", "ANULADA"])
    invalid_installment_status = ~df["EstadoCuota_norm"].isin(["PENDIENTE", "PAGADA"])

    invalid_mask = (
        blank_required | invalid_date | invalid_amount | invalid_installment
        | invalid_separation_status | invalid_installment_status
    )

    # Evitar procesar claves repetidas con datos contradictorios.
    key_duplicate = df.duplicated(subset=["SeparacionId", "NumeroCuota"], keep=False)
    conflict_keys = int(df.loc[key_duplicate, ["SeparacionId", "NumeroCuota"]].drop_duplicates().shape[0])
    if key_duplicate.any():
        logging.error(
            "Se encontraron %s claves SeparacionId + NumeroCuota repetidas después de quitar duplicados exactos; se excluirán.",
            conflict_keys,
        )
        invalid_mask |= key_duplicate

    invalid_count = int(invalid_mask.sum())
    if invalid_count:
        logging.warning("Se excluirán %s registros con datos obligatorios inválidos o claves repetidas.", invalid_count)

    valid = df.loc[~invalid_mask].copy()
    valid["NumeroCuota_num"] = valid["NumeroCuota_num"].astype(int)

    # El correo es opcional para generar el Excel, pero necesario para abrir borradores de Gmail.
    missing_email_rows = 0
    if "EmailAsesor" in valid.columns:
        missing_email_mask = valid["EmailAsesor"].isna() | valid["EmailAsesor"].astype(str).str.strip().eq("")
        missing_email_rows = int(missing_email_mask.sum())
        missing_emails = valid.loc[missing_email_mask, "Asesor"].drop_duplicates().tolist()
        if missing_emails:
            logging.warning(
                "EmailAsesor está vacío en %s registros. Asesores afectados: %s",
                missing_email_rows, ", ".join(missing_emails)
            )
    else:
        missing_emails = []
        logging.warning("El CSV no contiene EmailAsesor; no se podrán abrir borradores de Gmail.")

    stats = {
        "filas_originales": source_rows,
        "duplicados_exactos": duplicated_rows,
        "filas_invalidas": invalid_count,
        "filas_validas": len(valid),
        "separaciones_anuladas": int((valid["EstadoSeparacion_norm"] == "ANULADA").sum()),
        "cuotas_pagadas": int((valid["EstadoCuota_norm"] == "PAGADA").sum()),
        "filas_sin_correo_asesor": missing_email_rows,
        "asesores_sin_correo": len(missing_emails),
    }
    return valid, missing_emails, stats


def build_report(df: pd.DataFrame, cutoff: pd.Timestamp, output_path: Path) -> dict[str, object]:
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

    return {
        "cuotas_vencidas": len(overdue),
        "asesores": len(advisors),
        "totales_por_asesor": totals,
        "total_general": float(overdue["Monto_num"].sum()),
    }


def main() -> int:
    args = parse_args()
    base_dir = Path(__file__).resolve().parent
    configure_logging(base_dir)
    today = pd.Timestamp(date.today())

    if args.fecha_corte is None:
        try:
            fecha_corte = input(
                f"Ingresa la fecha de corte (DD/MM/AAAA; Enter = {today:%d/%m/%Y}): "
            ).strip()
        except EOFError:
            logging.error(
                "No se puede solicitar la fecha en esta consola. Ejecuta main.py desde una terminal interactiva."
            )
            return 2
    else:
        fecha_corte = args.fecha_corte.strip()

    if not fecha_corte:
        cutoff = today
        logging.info("No se ingresó fecha de corte. Se utilizará la fecha de hoy: %s", today.date())
    else:
        try:
            cutoff = pd.to_datetime(fecha_corte, format="%d/%m/%Y", errors="raise")
        except ValueError:
            cutoff = today
            logging.warning(
                "Fecha de corte inválida. Se utilizará la fecha de hoy: %s",
                today.date(),
            )

    csv_path = Path(args.archivo)
    if not csv_path.is_absolute():
        csv_path = base_dir / csv_path
    output_path = Path(args.salida)
    if not output_path.is_absolute():
        output_path = base_dir / output_path
    output_path = output_path.with_name(
        f"{output_path.stem}_{today:%Y%m%d}{output_path.suffix}"
    )

    try:
        logging.info("Inicio del proceso. Fecha de corte: %s", cutoff.date())
        valid, missing_emails, stats = load_and_validate(csv_path)
        logging.info("Validación: %s", stats)
        report = build_report(valid, cutoff, output_path)
        logging.info("Resultado: %s", report)
        if missing_emails:
            logging.warning(
                "No se abrirán borradores para estos asesores porque falta EmailAsesor: %s",
                ", ".join(missing_emails),
            )
        if "EmailAsesor" in valid.columns:
            emails = valid["EmailAsesor"].dropna().astype(str).str.strip()
            recipients = emails[emails.ne("")].tolist()
        else:
            recipients = []
        recipient_count = open_gmail_draft(recipients)
        logging.info("Borrador de Gmail abierto con %s destinatarios.", recipient_count)
        logging.info("Proceso finalizado correctamente. Archivo generado: %s", output_path)
        return 0
    except (FileNotFoundError, PermissionError, ValueError, pd.errors.ParserError) as exc:
        logging.exception("No se pudo completar el proceso: %s", exc)
        return 1
    except Exception as exc:  # Última barrera para registrar errores inesperados.
        logging.exception("Error inesperado: %s", exc)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
