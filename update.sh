#!/usr/bin/env bash
# Synchronise les nouveaux podcasts (aperçus audio) du notebook NotebookLM vers
# le dépôt GitHub Pages, régénère le flux RSS et pousse.
# Idempotent : ne télécharge que les artefacts audio absents de episodes.json.
set -euo pipefail

# PATH complet (cron/launchd ont un PATH minimal)
export PATH="/opt/homebrew/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

REPO="$HOME/notebooklm-podcasts"
cd "$REPO"

TOKEN_FILE="$HOME/.config/notebooklm-podcasts/gh_token"
NB="$(python3 -c 'import json;print(json.load(open("feed_config.json"))["notebook_id"])')"
NLM="$(command -v notebooklm || echo "$HOME/.local/bin/notebooklm")"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sync notebook $NB"

# Liste des artefacts audio prêts
ARTI_JSON="$("$NLM" artifact list -n "$NB" --json 2>/dev/null)"

python3 - "$ARTI_JSON" "$NB" "$NLM" <<'PY'
import json, os, subprocess, sys
arti = json.loads(sys.argv[1]); nb = sys.argv[2]; nlm = sys.argv[3]
eps = json.load(open("episodes.json")) if os.path.exists("episodes.json") else []
known = {e["id"] for e in eps}
added = 0
for a in arti.get("artifacts", []):
    if a.get("type_id") != "audio" or a.get("status") != "completed":
        continue
    aid = a["id"]
    if aid in known:
        continue
    dest = f"audio/{aid}.mp3"
    tmp = f"audio/_dl_{aid}.mp3"
    print(f"  + nouveau podcast: {a['title']} ({aid})")
    subprocess.run([nlm,"download","audio","--name",a["title"],"-n",nb,tmp],
                   capture_output=True,text=True)
    if not os.path.exists(tmp):
        print("    !! téléchargement échoué, ignoré pour ce run")
        continue
    os.replace(tmp, dest)
    eps.append({
        "id": aid,
        "title": a["title"],
        "file": dest,
        "pubDate": a.get("created_at",""),
        "description": f"Aperçu audio NotebookLM — {a['title']}.",
    })
    added += 1
json.dump(eps, open("episodes.json","w"), ensure_ascii=False, indent=2)
print(f"  {added} nouvel(eaux) épisode(s).")
PY

python3 build_feed.py

if [[ -n "$(git status --porcelain)" ]]; then
  git add -A
  git commit -q -m "Mise à jour du flux podcast ($(date '+%Y-%m-%d %H:%M'))"
  # Push avec le jeton (helper d'identifiants en ligne, sans stocker le secret dans .git/config)
  git -c credential.helper='!f(){ echo username=x-access-token; echo "password=$(cat '"$TOKEN_FILE"')"; }; f' \
      push origin main
  echo "Poussé sur GitHub Pages."
else
  echo "Aucun changement."
fi
