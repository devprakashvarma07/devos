#!/usr/bin/env python3
"""
genesis-recipes-audit.py — extraction ki ADHOORAPAN jaanch: kaunse sections me commands
capture NAHI hue. Book me 'installation' div 110 baar aata hai; recipes kitne bane, ye
unka mel zaroori hai — warna Genesis driver aadhi system chup-chaap skip karega.

Output:
  1) chapter-wise heading list (jisme 0 cmds wale bhi) + kya us heading ke baad
     <div class="installation"> tha
  2) wo installation blocks jo KISI recipe se attach nahi hue (dropped)
Usage: python3 genesis-recipes-audit.py <book.html> [chapters...]
"""
import sys, re
from html.parser import HTMLParser

HEAD_RE = re.compile(r'^(\d+)\.(\d+(?:\.\d+)*)(?:\.)?\s+(.*)$')
HEADINGS = ('h1', 'h2', 'h3', 'h4', 'h5', 'h6')


class Audit(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.sects = []
        self.cur = None
        self.h_tag = None
        self.h_buf = []
        self.pre_depth = 0
        self.kbd_class = None
        self.kbd_buf = []
        self.install_pending = 0     # <div class="installation"> dekha, abhi heading ka intezaar
        self.install_count = 0
        self.install_with_cmds = 0
        self.last_num = None

    def _close_heading(self):
        title = ' '.join(''.join(self.h_buf).split())
        self.h_tag, self.h_buf = None, []
        m = HEAD_RE.match(title)
        if not m:
            # extractor (fixed) se rule match karna zaroori hai, warna audit dusri hi cheez
            # nap rahi hogi: admonition headings recipe reset NAHI karti
            if title.strip() not in ('Note', 'Important', 'Warning', 'Caution', 'Tip'):
                self.cur = None
            return
        num = '%s.%s' % (m.group(1), m.group(2))
        self.cur = {'chap': m.group(1), 'num': num, 'title': m.group(3).strip(),
                    'cmds': 0, 'after_install': bool(self.install_pending)}
        self.sects.append(self.cur)
        self.install_pending = 0
        self.last_num = num

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == 'div' and (a.get('class') or '') == 'installation':
            self.install_count += 1
            self.install_pending += 1
        elif tag in HEADINGS:
            if self.h_tag:
                self._close_heading()
            self.h_tag = tag
            self.h_buf = []
        elif tag == 'pre':
            self.pre_depth += 1
        elif tag == 'kbd' and self.pre_depth:
            self.kbd_class = a.get('class', 'command')
            self.kbd_buf = []

    def handle_endtag(self, tag):
        if tag in HEADINGS:
            if self.h_tag == tag:
                self._close_heading()
        elif tag == 'pre' and self.pre_depth:
            self.pre_depth -= 1
        elif tag == 'kbd' and self.kbd_class is not None:
            txt = ''.join(self.kbd_buf).strip()
            cls = self.kbd_class
            self.kbd_class = None
            if txt and cls == 'command' and self.cur is not None:
                self.cur['cmds'] += 1

    def handle_data(self, data):
        # BUG (pehli version): ye method hi nahi tha -> h_buf khaali -> 0 headings ->
        # poora audit '0 sections' bolta tha. Parser tag deta hai, text nahi.
        if self.h_tag is not None:
            self.h_buf.append(data)
        elif self.kbd_class is not None:
            self.kbd_buf.append(data)


def main():
    book = sys.argv[1]
    wanted = sys.argv[2:] or None
    doc = open(book, encoding='utf-8', errors='replace').read()
    p = Audit()
    p.feed(doc)
    p.close()
    print('book installation divs =', p.install_count)
    print('sections with >=1 cmd  =', sum(1 for s in p.sects if s['cmds']))
    print('headings total         =', len(p.sects))
    print()
    zero = [s for s in p.sects if s['cmds'] == 0 and s['after_install']]
    print('===== installation ke BAAD wali heading jisme 0 commands (SUSPECT) =====')
    for s in zero[:40]:
        print('   %-10s %s' % (s['num'], s['title'][:60]))
    print('   suspect total =', len(zero))
    print()
    for ch in (wanted or sorted({s['chap'] for s in p.sects}, key=int)):
        secs = [s for s in p.sects if s['chap'] == ch]
        if not secs:
            continue
        print('===== chapter %s (%d headings, %d with cmds) =====' % (ch, len(secs), sum(1 for s in secs if s['cmds'])))
        for s in secs:
            flag = '  ' if s['cmds'] else ('!!' if s['after_install'] else ' .')
            print('  %s %-10s %-52s %3d cmds%s' % (flag, s['num'], s['title'][:52], s['cmds'],
                                                   '  <- installation div' if s['after_install'] else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main())
