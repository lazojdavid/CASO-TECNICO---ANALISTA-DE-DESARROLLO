"""Abre el reporte Excel generado con la aplicación predeterminada de Windows."""

from __future__ import annotations

import logging
import os
from pathlib import Path


def open_excel_report(report_path: Path) -> None:
    if not report_path.is_file():
        raise FileNotFoundError(f"No se encontró el reporte para abrir: {report_path}")

    os.startfile(str(report_path))
    logging.info("Se abrió el reporte Excel: %s", report_path)
