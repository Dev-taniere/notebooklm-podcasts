#!/usr/bin/env bash
# Crée un podcast NotebookLM pour N'IMPORTE QUEL sujet et le publie dans un flux.
# Pipeline complet : génère l'aperçu audio -> attend -> télécharge -> ajoute au flux
# -> régénère les RSS -> pousse sur GitHub Pages -> archive le MP3 dans Dropbox.
# JAMAIS de podcast sur le Bureau : archive = ~/Dropbox/_TANIÈRE/TANIÈRE_ISABELLE/Podcasts
#
# Usage :
#   nouveau-podcast.sh --notebook <NOTEBOOK_ID> --feed <slug> --desc "<consigne>" \
#        [--format deep-dive|brief|critique|debate] [--length short|default|long] \
#        [--title "<titre affiché dans le flux>"]
#
# Flux (slug) disponibles : voir feeds.json (audiovisuel, daily-musique, daily-tech, apprentissage).
# Le slug doit exister dans feeds.json. Pour un nouveau flux, l'ajouter d'abord (voir SKILL.md).
set -euo pipefail
export PATH="/opt/homebrew/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

REPO="$HOME/notebooklm-podcasts"; cd "$REPO"
NLM="$(command -v notebooklm || echo "$HOME/.local/bin/notebooklm")"
TOKEN_FILE="$HOME/.config/notebooklm-podcasts/gh_token"
ARCHIVE="$HOME/Dropbox/_TANIÈRE/TANIÈRE_ISABELLE/Podcasts"

FORMAT="deep-dive"; LENGTH="long"; TITLE=""; NB=""; SLUG=""; DESC=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --notebook) NB="$2"; shift 2;;
    --feed) SLUG="$2"; shift 2;;
    --desc) DESC="$2"; shift 2;;
    --format) FORMAT="$2"; shift 2;;
    --length) LENGTH="$2"; shift 2;;
    --title) TITLE="$2"; shift 2;;
    *) echo "Argument inconnu: $1"; exit 1;;
  esac
done
[[ -z "$NB" || -z "$SLUG" || -z "$DESC" ]] && { echo "Requis: --notebook --feed --desc"; exit 1; }

# Récupérer la config du flux
read -r ADIR EPF < <(python3 -c "
import json,sys
f=next((x for x in json.load(open('feeds.json')) if x['slug']=='$SLUG'),None)
if not f: sys.exit('Flux inconnu: $SLUG (voir feeds.json)')
print(f['audio_dir'], f['episodes'])")
mkdir -p "$ADIR"

echo "[1/5] Génération de l'aperçu audio (format=$FORMAT, length=$LENGTH)…"
"$NLM" generate audio "$DESC" -n "$NB" --format "$FORMAT" --length "$LENGTH" --language fr --no-wait >/dev/null

echo "[2/5] Attente de la fin de génération (peut prendre 5-15 min)…"
for i in $(seq 1 60); do
  read -r AID ASTATUS ATITLE < <("$NLM" artifact list -n "$NB" --json 2>/dev/null | python3 -c '
import sys,json
d=json.load(sys.stdin); a=[x for x in d.get("artifacts",[]) if x.get("type_id")=="audio"]
a.sort(key=lambda x:x.get("created_at",""),reverse=True)
print(a[0]["id"], a[0].get("status","?"), a[0].get("title","")) if a else print("- none -")')
  echo "   …statut=$ASTATUS"
  [[ "$ASTATUS" == "completed" ]] && break
  [[ "$ASTATUS" == "failed" ]] && { echo "ÉCHEC de génération."; exit 2; }
  sleep 20
done
[[ "$ASTATUS" != "completed" ]] && { echo "Délai dépassé."; exit 3; }
[[ -n "$TITLE" ]] || TITLE="$ATITLE"

echo "[3/5] Téléchargement du MP3…"
DEST="$ADIR/$AID.mp3"
"$NLM" download audio "$DEST" --name "$ATITLE" -n "$NB" >/dev/null
[[ -f "$DEST" ]] || { echo "Téléchargement échoué."; exit 4; }

echo "[4/5] Ajout au flux + archive Dropbox…"
python3 - "$EPF" "$DEST" "$AID" "$TITLE" "$ATITLE" "$SLUG" "$ARCHIVE" <<'PY'
import json,os,sys,shutil,re
epf,dest,aid,title,atitle,slug,archive=sys.argv[1:8]
eps=json.load(open(epf)) if os.path.exists(epf) else []
if aid not in {e["id"] for e in eps}:
    from datetime import datetime
    eps.append({"id":aid,"title":title,"file":dest,
                "pubDate":datetime.now().isoformat(timespec="seconds"),
                "description":f"{title}."})
    json.dump(eps,open(epf,"w"),ensure_ascii=False,indent=2)
os.makedirs(archive,exist_ok=True)
safe=lambda s: re.sub(r'[^\w\-]+','-',s).strip('-')[:80]
shutil.copy2(dest, os.path.join(archive, f"{safe(slug)}-{safe(atitle)}.mp3"))
print("   ajouté + archivé:", title)
PY

echo "[5/5] Build des flux + push GitHub Pages…"
python3 build_feed.py
git add -A
git commit -q -m "Nouveau podcast ($SLUG) : $TITLE"
git -c credential.helper='!f(){ echo username=x-access-token; echo "password=$(cat '"$TOKEN_FILE"')"; }; f' push origin main
echo "✅ Publié. Flux : https://dev-taniere.github.io/notebooklm-podcasts/$(python3 -c "import json;print(next(x['output'] for x in json.load(open('feeds.json')) if x['slug']=='$SLUG'))")"
