# Deploying the playground on GitHub

Step by step, on Windows, from a built `hmda` database to a live URL anyone can open.

Every step says what it does and how to tell it worked. **Run one block at a time** and check the result before moving on. If a step fails, stop there and look at section 12 rather than carrying on.

Time: about 40 minutes, most of it waiting for the first push.

---

## What you are about to build

| | |
|---|---|
| Output | A static website: one HTML file, the DuckDB engine as WebAssembly, and your model as Parquet |
| Where it lives | The `docs/playground/` folder of your repository |
| How it is served | GitHub Pages, built into GitHub, no Actions workflow and no second branch |
| Size added to the repository | About 100 MB |
| Cost | Nothing, forever, as long as the repository is public |

**The repository has to be public.** GitHub Pages on a private repository needs a paid plan. If the repository is private, Pages will either refuse or serve a 404 with no useful error.

---

## 1. Check what you already have

Open **PowerShell** (not Command Prompt). Run each line on its own and read the answer.

```powershell
psql --version
```

Expect something like `psql (PostgreSQL) 18.x`. If it says "not recognized", add it for this window:

```powershell
$env:Path += ";C:\Program Files\PostgreSQL\18\bin"
```

That lasts only for this PowerShell window, which is fine, but it means **every step below has to run in this same window**. If you close it, run that line again.

```powershell
python --version
```

