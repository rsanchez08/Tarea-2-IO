"""Convierte informe_tecnico.md en un HTML autocontenido listo para imprimir a PDF."""
import base64, pathlib, re, markdown

src = pathlib.Path("informe_tecnico.md").read_text(encoding="utf-8")

# incrustar imagenes como data URI
def embed(m):
    alt, path = m.group(1), m.group(2)
    data = base64.b64encode(pathlib.Path(path).read_bytes()).decode()
    return f'![{alt}](data:image/png;base64,{data})'
src = re.sub(r'!\[([^\]]*)\]\(([^)]+\.png)\)', embed, src)

body = markdown.markdown(src, extensions=["tables", "fenced_code", "toc", "sane_lists"])

html = f"""<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<title>Informe M/M/1 - Caja de la cafeteria</title>
<style>
  :root {{ --ink:#1a202c; --muted:#4a5568; --line:#cbd5e0; --accent:#2b6cb0; --bg-soft:#f7fafc; }}
  * {{ box-sizing:border-box; }}
  body {{ font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;
         color:var(--ink); line-height:1.55; max-width:820px; margin:2.2rem auto;
         padding:0 1.4rem; font-size:15px; }}
  h1 {{ font-size:1.7rem; line-height:1.25; border-bottom:3px solid var(--accent);
        padding-bottom:.35rem; margin-top:0; }}
  h2 {{ font-size:1.28rem; margin-top:2.4rem; border-bottom:1px solid var(--line);
        padding-bottom:.2rem; }}
  h3 {{ font-size:1.05rem; color:var(--muted); margin-top:1.6rem; }}
  table {{ border-collapse:collapse; width:100%; margin:1rem 0; font-size:13.5px; }}
  th,td {{ border:1px solid var(--line); padding:.4rem .55rem; text-align:left;
           vertical-align:top; }}
  thead th {{ background:var(--bg-soft); }}
  tbody tr:nth-child(even) {{ background:#fbfcfe; }}
  code {{ background:var(--bg-soft); padding:.1rem .3rem; border-radius:3px;
          font-size:.9em; }}
  pre {{ background:#1e293b; color:#e2e8f0; padding:1rem; border-radius:6px;
         overflow-x:auto; font-size:12.5px; line-height:1.45; }}
  pre code {{ background:none; color:inherit; padding:0; }}
  img {{ max-width:100%; height:auto; display:block; margin:1rem auto;
         border:1px solid var(--line); border-radius:4px; }}
  blockquote {{ border-left:4px solid var(--accent); margin:1rem 0; padding:.3rem 1rem;
                background:var(--bg-soft); color:var(--muted); }}
  hr {{ border:none; border-top:1px solid var(--line); margin:2rem 0; }}
  em {{ color:var(--muted); }}
  @media print {{
    body {{ max-width:none; margin:0; font-size:11pt; }}
    h1 {{ font-size:18pt; }} h2 {{ font-size:14pt; page-break-after:avoid; }}
    h3 {{ page-break-after:avoid; }}
    table,pre,img,blockquote {{ page-break-inside:avoid; }}
    pre {{ white-space:pre-wrap; word-wrap:break-word; }}
  }}
</style>
</head>
<body>
{body}
</body>
</html>
"""
pathlib.Path("informe_tecnico.html").write_text(html, encoding="utf-8")
kb = len(html.encode()) / 1024
print(f"informe_tecnico.html generado ({kb:.0f} KB, imagenes incrustadas)")
print("Abrir en el navegador y usar  Imprimir -> Guardar como PDF.")
