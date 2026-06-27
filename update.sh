#!/usr/bin/env bash
# Synchronise les nouveaux podcasts (aperçus audio) du notebook NotebookLM vers
# le dépôt GitHub Pages, régénère le flux RSS et pousse.
# Idempotent : ne télécharge que les artefacts audio absents de episodes.json.
set -euo pipefail

REPO="$HOME/notebooklm-podcasts"
cd "$REPO"

NB="$(python3 -c 'import json;print(json.load(open("feed_config.json"))["notebook_id"])')"
NLM="$(command -v notebooklm || echo "$HOME/.local/bin/notebooklm")"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sync notebook $NB"

# Liste des artefacts audio prêts
ARTI_JSON="$("$NLM" artifact list -n "$NB" --json 2>/dev/null)"

python3 - "$ARTI_JSON" <<'PY'
import json, os, subprocess, sys
arti = json.loads(sys.argv[1])
eps = json.load(open("episodes.json")) if os.path.exists("episodes.json") else []
known = {e["id"] for e in eps}
nlm = os.path.expanduser("~/.local/bin/notebooklm")
if not os.path.exists(nlm):
    nlm = subprocess.run(["bash","-lc","command -v notebooklm"],capture_output=True,text=True).stdout.strip() or "notebooklm"
nb = json.load(open("feed_config.json"))["notebook_id"]
added = 0
for a in arti.get("artifacts", []):
    if a.get("type_id") != "audio" or a.get("status") != "completed":
        continue
    aid = a["id"]
    if aid in known:
        continue
    dest = f"audio/{aid}.mp3"
    print(f"  + nouveau podcast: {a['title']}  ({aid})")
    # download by exact title to a temp path then move
    tmp = f"audio/_dl_{aid}.mp3"
    r = subprocess.run([nlm,"download","audio","--name",a["title"],"-n",nb,tmp],
                       capture_output=True,text=True)
    src = tmp
    if not os.path.exists(src):
        # fallback: certains CLI écrivent un nom par défaut ; tenter le dernier .mp3 créé hors audio/
        print("    (téléchargement par nom échoué, tentative --name sans chemin)", r.stderr[:200])
        continue
    os.replace(src, dest)
    eps.append({
        "id": aid,
        "title": a["title"],
        "file": dest,
        "pubDate": a.get("created_at",""),
        "description": f"Aperçu audio NotebookLM — {a['title']}.",
    })
    added += 1
json.dump(eps, open("episodes.json","w"), ensure_ascii=False, indent=2)
print(f"  {added} nouvel(eaux) épisode(s) ajouté(s).")
PY

python3 build_feed.py

if [[ -n "$(git status --porcelain)" ]]; then
  git add -A
  git commit -m "Mise à jour du flux podcast ($(date '+%Y-%m-%d %H:%M'))" >/dev/null
  git push origin main
  echo "Poussé sur GitHub Pages."
else
  echo "Aucun changement."
fi