Expect `Python 3.something`. If it opens the Microsoft Store instead, Python is not properly installed: get it from [python.org](https://www.python.org/downloads/) and tick **Add python.exe to PATH** on the first screen of the installer.

```powershell
node --version
```

Expect `v20.x` or higher. If it is missing, install it from [nodejs.org](https://nodejs.org/download).

The page offers two builds. **Take the one marked LTS**, which at the time of writing is v24 and carries the codename Krypton. The other is marked **Current** (v26) and is where new features land before they are considered stable, so it is the wrong choice for a build you want to still work next year. Codenames are just release nicknames and mean nothing for this.

Pick the Windows Installer, `.msi`, **x64**, accept the defaults, then **close PowerShell and open a new one** so it picks up the new PATH.

Node is needed once, to bundle the database engine into a single file. It is not needed to run the site, and nobody visiting your playground needs it.

---

## 2. Install the one Python package

```powershell
pip install duckdb --break-system-packages
```

If that flag causes an error on your Python, drop it:

```powershell
pip install duckdb
```

Check it:

```powershell
python -c "import duckdb; print(duckdb.__version__)"
```

Any version from 0.10 upwards is fine. This is the tool that converts your tables to Parquet. It is not the same thing as the browser engine, which comes from npm in step 6.

---

## 3. Put the playground folder in your project

Unpack `playground_source.tar.gz` so that your project looks like this:

```
hmda-ny\
  migrations\
  seed\
  docs\
  playground\          <- new
    bootstrap.sql
    build_page.py
    export_parquet.py
    package.json
    page_template.html
    parity_test.py
    vendor_entry.js
    README.md
    queries\
      01_denial_by_year.sql ... 10_reconciliation.sql
```

Now move into it. Use your own path if it differs:

```powershell
cd $HOME\projects\hmda-ny\playground
```

Check you are in the right place:

```powershell
dir
```

You should see `export_parquet.py` and a `queries` folder. If not, you are in the wrong directory and nothing below will work.

---

## 4. Tell the scripts how to reach your database

Set your real PostgreSQL password. Replace the text inside the quotes with it, do not paste the line as it stands:

```powershell
$env:PGPASSWORD = 'REPLACE-WITH-YOUR-REAL-PASSWORD'
```

**Why the password goes in a variable.** The export runs `psql` nineteen times. Without `PGPASSWORD` each one stops and waits for you to type the password, and a script cannot type it for you.

The scripts already default to `localhost`, port **5432**, user `postgres`, database `hmda`, which is what a standard PostgreSQL installer gives you. **Do not set `PGPORT` unless you know your server is on a different port.** Setting it to a port nothing is listening on is the single most common way this step fails.

Confirm the connection before doing any work:

```powershell
psql -U postgres -d hmda -c "SELECT count(*) FROM marts.fct_application;"
```

You should get `1754846`. That one command proves the password, the port, the database name and the model all at once, and it takes a second.

If it says `could not connect to server`, find out which port your server is actually on:

```powershell
psql -U postgres -l
```

If that works, you are on the default 5432 and you should clear any override you have set in this window:

```powershell
Remove-Item Env:PGPORT
```

---

## 5. Export the model to Parquet

```powershell
python export_parquet.py
```

This takes about two minutes. It dumps each table to a temporary CSV, reads it back with the column types taken from your database rather than guessed, writes a compressed Parquet file, and deletes the CSV.

Expected output, ending with these lines:

```
fct_application_2022                22,838 kB
fct_application_2023                16,148 kB
fct_application_2024                15,831 kB
fct_application_2025                17,646 kB
total                                   82 MB

type fidelity check: action_taken IN ('1','3') matched 283,192 rows
```

**About one institution name.** Four rows of `dim_institution`, all the same Puerto Rican credit union, contain the Unicode replacement character, left over from an encoding problem in the publisher's own transmittal sheet. The export forces UTF8 so those rows come through rather than stopping the dump. They will show a replacement glyph in the playground, which is the honest representation of what the source file contains.

**Check two things before moving on.** The total should be about 82 MB. And the last line must say 283,192, which is the number of decided applications in 2024 in your PostgreSQL database. If it says 0, the code columns came back as numbers instead of text and every query in the browser would fail. Stop and see section 12.

---

## 6. Prove the browser will give the same answers

```powershell
python parity_test.py
```

This runs all ten published queries against PostgreSQL and against the Parquet you just wrote, and compares every cell.

```
  ok     01_denial_by_year.sql  (4 rows)
  ok     02_outcome_mix.sql  (8 rows)
  ...
  ok     10_reconciliation.sql  (1 rows)

all 10 queries return identical results in both engines
```

**This is the most important check in the whole deployment.** The two engines are not the same database, and they disagree in places where neither raises an error. [Phase 10 section 3](10_playground.md#3-the-bug-that-justifies-the-parity-test) has the example: one regex operator behaves differently and silently changed a published figure by 20 percent.

If any line says `DIFFER`, do not publish. The output names the query and the first row that disagrees.

---

## 7. Fetch and bundle the browser engine

Windows blocks PowerShell scripts by default, and `npm` on Windows is a PowerShell script. Allow scripts for this window only, before the first npm command:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

`-Scope Process` is the important part. It applies to this PowerShell window and nothing else, and it is gone the moment you close it. Nothing about the machine's security settings is changed permanently.

If you would rather not touch the policy at all, call the batch wrapper instead and skip the line above: `npm.cmd install` and `npm.cmd run vendor` do the same work without going through PowerShell.

```powershell
npm install
```

One to two minutes. It downloads DuckDB compiled to WebAssembly, pinned to version 1.28.0, plus the bundler. A `node_modules` folder appears, which is build tooling and is not committed.

```powershell
npm run vendor
```

Expect the bundle line, then a listing of exactly what it produced:

```
  vendor/duckdb-browser.mjs  212.8kb
vendor/ ready, duckdb-wasm 1.28.0
  duckdb-browser-eh.worker.js          260 kB
  duckdb-browser.mjs                   213 kB
  duckdb-eh.wasm                     17682 kB
```

**All three files must be there.** If you see only `duckdb-browser.mjs`, the copy step did not run and the page will not start. That listing is printed precisely so a partial vendor folder is obvious rather than discovered later in the browser.

**Why bundle at all.** The published engine imports a library by name, and a browser cannot resolve a bare name like that. The bundler flattens the engine and its dependency into one file the browser can load directly. The version is pinned because from 1.29.0 the Parquet reader became a separate download from an external server, which would put a run-time dependency on someone else's uptime into your portfolio.

---

## 7b. Build the data dictionary

One command, two seconds, no dependencies beyond `psql`:

```powershell
cd ..\catalog
```

```powershell
python build_catalog.py
```

```
built ../docs/catalog/index.html  91 kB
  22 objects, 239 columns (175 on tables, 100% documented)
  26 indexes, 53 constraints
```

**If it reports less than 100 percent**, it also names the columns with no `COMMENT ON`. Add them to `migrations/009_comments.sql`, re-run that migration, and build again. An undocumented column should be a number you can see, not something nobody notices.

```powershell
cd ..\playground
```

---

## 8. Build the site

```powershell
python build_page.py
```

```
built ..\docs\playground
  index.html   24 kB
  vendor/      17.7 MB   (DuckDB compiled to WebAssembly)
  data/        19 files, 82.2 MB
  total        99.9 MB
```

It writes into `docs\playground` because GitHub Pages can serve the `docs` folder of your main branch directly, with no build step and no second branch. That is the simplest Pages setup there is.

It also writes an empty `.nojekyll` file. GitHub Pages runs a site generator called Jekyll by default; that file turns it off, which is both faster and avoids Jekyll quietly ignoring files.

---

## 9. Test it on your own machine before anyone else sees it

```powershell
cd ..\docs\playground
```

```powershell
python -m http.server 8000
```

Leave that running. Open a browser at:

```
http://localhost:8000/
```

You should see the page, a green dot, and "Ready. 1,754,846 rows, 15 tables, in this tab." within a few seconds, with the first query's results already on screen:

| activity_year | decided | denial_pct |
|---|---|---|
| 2022 | 400,563 | 23.29 |
| 2023 | 277,970 | 26.94 |
| 2024 | 283,192 | 26.26 |
| 2025 | 309,119 | 24.87 |

**Work through the dropdown.** All ten should run, the slowest in about 1.6 seconds. Then type your own query into the box and press Ctrl+Enter.

**There is one SQL box, not ten.** The dropdown loads a query's text into it. Typing over that text changes only what is in the browser's memory for this page view: the page never writes back to `playground/queries/*.sql`, so nothing in the repository can be overwritten by using the playground. Pick another query from the list, or reload the page, and the original comes back. The page says as much under the box, so a reviewer knows they can experiment freely.

**The local server is for you, not for them.** `python -m http.server` exists here only so you can see the site before publishing it. GitHub Pages is itself the web server, so a reviewer opens the URL and that is the whole interaction: no Python, no PostgreSQL, no downloads, no account.

It does have to be a server rather than a double-clicked file, even locally. Browsers block JavaScript modules and Web Workers on `file://` URLs for security reasons, and this page needs both. Over `http://localhost` or over the `https://` that Pages provides, they work normally.

When you are done, press **Ctrl+C** in PowerShell to stop the server, then:

```powershell
cd ..\..\playground
```

If the page sits on "Starting the database engine" forever, press **F12** in the browser and read the Console tab. Section 12 has the two errors you are likely to see.

---

## 10. Commit it

Move to the top of the project:

```powershell
cd ..
```

If this is not a git repository yet:

```powershell
git init -b main
```

First time using git on this machine, set who you are:

```powershell
git config --global user.name "Samuel Babajide"
```

```powershell
git config --global user.email "samuelbabajideb@gmail.com"
```

Check what git is about to include:

```powershell
git status --short
```

**Read this list.** You should see `docs/`, `migrations/`, `playground/`, `seed/`, `README.md` and the rest. You should **not** see `playground/node_modules/`, `playground/parquet/` or any 200 MB CSV. The `.gitignore` in the repository root excludes them. If you see them anyway, the `.gitignore` file is missing or in the wrong folder, and committing 700 MB of CSV to GitHub is a mistake that is genuinely annoying to undo.

```powershell
git add .
```

```powershell
git commit -m "HMDA New York 2022-2025: model, analysis and browser playground"
```

Confirm the size of what you are about to push:

```powershell
git count-objects -vH
```

`size-pack` should be somewhere around 100 MB. Much more than that means something unwanted got in.

---

## 11. Push it to GitHub and turn Pages on

### 11.1 Create the repository

On [github.com](https://github.com), click **New repository**.

- Name: `hmda-ny`
- **Public**, which is required for free Pages
- Do **not** tick "Add a README", "Add .gitignore" or "Choose a license". You already have those, and adding them here creates a conflict on your first push.

### 11.2 Connect and push

Use your own username:

```powershell
git remote add origin https://github.com/YOUR-USERNAME/hmda-ny.git
```

```powershell
git push -u origin main
```

**This push moves about 100 MB and will take several minutes.** It looks stalled at "Writing objects" for a long time. Leave it.

On authentication: GitHub stopped accepting account passwords here. When it asks, a browser window usually opens for you to approve. If instead it asks for a password in the terminal, you need a personal access token: GitHub → your avatar → **Settings** → **Developer settings** → **Personal access tokens** → **Tokens (classic)** → **Generate new token**, tick the `repo` scope, and paste the token where it asks for a password. If any of that goes wrong, [GitHub Desktop](https://desktop.github.com/) handles the whole thing with a button and works on the repository you just made.

### 11.3 Enable Pages

In your repository on GitHub:

1. **Settings** (the tab, not your account settings)
2. **Pages** in the left sidebar
3. Under **Build and deployment**, Source: **Deploy from a branch**
4. Branch: **main**, folder: **/docs**
5. **Save**

A banner appears with your site address. The first build takes one to three minutes. The **Actions** tab shows a "pages build and deployment" job; wait for its green tick.

### 11.4 Open it

```
https://YOUR-USERNAME.github.io/hmda-ny/playground/
```

**The trailing slash matters.** Without it some browsers request `/playground` as a file, get a redirect, and the relative paths to `data/` and `vendor/` resolve one level too high.

Expect a longer wait than on your own machine, because the browser is now downloading about 100 MB. On a normal connection it is ready in 20 to 40 seconds. After the first visit the browser caches it.

---

## 12. When something goes wrong

| what you see | what it means | what to do |
|---|---|---|
| `psql: not recognized` | PostgreSQL's tools are not on this window's PATH | Re-run the `$env:Path` line from section 1, in this window |
| `npm.ps1 cannot be loaded because running scripts is disabled on this system` | Windows blocks PowerShell scripts by default and npm is one | `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` in this window, or use `npm.cmd install` instead |
| `password authentication failed` | `PGPASSWORD` is wrong or not set in this window | Set it again; each new PowerShell window starts empty |
| `Could not talk to PostgreSQL` naming a port that is not 5432 | You set `PGPORT` when you did not need to | `Remove-Item Env:PGPORT`, then re-run. Confirm with `psql -U postgres -l` |
| `byte sequence 0xef 0xbf 0xbd ... has no equivalent in encoding "WIN1252"` | psql is writing the CSV in your console's codepage, and four institution names contain a character WIN1252 cannot represent | You are on an older `export_parquet.py`. The current one forces UTF8 itself. As a one-off you can also set `$env:PGCLIENTENCODING = "UTF8"` before running it |
| `type fidelity check ... matched 0 rows` | Codes were exported as numbers instead of text | Confirm the export ran against the real `hmda` database, then check `SELECT data_type FROM information_schema.columns WHERE table_name='fct_application' AND column_name='action_taken'` returns `text` |
| `parity_test.py` says `DIFFER` | A query returns different answers in the two engines | Do not publish. The output names the query and the first disagreeing row. Phase 10 section 3 explains the two known causes |
| `no parquet/ directory` | Step 5 has not run, or you are in the wrong folder | `cd` into `playground` and run `python export_parquet.py` |
| `No files found that match the pattern "data/fct_application_2022.parquet"` | An older `parity_test.py` looked for the files under `data/`, where they only exist after the site is built | Use the current `parity_test.py`, which reads them from `parquet/` |
| `no vendor/duckdb-eh.wasm` | Step 7 has not run | `npm install` then `npm run vendor` |
| Page stuck on "Starting the database engine" | The engine files did not load | Press F12, open Console. `404 ... vendor/...` means `vendor/` was not committed; check `git status`. `MIME type` errors mean you opened the file directly instead of through a server |
| `table index is out of bounds` | A newer DuckDB build is trying to download a Parquet extension | You changed the pinned version. Put `"@duckdb/duckdb-wasm": "1.28.0"` back in `package.json`, delete `node_modules`, and repeat step 7 |
| Pages shows 404 after the green tick | Wrong folder setting, missing trailing slash, or a private repository | Check Settings → Pages says **main** and **/docs**; add the trailing slash; make the repository public |
| Push hangs for minutes at "Writing objects" | Normal for 100 MB | Wait. If it fails, `git push` again; git resumes rather than restarting from nothing |

---

## 13. Finish the job

Two small things that are easy to forget and look careless if you skip them.

**Put the real link in the README.** Open `README.md` and replace every `YOUR-USERNAME` with your GitHub username. There are two, including the playground link at the top, which is the first thing anyone clicks.

```powershell
git add README.md
```

```powershell
git commit -m "Point the playground link at the published site"
```

```powershell
git push
```

**Add the link to the repository header.** On GitHub, next to **About** on the right of your repository page, click the gear and paste the playground URL into the **Website** field. It then shows next to your repository name everywhere it appears.

---

## 14. Updating it later

How much work an update is depends entirely on what changed.

| what changed | what you run | what gets pushed | time |
|---|---|---|---|
| A phase document, the README, anything in `docs/` | nothing, just commit | a few kB | seconds |
| Page wording, layout or colours (`page_template.html`) | `python build_page.py` | ~24 kB, just `index.html` | under a minute |
| A published query, or a new one in `queries/` | `python parity_test.py` then `python build_page.py` | ~24 kB | about two minutes |
| The model itself: a migration changed, or a new year loaded | `python export_parquet.py`, then the two above | only the Parquet files that genuinely changed | about five minutes |

Then in every case:

```powershell
git add -A ; git commit -m "what changed" ; git push
```

GitHub Pages redeploys on its own within a minute or two. **The URL never changes**, so any link you have already put on a CV or in a message keeps working.

### Why most updates cost almost nothing

`build_page.py` rewrites the whole `docs/playground` folder every time, including all 82 MB of `data/`. That sounds expensive and is not, because git tracks content rather than timestamps, and the export is deterministic: re-running `export_parquet.py` against an unchanged database produces **byte-identical Parquet**, verified across all nineteen files. Git sees no change and stores nothing new, so a wording tweak on the page really does push 24 kB.

That determinism is the same property the phase 06 key design was built for, showing up somewhere it was not designed for.

One caveat worth knowing rather than discovering. The export has no `ORDER BY`, so it depends on PostgreSQL returning rows in their physical order, which is stable for a static table but not guaranteed after a `VACUUM FULL` or a reload. If you ever see all nineteen files change when the data did not, that is the cause, and adding an `ORDER BY` to the dump in `export_parquet.py` fixes it permanently.

### The one genuine cost

When data really does change, git keeps the old version forever. Re-exporting after a full model rebuild can add up to 82 MB to the repository's history, and that space is never reclaimed by a later commit. Two or three rebuilds are fine. Twenty would make the repository unpleasant to clone.

So: rebuild the model as often as you like locally, and re-export only when you intend to publish the result.

### Adding a fifth year

Loading 2026 later takes three steps rather than two. Add the partition in `003_fact.sql` and load it as the runbook describes, add `2026` to the year list in `export_parquet.py`, and add one line to `bootstrap.sql`:

```sql
'data/fct_application_2026.parquet',
```

`build_page.py` finds the new Parquet file on its own, but `bootstrap.sql` lists the fact files explicitly, because DuckDB in the browser cannot glob over HTTP. Phase 10 section 7 explains why.

### The habit worth keeping

**Never push a build where `parity_test.py` did not pass.** The value of the playground is that its numbers are the documented numbers. A build that quietly disagrees with the analysis is worse than no playground at all.
