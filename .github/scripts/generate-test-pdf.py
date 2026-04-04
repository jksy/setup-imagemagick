#!/usr/bin/env python3

from pathlib import Path
import sys


def main() -> int:
    output = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("input.pdf")

    lines = [
        b"%PDF-1.4\n",
        b"1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n",
        b"2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n",
        b"3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>\nendobj\n",
        b"4 0 obj\n<< /Length 37 >>\nstream\nBT /F1 24 Tf 30 100 Td (Hello PDF) Tj ET\nendstream\nendobj\n",
        b"5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n",
    ]

    body = bytearray()
    offsets = [0]
    for chunk in lines[1:]:
        offsets.append(len(body) + len(lines[0]))
        body.extend(chunk)

    xref_start = len(lines[0]) + len(body)
    xref = [b"xref\n0 6\n", b"0000000000 65535 f \n"]
    for offset in offsets[1:]:
        xref.append(f"{offset:010d} 00000 n \n".encode())

    trailer = (
        b"trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n"
        + str(xref_start).encode()
        + b"\n%%EOF\n"
    )

    output.write_bytes(lines[0] + body + b"".join(xref) + trailer)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
