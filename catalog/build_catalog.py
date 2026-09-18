#!/usr/bin/env python3
"""
Generate the data dictionary at docs/catalog/index.html from the live
PostgreSQL catalogue.

Nothing here is hand-written. Every table, column, type, key, index, check
and description is read from pg_catalog at build time, which means the
published dictionary cannot describe a column that no longer exists. The
prose comes from COMMENT ON statements in migrations/009_comments.sql, so
the documentation is versioned with the DDL rather than in a wiki.

Output is one self-contained HTML file of about 120 kB with no external
assets, so it works from GitHub Pages, from a file:// URL and offline.

Usage:  python3 build_catalog.py [output_dir]      default ../docs/catalog
"""
import html
import json
import os
import pathlib
import subprocess
import sys

PG = dict(host=os.environ.get("PGHOST", "localhost"),
          port=os.environ.get("PGPORT", "5432"),
          user=os.environ.get("PGUSER", "postgres"),
          db=os.environ.get("PGDATABASE", "hmda"))
ENV = {**os.environ, "PGCLIENTENCODING": "UTF8"}

SCHEMAS = ("marts", "ref")

# Display title. Kept separate from the database name, which is "hmda" and
# means nothing to a reader arriving from the README.
TITLE = "US HMDA Data Dictionary"

# Objects are grouped in the sidebar by what they are, not alphabetically,
# because "which table is the fact table" is the first question a reader has.
def group_of(name, kind):
    if kind == "v":
        return "Views"
    if name.startswith("fct_"):
        return "Fact"
    if name.startswith("dim_"):
        return "Dimensions"
    if name.startswith("br_"):
        return "Bridges"
    if name.startswith("quarantine"):
        return "Fact"
    return "Reference"


GROUP_ORDER = ["Fact", "Dimensions", "Bridges", "Reference", "Views"]


def human(n):
    """Format bytes the way pg_size_pretty does, for the summed partition total."""
    for unit, step in (("bytes", 1), ("kB", 1024), ("MB", 1024 ** 2), ("GB", 1024 ** 3)):
        if n < step * 1024 or unit == "GB":
            return f"{n} bytes" if unit == "bytes" else f"{round(n / step)} {unit}"
    return f"{n} bytes"


def q(sql):
    """Run a query and return a list of dicts.

    Results come back as JSON rather than delimited text. A delimited read
    looked simpler and broke on the first value containing a newline, which
    silently produced a short row rather than an error. JSON has no delimiter
    to collide with.
    """
    wrapped = f"SELECT coalesce(json_agg(t), '[]'::json) FROM ({sql}) t"
    out = subprocess.run(
        ["psql", "-h", PG["host"], "-p", PG["port"], "-U", PG["user"], "-d", PG["db"],
         "-X", "-A", "-t", "-q", "-v", "ON_ERROR_STOP=1", "-c", wrapped],
        capture_output=True, text=True, env=ENV)
    if out.returncode != 0:
        sys.exit(f"\npsql failed:\n{out.stderr.strip()}\n")
    return json.loads(out.stdout)


