#!/usr/bin/env bash
# Synchronise les nouveaux podcasts (aperçus audio) de TOUS les flux définis dans
# feeds.json (un notebook NotebookLM par flux) vers GitHub Pages, régénère les RSS
# et pousse. Idempotent : ne télécharge que les artefacts audio absents.
set -euo pipefail
export PATH="/opt/homebrew/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

REPO="$HOME/notebooklm-podcasts"
cd "$REPO"
TOKEN_FILE="$HOME/.config/notebooklm-podcasts/gh_token"
NLM="$(command -v notebooklm || echo "$HOME/.local/bin/notebooklm")"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sync multi-flux"

# Pour chaque flux : récupérer la liste d'artefacts audio et télécharger les nouveaux
python3 - "$NLM" <<'PY'
import json, os, subprocess, sys
nlm = sys.argv[1]
feeds = json.load(open("feeds.json"))
for feed in feeds:
    nb = feed["notebook_id"]; epf = feed["episodes"]; adir = feed["audio_dir"]
    os.makedirs(adir, exist_ok=True)
    eps = json.load(open(epf)) if os.path.exists(epf) else []
    known = {e["id"] for e in eps}
    try:
        arti = json.loads(subprocess.run([nlm,"artifact","list","-n",nb,"--json"],
                                         capture_output=True,text=True).stdout)
    except Exception as ex:
        print(f"  [{feed['slug']}] erreur liste artefacts: {ex}"); continue
    added = 0
    for a in arti.get("artifacts", []):
        if a.get("type_id") != "audio" or a.get("status") != "completed":
            continue
        aid = a["id"]
        if aid in known:
            continue
        dest = f"{adir}/{aid}.mp3"; tmp = f"{adir}/_dl_{aid}.mp3"
        subprocess.run([nlm,"download","audio","--name",a["title"],"-n",nb,tmp],
                       capture_output=True,text=True)
        if not os.path.exists(tmp):
            print(f"  [{feed['slug']}] téléchargement échoué: {a['title']}"); continue
        os.replace(tmp, dest)
        eps.append({"id":aid,"title":a["title"],"file":dest,
                    "pubDate":a.get("created_at",""),
                    "description":f"{feed['title']} — {a['title']}."})
        added += 1
    json.dump(eps, open(epf,"w"), ensure_ascii=False, indent=2)
    print(f"  [{feed['slug']}] {added} nouvel(eaux) épisode(s).")
PY

python3 build_feed.py

if [[ -n "$(git status --porcelain)" ]]; then
  git add -A
  git commit -q -m "MAJ flux podcasts ($(date '+%Y-%m-%d %H:%M'))"
  git -c credential.helper='!f(){ echo username=x-access-token; echo "password=$(cat '"$TOKEN_FILE"')"; }; f' \
      push origin main
  echo "Poussé sur GitHub Pages."
else
  echo "Aucun changement."
fi
