#!/usr/bin/env python3
"""Builds hermsy.illbytes.com into _site/ (GitHub Pages publishes it).

    pip install markdown==3.7
    python3 site/build.py            # then open _site/index.html

Pages are site/pages/*.md or *.html, wrapped in site/template.html. The
privacy page is built from store/privacy-policy.md, the same text the app
stores link to, so there is only ever one copy of the policy.
"""
import re
import shutil
from pathlib import Path

import markdown

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / "site"
OUT = ROOT / "_site"

# (source, output path, title, nav label)
PAGES = [
    (SITE / "pages" / "index.html", "index.html", "Hermsy: your own AI agent, in your pocket", "Home"),
    (SITE / "pages" / "setup.md", "setup/index.html", "Set up Hermsy", "Setup"),
    (ROOT / "store" / "privacy-policy.md", "privacy/index.html", "Hermsy privacy policy", "Privacy"),
    (SITE / "pages" / "support.md", "support/index.html", "Hermsy support", "Support"),
    (SITE / "pages" / "delete-data.md", "delete-data/index.html", "Delete your Hermsy data", None),
]


def render(source: Path) -> str:
    text = source.read_text(encoding="utf-8")
    if source.suffix == ".html":
        return text
    html = markdown.markdown(text, extensions=["tables", "fenced_code", "sane_lists"])
    # Open external links in the same tab, but mark them for the stylesheet.
    return re.sub(r'<a href="(https?://)', r'<a class="out" href="\1', html)


def main() -> None:
    template = (SITE / "template.html").read_text(encoding="utf-8")
    if OUT.exists():
        shutil.rmtree(OUT)
    shutil.copytree(SITE / "static", OUT / "static")
    for source, path, title, label in PAGES:
        depth = path.count("/")
        prefix = "../" * depth
        nav = "\n".join(
            f'<a href="{prefix}{"" if p == "index.html" else p.replace("index.html", "")}"'
            f'{" aria-current=\"page\"" if p == path else ""}>{l}</a>'
            for _, p, _, l in PAGES
            if l  # pages without a label are linked from others, not the menu
        )
        page = (
            template.replace("{{TITLE}}", title)
            .replace("{{NAV}}", nav)
            .replace("{{ROOT}}", prefix)
            .replace("{{BODY}}", render(source))
            .replace("{{KIND}}", "home" if path == "index.html" else "doc")
        )
        target = OUT / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(page, encoding="utf-8")
    (OUT / "CNAME").write_text("hermsy.illbytes.com\n")
    print(f"built {len(PAGES)} pages into {OUT}")


if __name__ == "__main__":
    main()
