#!/usr/bin/env python3
"""Génère un fichier RSS par flux défini dans feeds.json.
- Config globale (base_url, author) : feed_config.json
- Liste des flux : feeds.json (slug, notebook_id, title, description, output, audio_dir, episodes, cover)
- État par flux : <episodes>.json (liste d'épisodes {id,title,file,pubDate,description})
"""
import json, os, subprocess, sys
from datetime import datetime, timezone
from email.utils import format_datetime
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.abspath(__file__))

def load(name, default=None):
    p = os.path.join(ROOT, name)
    if not os.path.exists(p):
        return default
    with open(p, encoding="utf-8") as f:
        return json.load(f)

def ffprobe_duration(path):
    try:
        out = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration",
             "-of", "default=noprint_wrappers=1:nokey=1", path],
            capture_output=True, text=True, timeout=30)
        secs = int(float(out.stdout.strip()))
        return f"{secs//3600:02d}:{(secs%3600)//60:02d}:{secs%60:02d}"
    except Exception:
        return "00:00:00"

def rfc2822(iso):
    try:
        dt = datetime.fromisoformat(iso)
    except Exception:
        dt = datetime.now()
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return format_datetime(dt)

def build_one(feed, base, author):
    episodes = load(feed["episodes"], []) or []
    episodes = sorted(episodes, key=lambda e: e.get("pubDate", ""), reverse=True)
    items = []
    for e in episodes:
        fpath = os.path.join(ROOT, e["file"])
        if not os.path.exists(fpath):
            continue
        size = os.path.getsize(fpath)
        dur = ffprobe_duration(fpath)
        url = f"{base}/{e['file']}"
        items.append(f"""    <item>
      <title>{escape(e['title'])}</title>
      <description>{escape(e.get('description',''))}</description>
      <itunes:summary>{escape(e.get('description',''))}</itunes:summary>
      <pubDate>{rfc2822(e.get('pubDate',''))}</pubDate>
      <enclosure url="{escape(url)}" length="{size}" type="audio/mpeg"/>
      <guid isPermaLink="false">{escape(e['id'])}</guid>
      <itunes:duration>{dur}</itunes:duration>
      <itunes:explicit>false</itunes:explicit>
    </item>""")

    title = escape(feed.get("title", "NotebookLM"))
    desc = escape(feed.get("description", ""))
    cover = feed.get("cover", "")
    cover_url = f"{base}/{cover}" if cover and os.path.exists(os.path.join(ROOT, cover)) else ""
    cover_tag = f'\n    <itunes:image href="{escape(cover_url)}"/>' if cover_url else ""
    img_block = (f"""\n    <image>
      <url>{escape(cover_url)}</url>
      <title>{title}</title>
      <link>{escape(base)}/</link>
    </image>""" if cover_url else "")
    now = format_datetime(datetime.now(timezone.utc))

    feed_xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>{title}</title>
    <link>{escape(base)}/</link>
    <language>fr-CA</language>
    <description>{desc}</description>
    <itunes:author>{escape(author)}</itunes:author>
    <itunes:summary>{desc}</itunes:summary>
    <itunes:explicit>false</itunes:explicit>
    <itunes:category text="Education"/>
    <lastBuildDate>{now}</lastBuildDate>{cover_tag}{img_block}
{chr(10).join(items)}
  </channel>
</rss>
"""
    with open(os.path.join(ROOT, feed["output"]), "w", encoding="utf-8") as f:
        f.write(feed_xml)
    return len(items)

def main():
    cfg = load("feed_config.json") or {}
    base = cfg.get("base_url", "").rstrip("/")
    author = cfg.get("author", "Isabelle Larouche")
    if not base:
        print("ERREUR: base_url manquant dans feed_config.json", file=sys.stderr); sys.exit(1)
    feeds = load("feeds.json", [])
    for feed in feeds:
        n = build_one(feed, base, author)
        print(f"  {feed['output']:24s} — {n} épisode(s)")

if __name__ == "__main__":
    main()
