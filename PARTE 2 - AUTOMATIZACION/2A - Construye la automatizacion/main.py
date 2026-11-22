#!/usr/bin/env python3
"""Genera un Excel con cuotas vencidas agrupadas por asesor."""

from __future__ import annotations

import argparse
import logging
import sys
from datetime import datetime
from pathlib import Path

import pandas as pd

from data_loader import load_and_validate
from excel_opener import open_excel_report
from gmail_drafts import open_gmail_draft
from report_generator import build_report


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


def main() -> int:
    args = parse_args()
    base_dir = Path(__file__).resolve().parent
    configure_logging(base_dir)
    run_started = datetime.now()
    today = pd.Timestamp(run_started.date())

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
        f"{output_path.stem}_{run_started:%Y%m%d_%H%M%S_%f}{output_path.suffix}"
    )

    try:
        logging.info("Inicio del proceso. Fecha de corte: %s", cutoff.date())
        valid, missing_emails, stats = load_and_validate(csv_path)
        logging.info("Validación: %s", stats)
        report, output_path = build_report(valid, cutoff, output_path)
        logging.info("Resultado: %s", report)
        open_excel_report(output_path)
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
