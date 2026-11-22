"""Carga y valida la información de cuotas desde el archivo CSV."""

from __future__ import annotations

import logging
from pathlib import Path

import pandas as pd

REQUIRED_COLUMNS = [
    "SeparacionId", "EstadoSeparacion", "Proyecto", "Manzana", "Lote",
    "Cliente", "Asesor", "NumeroCuota", "FechaVencimiento", "Monto",
    "EstadoCuota",
]
OPTIONAL_COLUMNS = ["DocumentoCliente", "TelefonoCliente", "EmailAsesor", "FechaPago"]


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
