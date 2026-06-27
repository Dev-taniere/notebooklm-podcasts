#!/usr/bin/env python3
"""Génère feed.xml (RSS 2.0 + iTunes) à partir de episodes.json et des MP3 dans audio/.
Config lue depuis feed_config.json (base_url, title, author, ...)."""
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
        h, m, s = secs // 3600, (secs % 3600) // 60, secs % 60
        return f"{h:02d}:{m:02d}:{s:02d}", secs
    except Exception:
        return "00:00:00", 0

def rfc2822(iso):
    try:
        dt = datetime.fromisoformat(iso)
    except Exception:
        dt = datetime.now()
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return format_datetime(dt)

def main():
    cfg = load("feed_config.json")
    if not cfg or not cfg.get("base_url"):
        print("ERREUR: feed_config.json manquant ou base_url vide", file=sys.stderr)
        sys.exit(1)
    base = cfg["base_url"].rstrip("/")
    episodes = load("episodes.json", [])
    # tri du plus récent au plus ancien
    episodes = sorted(episodes, key=lambda e: e.get("pubDate", ""), reverse=True)

    items = []
    for e in episodes:
        fpath = os.path.join(ROOT, e["file"])
        if not os.path.exists(fpath):
            continue
        size = os.path.getsize(fpath)
        dur, _ = ffprobe_duration(fpath)
        url = f"{base}/{e['file']}"
        guid = e["id"]
        title = escape(e["title"])
        desc = escape(e.get("description", ""))
        pub = rfc2822(e.get("pubDate", ""))
        items.append(f"""    <item>
      <title>{title}</title>
      <description>{desc}</description>
      <itunes:summary>{desc}</itunes:summary>
      <pubDate>{pub}</pubDate>
      <enclosure url="{escape(url)}" length="{size}" type="audio/mpeg"/>
      <guid isPermaLink="false">{escape(guid)}</guid>
      <itunes:duration>{dur}</itunes:duration>
      <itunes:explicit>false</itunes:explicit>
    </item>""")

    title = escape(cfg.get("title", "NotebookLM — Podcasts"))
    author = escape(cfg.get("author", "Isabelle Larouche"))
    desc = escape(cfg.get("description", "Aperçus audio générés par NotebookLM."))
    cover = cfg.get("cover_url", "")
    cover_tag = f'\n    <itunes:image href="{escape(cover)}"/>' if cover else ""
    img_block = (f"""\n    <image>
      <url>{escape(cover)}</url>
      <title>{title}</title>
      <link>{escape(base)}/</link>
    </image>""" if cover else "")
    now = format_datetime(datetime.now(timezone.utc))

    feed = f"""<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>{title}</title>
    <link>{escape(base)}/</link>
    <language>fr-CA</language>
    <description>{desc}</description>
    <itunes:author>{author}</itunes:author>
    <itunes:summary>{desc}</itunes:summary>
    <itunes:explicit>false</itunes:explicit>
    <itunes:category text="Education"/>
    <lastBuildDate>{now}</lastBuildDate>{cover_tag}{img_block}
{chr(10).join(items)}
  </channel>
</rss>
"""
    with open(os.path.join(ROOT, "feed.xml"), "w", encoding="utf-8") as f:
        f.write(feed)
    print(f"feed.xml généré — {len(items)} épisode(s).")

if __name__ == "__main__":
    main()
