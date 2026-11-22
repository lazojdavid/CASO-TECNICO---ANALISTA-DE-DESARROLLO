"""Funciones para abrir borradores de Gmail."""

from __future__ import annotations

import logging
import webbrowser
from collections.abc import Iterable
from urllib.parse import urlencode


def open_gmail_draft(recipients: Iterable[str]) -> int:
    """Abre un borrador de Gmail con los destinatarios indicados en el campo Para."""
    unique_recipients: list[str] = []
    seen_recipients: set[str] = set()
    for recipient in recipients:
        normalized = recipient.strip()
        key = normalized.casefold()
        if normalized and key not in seen_recipients:
            unique_recipients.append(normalized)
            seen_recipients.add(key)

    if not unique_recipients:
        logging.warning("No se abrirá el borrador de Gmail: no hay destinatarios con EmailAsesor.")
        return 0

    query = urlencode({
        "view": "cm",
        "fs": "1",
        "to": ",".join(unique_recipients),
        "su": "Reporte de cuotas vencidas por asesor",
        "body": "Se envía un reporte separado para cada asesor.",
    })
    if not webbrowser.open(f"https://mail.google.com/mail/?{query}", new=2):
        raise RuntimeError("No se pudo abrir Gmail para crear el borrador.")

    logging.info("Se abrió un borrador de Gmail para %s destinatarios.", len(unique_recipients))
    return len(unique_recipients)
