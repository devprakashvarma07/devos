#!/usr/bin/env python3
"""
genesis-headings.py — book ki SAARI heading texts jo section-number se shuru NAHI hoti.
Kyun: extractor unnumbered heading par recipe reset kar deta tha, isliye 9 installation
sections ke commands ganve (Note/WARNING ke andar commands bhi hote hain). Fix choose karne
ke liye pehle dekhna hai ke ye headings kaunsi hain — allowlist andaaze se nahi banayenge.
Usage: python3 genesis-headings.py <book.html>
"""
import sys, re
from collections import Counter
from html.parser import HTMLParser

NUM_RE = re.compile(r'^\d+(\.\d+)*\.?\s')
HEADINGS = ('h1', 'h2', 'h3', 'h4', 'h5', 'h6')


class H(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.in_h = None
        self.buf = []
        self.unnumbered = Counter()
        self.numbered = 0

    def handle_starttag(self, tag, attrs):
        if tag in HEADINGS:
            if self.in_h:
                self._flush()
            self.in_h = tag
            self.buf = []

    def handle_endtag(self, tag):
        if tag in HEADINGS and self.in_h == tag:
            self._flush()

    def handle_data(self, d):
        if self.in_h:
            self.buf.append(d)

    def _flush(self):
        t = ' '.join(''.join(self.buf).split())
        self.in_h = None
        if not t:
            return
        if NUM_RE.match(t):
            self.numbered += 1
        else:
            self.unnumbered[t[:60]] += 1


def main():
    doc = open(sys.argv[1], encoding='utf-8', errors='replace').read()
    p = H()
    p.feed(doc)
    p.close()
    print('numbered headings   :', p.numbered)
    print('unnumbered headings :', sum(p.unnumbered.values()))
    print()
    for t, c in p.unnumbered.most_common(60):
        print('%4d  %s' % (c, t))
    return 0


if __name__ == '__main__':
    sys.exit(main())
