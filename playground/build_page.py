#!/usr/bin/env python3
"""
Assemble the playground site.

Inlines bootstrap.sql and every file in queries/ into page_template.html, then
copies the Parquet export and the vendored DuckDB engine alongside it.

The default output is ../docs/playground, because GitHub Pages can serve the
/docs folder of the main branch with no build step, no Actions workflow and no
gh-pages branch. Pass another directory as the first argument to build elsewhere:

    python build_page.py                 -> ../docs/playground
    python build_page.py site            -> ./site   (for local testing)
"""
import glob
import json
import os
import pathlib
import shutil
import sys

OUT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "../docs/playground")
TEMPLATE = pathlib.Path("page_template.html")

if not pathlib.Path("parquet").is_dir():
    sys.exit("no parquet/ directory. Run export_parquet.py first.")
if not pathlib.Path("vendor/duckdb-eh.wasm").is_file():
    sys.exit("no vendor/duckdb-eh.wasm. Run: npm install && npm run vendor")

bootstrap = pathlib.Path("bootstrap.sql").read_text()
files = sorted(glob.glob("parquet/*.parquet"))
names = ["data/" + os.path.basename(f) for f in files]

queries = []
for p in sorted(glob.glob("queries/*.sql")):
    stem = os.path.basename(p)[:-4]
    label = stem.split("_", 1)[1].replace("_", " ")
    queries.append({"id": stem, "label": f"{stem.split('_')[0]}. {label}",
                    "sql": pathlib.Path(p).read_text().rstrip()})

html = TEMPLATE.read_text()
html = html.replace("/*__BOOTSTRAP__*/'x'", json.dumps(bootstrap))
html = html.replace("/*__FILES__*/[]", json.dumps(names))
html = html.replace("/*__QUERIES__*/[]", json.dumps(queries, indent=2))

OUT.mkdir(parents=True, exist_ok=True)
(OUT / "index.html").write_text(html)

# GitHub Pages runs Jekyll by default, which ignores files and folders whose
# names begin with an underscore and adds a build step this site does not need.
# An empty .nojekyll turns that off and serves the directory as it is.
(OUT / ".nojekyll").write_text("")

shutil.rmtree(OUT / "data", ignore_errors=True)
(OUT / "data").mkdir()
for f in files:
    shutil.copy(f, OUT / "data" / os.path.basename(f))

shutil.rmtree(OUT / "vendor", ignore_errors=True)
shutil.copytree("vendor", OUT / "vendor")

data_mb = sum(os.path.getsize(f) for f in files) / 1048576
vendor_mb = sum(os.path.getsize(os.path.join(dp, f))
                for dp, _, fs in os.walk(OUT / "vendor") for f in fs) / 1048576

print(f"built {OUT}")
print(f"  index.html   {os.path.getsize(OUT / 'index.html') // 1024} kB")
print(f"  vendor/      {vendor_mb:.1f} MB   (DuckDB compiled to WebAssembly)")
print(f"  data/        {len(files)} files, {data_mb:.1f} MB")
print(f"  total        {(data_mb + vendor_mb):.1f} MB")