def collect():
    schema_list = ",".join(f"'{s}'" for s in SCHEMAS)
    # Every column is aliased, because json_agg names the keys and an
    # unaliased expression would arrive as "?column?".
    live = f"""n.nspname IN ({schema_list})
               AND NOT EXISTS (SELECT 1 FROM pg_inherits i WHERE i.inhrelid = c.oid)"""

    # Partition children are excluded here and listed under their parent
    # instead: a reader cares about fct_application, not fct_application_2023.
    rels = q(f"""
        SELECT n.nspname AS schema, c.relname AS name, c.relkind AS kind,
               coalesce(obj_description(c.oid), '') AS comment,
               pg_size_pretty(pg_total_relation_size(c.oid)) AS size,
               pg_total_relation_size(c.oid) AS bytes
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE {live} AND c.relkind IN ('r','p','v')
        ORDER BY 1, 2""")

    cols = q(f"""
        SELECT n.nspname AS schema, c.relname AS rel, a.attnum AS n, a.attname AS name,
               format_type(a.atttypid, a.atttypmod) AS type,
               CASE WHEN a.attnotnull THEN 'NO' ELSE 'YES' END AS nullable,
               coalesce(pg_get_expr(d.adbin, d.adrelid), '') AS "default",
               coalesce(col_description(c.oid, a.attnum), '') AS comment
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
        LEFT JOIN pg_attrdef d ON d.adrelid = c.oid AND d.adnum = a.attnum
        WHERE {live} AND c.relkind IN ('r','p','v')
        ORDER BY 1, 2, 3""")

    cons = q(f"""
        SELECT n.nspname AS schema, c.relname AS rel, con.conname AS name,
               CASE con.contype WHEN 'p' THEN 'PRIMARY KEY' WHEN 'f' THEN 'FOREIGN KEY'
                                WHEN 'u' THEN 'UNIQUE'      WHEN 'c' THEN 'CHECK'
                                ELSE con.contype::text END AS type,
               pg_get_constraintdef(con.oid) AS definition,
               coalesce(array_to_string(ARRAY(
                 SELECT a.attname FROM unnest(con.conkey) k
                 JOIN pg_attribute a ON a.attrelid = con.conrelid AND a.attnum = k), ','), '')
                 AS columns,
               coalesce(fn.nspname || '.' || fc.relname, '') AS target
        FROM pg_constraint con
        JOIN pg_class c ON c.oid = con.conrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        LEFT JOIN pg_class fc ON fc.oid = con.confrelid
        LEFT JOIN pg_namespace fn ON fn.oid = fc.relnamespace
        WHERE {live}
        ORDER BY 1, 2, con.contype, 3""")

    idx = q(f"""
        SELECT n.nspname AS schema, c.relname AS rel, i.relname AS name,
               pg_get_indexdef(x.indexrelid) AS definition,
               pg_size_pretty(pg_relation_size(i.oid)) AS size,
               x.indisunique AS unique,
               (x.indpred IS NOT NULL) AS partial
        FROM pg_index x
        JOIN pg_class c ON c.oid = x.indrelid
        JOIN pg_class i ON i.oid = x.indexrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE {live}
        ORDER BY 1, 2, pg_relation_size(i.oid) DESC""")

    parts = q(f"""
        SELECT pn.nspname AS schema, p.relname AS parent, ch.relname AS name,
               pg_get_expr(ch.relpartbound, ch.oid) AS bound,
               pg_size_pretty(pg_total_relation_size(ch.oid)) AS size,
               pg_total_relation_size(ch.oid) AS bytes
        FROM pg_inherits i
        JOIN pg_class p ON p.oid = i.inhparent
        JOIN pg_namespace pn ON pn.oid = p.relnamespace
        JOIN pg_class ch ON ch.oid = i.inhrelid
        WHERE pn.nspname IN ({schema_list})
        ORDER BY 3""")

    viewdefs = q(f"""
        SELECT n.nspname AS schema, c.relname AS name,
               pg_get_viewdef(c.oid, true) AS definition
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname IN ({schema_list}) AND c.relkind = 'v'""")

    objects = {}
    for r in rels:
        key = f"{r['schema']}.{r['name']}"
        objects[key] = dict(schema=r["schema"], name=r["name"], kind=r["kind"],
                            comment=r["comment"], size=r["size"], bytes=r["bytes"],
                            group=group_of(r["name"], r["kind"]),
                            columns=[], constraints=[], indexes=[], partitions=[],
                            referenced_by=[], rows=None, viewdef="")

    for c in cols:
        key = f"{c['schema']}.{c['rel']}"
        if key in objects:
            objects[key]["columns"].append(dict(
                n=c["n"], name=c["name"], type=c["type"], nullable=c["nullable"],
                default=c["default"], comment=c["comment"], keys=[], fk=[]))

    for c in cons:
        key = f"{c['schema']}.{c['rel']}"
        if key not in objects:
            continue
        objects[key]["constraints"].append(dict(
            name=c["name"], type=c["type"], definition=c["definition"],
            columns=c["columns"], target=c["target"]))
        members = [m for m in c["columns"].split(",") if m]
        for col in objects[key]["columns"]:
            if col["name"] not in members:
                continue
            if c["type"] == "PRIMARY KEY" and "PK" not in col["keys"]:
                col["keys"].append("PK")
            elif c["type"] == "FOREIGN KEY":
                if "FK" not in col["keys"]:
                    col["keys"].append("FK")
                if c["target"] and c["target"] not in col["fk"]:
                    col["fk"].append(c["target"])
            elif c["type"] == "UNIQUE" and "UQ" not in col["keys"]:
                col["keys"].append("UQ")
        if c["type"] == "FOREIGN KEY" and c["target"] in objects:
            objects[c["target"]]["referenced_by"].append(
                dict(table=key, columns=c["columns"]))

    for i in idx:
        key = f"{i['schema']}.{i['rel']}"
        if key in objects:
            objects[key]["indexes"].append(dict(
                name=i["name"], definition=i["definition"], size=i["size"],
                unique=bool(i["unique"]), partial=bool(i["partial"])))

    for p in parts:
        key = f"{p['schema']}.{p['parent']}"
        if key in objects:
            objects[key]["partitions"].append(
                dict(name=p["name"], bound=p["bound"], size=p["size"],
                     bytes=p["bytes"]))

    # pg_total_relation_size on a partitioned parent is 0, because the parent
    # holds no rows. Reporting that would say the fact table is empty, so the
    # children are summed instead.
    for obj in objects.values():
        if obj["partitions"]:
            total = sum(x["bytes"] for x in obj["partitions"])
            obj["bytes"] = total
            obj["size"] = human(total)

    for v in viewdefs:
        key = f"{v['schema']}.{v['name']}"
        if key in objects:
            objects[key]["viewdef"] = v["definition"]

    # Exact counts. Fifteen tables, so accuracy beats reltuples estimates.
    for key, obj in objects.items():
        if obj["kind"] in ("r", "p"):
            obj["rows"] = q(f"SELECT count(*) AS n FROM {key}")[0]["n"]

    return objects


