#!/usr/bin/env python3
"""
genesis-recipes.py — LFS book (12.4) ke HTML se build commands EXTRACT karna.

Kyun: "no third-party base" = sab kuch source se khud build. Build steps memory se likhna risky
tha (configure flags har version me badalte hain), isliye book ka HTML hi source of truth hai.
Ye script se nikle recipes padhne-layak aur verify-able hain; DevOS ka build driver inhe
$LFS/$TOOLS/$package variables ke saath chalata hai.

Kaise: ek single-pass HTMLParser state machine — koi offset slicing nahi.
Pichli implementation <div class="installation"> ke offsets kaat-kaat kar slice karti thi aur
chapter 5 me se SIRF 1 section nikla (baaki chup-chaap drop), kyunke:
  (a) book ka HTML line-wrapped hai — heading aur kbd ke beech bhi line break:
        <pre class="userinput"><kbd class=
        "command">make mrproper</kbd></pre>
  (b) installation block ke *andar* bhi <div class="content"> aata hai (informalexample etc),
      isliye "agla content div = block ka end" wala rule commands kaad deta tha.
Is version me bas tag stream hai:
  * h1..h6 ka text -> section title + number -> naya recipe khulta hai
  * <pre> ke andar <kbd class="command">                  -> ek command (multi-line/backslash
        waise hi rakhte hain, jod-te ya todte nahi)
  * <kbd class="computeroutput"> / <pre class="screen">   -> output, comment bankar likha jaata
        hai (driver ignore karta hai, par padhne wale ke liye context rahe)

Usage: python3 genesis-recipes.py <LFS-BOOK-*.html> <out-dir> [chapter ...]
       (chapter ke bina = sab chapters)
"""
import sys, os, re
from html.parser import HTMLParser

HEAD_RE = re.compile(r'^(\d+)\.(\d+(?:\.\d+)*)(?:\.)?\s+(.*)$')
HEADINGS = ('h1', 'h2', 'h3', 'h4', 'h5', 'h6')
# Book ke installation blocks ke ANDAR bina-number wali headings — genesis-headings.py se
# gine gayi (Note 71, Important 22, Warning 10, Caution 5; 'Tip' kahin nahi, par chhodte hain
# standard DocBook name hai). Inme commands aate hain (e.g. 5.2.1 Cross Binutils ka Note),
# isliye in par recipe RESET karna hi wo 9 sections tha jinke commands ganve the.
ADMONITIONS = {'Note', 'Important', 'Warning', 'Caution', 'Tip'}


class BookParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.recipes = []          # [{chap, num, title, items:[(kind, text)]}]
        self.cur = None
        self.h_tag = None
        self.h_buf = []
        self.pre_depth = 0
        self.pre_class = []
        self.kbd_class = None
        self.kbd_buf = []
        # <pre class="screen"> ka text HTMLParser multiple data chunks me deta hai (nested
        # span/entity ki wajah se 'G' + 'eneral setup --->' jaisa toot-ta hai) -> isliye poora
        # pre buffer karke </pre> par EK item emit karte hain.
        self.screen_buf = []

    def _close_heading(self):
        title = ' '.join(''.join(self.h_buf).split())
        self.h_tag, self.h_buf = None, []
        m = HEAD_RE.match(title)
        if not m:
            # Admonition heading (Note/Warning/...) = USI section ka ang hai, commands uske
            # baad bhi isi recipe ke hain -> reset NAHI. Baaki bina-number headings (Part/
            # Chapter titles, "Short Descriptions", "Contents of X") par recipe band karo,
            # warna commands galat section me ghus jaayenge.
            if title not in ADMONITIONS:
                self.cur = None
            return
        chap, rest, name = m.group(1), m.group(2), m.group(3).strip()
        self.cur = {'chap': chap, 'num': '%s.%s' % (chap, rest), 'title': name, 'items': []}
        self.recipes.append(self.cur)

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag in HEADINGS:
            if self.h_tag:
                self._close_heading()
            self.h_tag = tag
            self.h_buf = []
        elif tag == 'pre':
            self.pre_depth += 1
            cls = a.get('class') or ''
            self.pre_class.append(cls)
            if 'screen' in cls:
                self.screen_buf = []
        elif tag == 'kbd' and self.pre_depth:
            self.kbd_class = a.get('class', 'command')
            self.kbd_buf = []

    def handle_endtag(self, tag):
        if tag in HEADINGS:
            if self.h_tag == tag:
                self._close_heading()
        elif tag == 'pre' and self.pre_depth:
            self.pre_depth -= 1
            cls = self.pre_class.pop() if self.pre_class else ''
            if 'screen' in cls:
                txt = ''.join(self.screen_buf).strip('\n')
                self.screen_buf = []
                if txt and self.cur is not None:
                    self.cur['items'].append(('out', txt))
        elif tag == 'kbd' and self.kbd_class is not None:
            txt = ''.join(self.kbd_buf).strip('\n')
            cls = self.kbd_class
            self.kbd_class = None
            if not txt or self.cur is None:
                return
            if cls == 'command':
                self.cur['items'].append(('cmd', txt))
            elif cls in ('computeroutput', 'screen'):
                self.cur['items'].append(('out', txt))
            # option / replaceable / filename / systemitem = command ka ang, alag item nahi

    def handle_data(self, data):
        if self.h_tag is not None:
            self.h_buf.append(data)
        elif self.kbd_class is not None:
            self.kbd_buf.append(data)
        elif self.pre_depth and self.pre_class and 'screen' in self.pre_class[-1]:
            self.screen_buf.append(data)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    src, out = sys.argv[1], sys.argv[2]
    wanted = sys.argv[3:] or None
    with open(src, encoding='utf-8', errors='replace') as f:
        doc = f.read()
    p = BookParser()
    p.feed(doc)
    p.close()

    by_chap = {}
    for r in p.recipes:
        by_chap.setdefault(r['chap'], []).append(r)

    chapters = wanted if wanted else sorted(by_chap, key=int)
    slug = lambda t: re.sub(r'[^a-z0-9]+', '-', t.lower()).strip('-')[:48]
    total = 0
    for ch in chapters:
        recs = [r for r in by_chap.get(ch, []) if any(k == 'cmd' for k, _ in r['items'])]
        d = os.path.join(out, 'chapter-%s' % ch)
        os.makedirs(d, exist_ok=True)
        print('== chapter %s: %d sections with commands (headings seen: %d)'
              % (ch, len(recs), len(by_chap.get(ch, []))))
        for r in recs:
            fn = os.path.join(d, '%s.%s.sh' % (r['num'], slug(r['title'])))
            with open(fn, 'w', encoding='utf-8', newline='\n') as g:
                g.write('#!/bin/bash\n')
                g.write('# DevOS Genesis recipe — EXTRACTED from %s\n' % os.path.basename(src))
                g.write('# LFS %s "%s" — commands exactly as the book gives them\n'
                        % (r['num'], r['title']))
                g.write('# Driver runs these with $LFS / $TOOLS / $package set.\n')
                g.write('set -euo pipefail\n\n')
                for k, t in r['items']:
                    if k == 'cmd':
                        g.write(t.rstrip() + '\n\n')
                    else:
                        for ln in t.splitlines():
                            g.write('# OUT| %s\n' % ln)
                        g.write('\n')
            total += 1
            ncmd = sum(1 for k, _ in r['items'] if k == 'cmd')
            print('   %-10s %-46s %2d cmds' % (r['num'], r['title'][:46], ncmd))
    print('files=%d  out=%s' % (total, out))
    return 0


if __name__ == '__main__':
    sys.exit(main())