PAGE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>__TITLE__</title>
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns=%27http://www.w3.org/2000/svg%27 viewBox=%270 0 32 32%27%3E%3Ctext y=%2726%27 font-size=%2728%27%3E%F0%9F%93%97%3C/text%3E%3C/svg%3E">
<style>
  :root {
    --bg:#fbfaf8; --panel:#fff; --ink:#1c1b19; --muted:#6b6862; --line:#e3e0da;
    --accent:#8a5a2b; --soft:#f2ece4; --code:#f6f4f0; --ok:#2f6b45; --warn:#9b6a2c;
    --mono:ui-monospace,SFMono-Regular,"SF Mono",Menlo,Consolas,monospace;
    --sans:ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;
  }
  @media (prefers-color-scheme:dark){:root:not([data-theme=light]){
    --bg:#171614; --panel:#1f1e1b; --ink:#ece9e3; --muted:#9c978e; --line:#322f2a;
    --accent:#d9a468; --soft:#2a2520; --code:#232120; --ok:#7fbf96; --warn:#d6a464;}}
  :root[data-theme=dark]{
    --bg:#171614; --panel:#1f1e1b; --ink:#ece9e3; --muted:#9c978e; --line:#322f2a;
    --accent:#d9a468; --soft:#2a2520; --code:#232120; --ok:#7fbf96; --warn:#d6a464;}
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.6 var(--sans);
       -webkit-text-size-adjust:100%}
  a{color:var(--accent)}
  .layout{display:flex;min-height:100vh;align-items:flex-start}
  aside{width:280px;flex:none;border-right:1px solid var(--line);padding:20px 0 40px;
        position:sticky;top:0;max-height:100vh;overflow-y:auto;background:var(--panel)}
  aside h1{font-size:0.95rem;margin:0 16px 4px;letter-spacing:-0.01em}
  aside .sub{font-size:0.78rem;color:var(--muted);margin:0 16px 14px}
  .search{margin:0 16px 14px}
  .search input{width:100%;font:inherit;font-size:0.88rem;color:var(--ink);
    background:var(--bg);border:1px solid var(--line);border-radius:7px;padding:7px 10px}
  .grp{font-size:0.7rem;letter-spacing:0.08em;text-transform:uppercase;color:var(--muted);
       margin:16px 16px 4px;font-weight:600}
  nav a{display:block;padding:5px 16px;font-size:0.86rem;text-decoration:none;color:var(--ink);
        font-family:var(--mono);border-left:3px solid transparent;white-space:nowrap;
        overflow:hidden;text-overflow:ellipsis}
  nav a:hover{background:var(--soft)}
  nav a.on{background:var(--soft);border-left-color:var(--accent);font-weight:600}
  nav a .cnt{float:right;color:var(--muted);font-size:0.75rem;font-family:var(--sans)}
  main{flex:1;min-width:0;padding:28px 28px 80px;max-width:1100px}
  .topbar{display:flex;gap:10px;align-items:center;margin-bottom:22px;flex-wrap:wrap}
  .topbar .spacer{flex:1}
  button{font:inherit;font-size:0.85rem;color:var(--ink);background:var(--panel);
    border:1px solid var(--line);border-radius:7px;padding:6px 11px;cursor:pointer}
  h2{font-size:1.5rem;margin:0 0 6px;font-family:var(--mono);letter-spacing:-0.02em}
  h2.title{font-family:var(--sans);font-weight:700;letter-spacing:-0.01em}
  h2 .sch{color:var(--muted);font-weight:400}
  .desc{margin:0 0 16px;color:var(--ink);max-width:78ch}
  .facts{display:flex;flex-wrap:wrap;gap:8px;margin-bottom:22px}
  .fact{background:var(--soft);border:1px solid var(--line);border-radius:7px;
        padding:6px 11px;font-size:0.8rem}
  .fact b{font-variant-numeric:tabular-nums}
  h3{font-size:0.95rem;margin:26px 0 8px;padding-bottom:5px;border-bottom:1px solid var(--line)}
  h3 .n{color:var(--muted);font-weight:400;font-size:0.85rem}
  .scroller{overflow-x:auto;border:1px solid var(--line);border-radius:9px;background:var(--panel)}
  table{border-collapse:collapse;width:100%;font-size:0.84rem}
  th,td{text-align:left;padding:7px 11px;border-bottom:1px solid var(--line);vertical-align:top}
  th{background:var(--soft);font-weight:600;font-size:0.76rem;letter-spacing:0.04em;
     text-transform:uppercase;white-space:nowrap}
  tr:last-child td{border-bottom:0}
  td.mono,th.mono{font-family:var(--mono);font-size:0.8rem;white-space:nowrap}
  td.cmt{font-size:0.82rem;color:var(--muted);min-width:22ch;white-space:normal}
  td.num{text-align:right;font-variant-numeric:tabular-nums;font-family:var(--mono)}
  .badge{display:inline-block;font-size:0.65rem;font-weight:700;letter-spacing:0.05em;
    padding:1px 5px;border-radius:4px;margin-right:3px;font-family:var(--sans)}
  .b-pk{background:var(--accent);color:#fff}
  .b-fk{background:var(--soft);color:var(--accent);border:1px solid var(--accent)}
  .b-uq{background:var(--soft);color:var(--muted);border:1px solid var(--line)}
  .b-nn{background:transparent;color:var(--muted);border:1px solid var(--line)}
  .fklink{display:block;font-size:0.78rem;font-family:var(--mono);margin-top:2px}
  pre{margin:0;font:12px/1.5 var(--mono);white-space:pre-wrap;word-break:break-word}
  .def{background:var(--code);border:1px solid var(--line);border-radius:9px;padding:12px 14px;
       overflow-x:auto}
  .empty{color:var(--muted);font-size:0.85rem;padding:10px 0}
  .hits{font-size:0.82rem;color:var(--muted);margin:0 0 14px}
  .hit{display:block;padding:6px 0;border-bottom:1px solid var(--line);text-decoration:none;color:var(--ink)}
  .hit b{font-family:var(--mono);font-size:0.85rem}
  .hit span{color:var(--muted);font-size:0.8rem}
  @media (max-width:820px){
    .layout{display:block}
    aside{width:auto;position:static;max-height:none;border-right:0;border-bottom:1px solid var(--line)}
    main{padding:20px 16px 60px}
    nav{display:flex;flex-wrap:wrap;gap:4px;padding:0 12px}
    nav a{border-left:0;border:1px solid var(--line);border-radius:6px;padding:4px 8px;font-size:0.8rem}
    nav a .cnt{display:none}
    .grp{width:100%;margin:12px 16px 2px}
  }
</style>
</head>
<body>
<div class="layout">
  <aside>
    <h1>__DBNAME__</h1>
    <p class="sub">__SUBTITLE__</p>
    <div class="search"><input id="q" type="search" placeholder="Search tables and columns" autocomplete="off"></div>
    <nav id="nav"></nav>
  </aside>
  <main>
    <div class="topbar">
      <div class="spacer"></div>
      <button id="theme">Theme</button>
    </div>
    <div id="body"></div>
  </main>
</div>
<script>
const DATA = __DATA__;
const META = __META__;
const GROUPS = __GROUPS__;

const $ = id => document.getElementById(id);
const esc = s => String(s == null ? '' : s).replace(/[&<>"]/g, c =>
  ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const num = n => Number(n).toLocaleString();

$('theme').onclick = () => {
  const now = document.documentElement.getAttribute('data-theme');
  const next = now === 'dark' ? 'light' : now === 'light' ? 'dark'
    : (matchMedia('(prefers-color-scheme: dark)').matches ? 'light' : 'dark');
  document.documentElement.setAttribute('data-theme', next);
  try { localStorage.setItem('cat-theme', next); } catch (e) {}
};
try { const s = localStorage.getItem('cat-theme');
      if (s) document.documentElement.setAttribute('data-theme', s); } catch (e) {}

function buildNav(filter) {
  const f = (filter || '').toLowerCase();
  let out = '';
  for (const g of GROUPS) {
    const items = Object.keys(DATA)
      .filter(k => DATA[k].group === g)
      .filter(k => !f || k.toLowerCase().includes(f)
                || DATA[k].columns.some(c => c.name.toLowerCase().includes(f)))
      .sort();
    if (!items.length) continue;
    out += `<div class="grp">${esc(g)}</div>`;
    for (const k of items) {
      const o = DATA[k];
      out += `<a href="#${esc(k)}" data-k="${esc(k)}">${esc(o.name)}`
           + `<span class="cnt">${o.columns.length}</span></a>`;
    }
  }
  $('nav').innerHTML = out || '<div class="grp">no match</div>';
  mark();
}

function mark() {
  const cur = location.hash.slice(1);
  document.querySelectorAll('#nav a').forEach(a =>
    a.classList.toggle('on', a.dataset.k === cur));
}

function colRow(c) {
  const badges = c.keys.map(k =>
    `<span class="badge b-${k.toLowerCase()}">${k}</span>`).join('')
    + (c.nullable === 'NO' ? '<span class="badge b-nn">NOT NULL</span>' : '');
  const fk = (c.fk || []).map(t =>
    `<a class="fklink" href="#${esc(t)}">&rarr; ${esc(t)}</a>`).join('');
  return `<tr>
    <td class="num">${c.n}</td>
    <td class="mono"><b>${esc(c.name)}</b></td>
    <td class="mono">${esc(c.type)}</td>
    <td>${badges}${fk}</td>
    <td class="mono">${esc(c.default)}</td>
    <td class="cmt">${esc(c.comment)}</td></tr>`;
}

function section(title, count, inner) {
  return `<h3>${esc(title)} <span class="n">${count}</span></h3>` + inner;
}

function render(key) {
  const o = DATA[key];
  if (!o) { renderIndex(); return; }
  let h = `<h2><span class="sch">${esc(o.schema)}.</span>${esc(o.name)}</h2>`;
  if (o.comment) h += `<p class="desc">${esc(o.comment)}</p>`;

  const facts = [];
  facts.push(`<span class="fact">${o.kind === 'v' ? 'view'
              : o.kind === 'p' ? 'partitioned table' : 'table'}</span>`);
  if (o.rows !== null) facts.push(`<span class="fact">rows <b>${num(o.rows)}</b></span>`);
  facts.push(`<span class="fact">columns <b>${o.columns.length}</b></span>`);
  if (o.kind !== 'v') facts.push(`<span class="fact">size <b>${esc(o.size)}</b></span>`);
  if (o.partitions.length) facts.push(`<span class="fact">partitions <b>${o.partitions.length}</b></span>`);
  h += `<div class="facts">${facts.join('')}</div>`;

  h += section('Columns', o.columns.length,
    `<div class="scroller"><table><thead><tr>
      <th>#</th><th>Column</th><th>Type</th><th>Keys</th><th>Default</th><th>Description</th>
     </tr></thead><tbody>${o.columns.map(colRow).join('')}</tbody></table></div>`);

  if (o.constraints.length) {
    h += section('Constraints', o.constraints.length,
      `<div class="scroller"><table><thead><tr>
        <th>Name</th><th>Type</th><th>Definition</th></tr></thead><tbody>` +
      o.constraints.map(c => `<tr><td class="mono">${esc(c.name)}</td>
        <td>${esc(c.type)}</td><td class="mono" style="white-space:normal">${esc(c.definition)}</td></tr>`).join('') +
      `</tbody></table></div>`);
  }

  if (o.indexes.length) {
    h += section('Indexes', o.indexes.length,
      `<div class="scroller"><table><thead><tr>
        <th>Name</th><th>Size</th><th>Unique</th><th>Partial</th><th>Definition</th>
       </tr></thead><tbody>` +
      o.indexes.map(i => `<tr><td class="mono">${esc(i.name)}</td>
        <td class="num">${esc(i.size)}</td><td>${i.unique ? 'yes' : ''}</td>
        <td>${i.partial ? 'yes' : ''}</td>
        <td class="mono" style="white-space:normal">${esc(i.definition)}</td></tr>`).join('') +
      `</tbody></table></div>`);
  }

  if (o.partitions.length) {
    h += section('Partitions', o.partitions.length,
      `<div class="scroller"><table><thead><tr>
        <th>Name</th><th>Bound</th><th>Size</th></tr></thead><tbody>` +
      o.partitions.map(p => `<tr><td class="mono">${esc(p.name)}</td>
        <td class="mono">${esc(p.bound)}</td><td class="num">${esc(p.size)}</td></tr>`).join('') +
      `</tbody></table></div>`);
  }

  if (o.referenced_by.length) {
    h += section('Referenced by', o.referenced_by.length,
      `<div class="scroller"><table><thead><tr>
        <th>Table</th><th>Columns</th></tr></thead><tbody>` +
      o.referenced_by.map(r => `<tr><td class="mono"><a href="#${esc(r.table)}">${esc(r.table)}</a></td>
        <td class="mono">${esc(r.columns)}</td></tr>`).join('') +
      `</tbody></table></div>`);
  }

  if (o.viewdef) {
    h += section('Definition', '', `<div class="def"><pre>${esc(o.viewdef)}</pre></div>`);
  }

  $('body').innerHTML = h;
  window.scrollTo(0, 0);
  mark();
}

function renderIndex() {
  let h = `<h2 class="title">${esc(META.db)}</h2><p class="desc">${esc(META.blurb)}</p>`;
  h += `<div class="facts">
      <span class="fact">objects <b>${num(META.objects)}</b></span>
      <span class="fact">columns <b>${num(META.columns)}</b></span>
      <span class="fact">rows <b>${num(META.rows)}</b></span>
      <span class="fact">indexes <b>${num(META.indexes)}</b></span>
      <span class="fact">constraints <b>${num(META.constraints)}</b></span>
      <span class="fact">table columns documented <b>${META.documented}%</b></span>
    </div>`;
  for (const g of GROUPS) {
    const items = Object.keys(DATA).filter(k => DATA[k].group === g).sort();
    if (!items.length) continue;
    h += section(g, items.length, `<div class="scroller"><table><thead><tr>
        <th>Object</th><th>Rows</th><th>Cols</th><th>Size</th><th>Description</th>
      </tr></thead><tbody>` +
      items.map(k => { const o = DATA[k]; return `<tr>
        <td class="mono"><a href="#${esc(k)}">${esc(o.name)}</a></td>
        <td class="num">${o.rows === null ? '' : num(o.rows)}</td>
        <td class="num">${o.columns.length}</td>
        <td class="num">${o.kind === 'v' ? '' : esc(o.size)}</td>
        <td class="cmt">${esc(o.comment)}</td></tr>`; }).join('') +
      `</tbody></table></div>`);
  }
  $('body').innerHTML = h;
  mark();
}

function renderSearch(term) {
  const f = term.toLowerCase();
  const hits = [];
  for (const k of Object.keys(DATA).sort()) {
    for (const c of DATA[k].columns) {
      if (c.name.toLowerCase().includes(f)) {
        hits.push(`<a class="hit" href="#${esc(k)}"><b>${esc(k)}.${esc(c.name)}</b>
          <span>${esc(c.type)}${c.comment ? ' &middot; ' + esc(c.comment.slice(0, 110)) : ''}</span></a>`);
      }
    }
  }
  $('body').innerHTML = `<h2>Columns matching &ldquo;${esc(term)}&rdquo;</h2>`
    + `<p class="hits">${hits.length} column${hits.length === 1 ? '' : 's'} across the model.</p>`
    + (hits.join('') || '<p class="empty">Nothing matched.</p>');
}

$('q').addEventListener('input', e => {
  const v = e.target.value.trim();
  buildNav(v);
  if (v.length >= 2) renderSearch(v);
  else if (location.hash.length > 1) render(location.hash.slice(1));
  else renderIndex();
});

addEventListener('hashchange', () => {
  $('q').value = '';
  buildNav('');
  location.hash.length > 1 ? render(location.hash.slice(1)) : renderIndex();
});

buildNav('');
location.hash.length > 1 ? render(location.hash.slice(1)) : renderIndex();
</script>
</body>
</html>
"""


def main():
    out_dir = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "../docs/catalog")
    objects = collect()

    total_cols = sum(len(o["columns"]) for o in objects.values())
    # Coverage is measured over TABLE columns. A view column inherits its
    # meaning from the column it selects, so requiring a separate comment
    # there would mean maintaining the same sentence twice.
    table_cols = sum(len(o["columns"]) for o in objects.values() if o["kind"] != "v")
    documented = sum(1 for o in objects.values() if o["kind"] != "v"
                     for c in o["columns"] if c["comment"])
    meta = dict(
        db=TITLE,
        objects=len(objects),
        columns=total_cols,
        rows=sum(o["rows"] or 0 for o in objects.values() if o["kind"] != "v"),
        indexes=sum(len(o["indexes"]) for o in objects.values()),
        constraints=sum(len(o["constraints"]) for o in objects.values()),
        documented=round(100 * documented / table_cols) if table_cols else 0,
        blurb=("Generated from the PostgreSQL catalogue, so it cannot describe a column "
               "that no longer exists. The prose comes from COMMENT ON statements in "
               "migrations/009_comments.sql, which means the documentation is versioned "
               "with the DDL. Pick an object on the left, or type a column name to find "
               "every table that has it."),
    )

    page = (PAGE
            .replace("__TITLE__", TITLE)
            .replace("__DBNAME__", html.escape(TITLE))
            .replace("__SUBTITLE__", f"{len(objects)} objects, {total_cols} columns")
            .replace("__DATA__", json.dumps(objects, separators=(",", ":")))
            .replace("__META__", json.dumps(meta, separators=(",", ":")))
            .replace("__GROUPS__", json.dumps(GROUP_ORDER)))

    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "index.html").write_text(page, encoding="utf-8")
    (out_dir / ".nojekyll").write_text("")

    size_kb = os.path.getsize(out_dir / "index.html") // 1024
    print(f"built {out_dir}/index.html  {size_kb} kB")
    print(f"  {len(objects)} objects, {total_cols} columns "
          f"({table_cols} on tables, {meta['documented']}% documented)")
    print(f"  {meta['indexes']} indexes, {meta['constraints']} constraints")
    undoc = [f"{k}.{c['name']}" for k, o in objects.items()
             for c in o["columns"] if not c["comment"] and o["kind"] != "v"]
    if undoc:
        print(f"\n  {len(undoc)} table columns have no COMMENT ON, for example:")
        for name in undoc[:8]:
            print(f"    {name}")


if __name__ == "__main__":
    main()
