"""Build an offline single-character fallback from pinned official Unicode data.
No network access, third-party package, executable download, or generated translation.
Usage: python3 script/import_unihan.py path/to/Unihan-18.0.0.zip
Place the official Unicode license.txt beside the archive as unicode-license.txt.
"""
import hashlib
import json
import re
import sys
import unicodedata
from pathlib import Path
from zipfile import ZipFile

VERSION = '18.0.0'
ARCHIVE_SHA256 = '4c93ea9c1f636451729a840978f1667a53886af37ba854fdcce109721c63d43e'
ROOT = Path(__file__).resolve().parents[1]


def plain_pinyin(value):
    # ü becomes v; tone marks are removed without collapsing ü to u.
    value = unicodedata.normalize('NFD', value.lower())
    value = value.replace('u\u0308', 'v')
    return ''.join(c for c in value if not unicodedata.combining(c))


def main():
    source = Path(sys.argv[1])
    raw = source.read_bytes()
    if hashlib.sha256(raw).hexdigest() != ARCHIVE_SHA256:
        raise ValueError('Archive differs from the reviewed official Unicode release')
    license_text = (source.parent / 'unicode-license.txt').read_text()
    if 'UNICODE LICENSE V3' not in license_text:
        raise ValueError('Official Unicode license is required')
    props = {}
    with ZipFile(source) as archive:
        for filename in ['Unihan_Readings.txt', 'Unihan_OtherMappings.txt']:
            if archive.getinfo(filename).file_size > 16 * 1024 * 1024:
                raise ValueError('Unexpected member size')
            content = archive.read(filename).decode('utf-8')
            if '# Unicode Version ' + VERSION not in content:
                raise ValueError('Unexpected Unicode data version')
            for line in content.splitlines():
                if not line or line.startswith('#'):
                    continue
                cp, key, value = line.split('\t')
                if key in ['kMandarin', 'kHanyuPinlu', 'kGB0']:
                    props.setdefault(chr(int(cp[2:], 16)), {})[key] = value
    # Never let the fallback overwrite an authored gloss, weight, or Wubi code.
    authored = set()
    for file in sorted((ROOT / 'data').glob('[0-9]*.tsv')):
        if file.name == '06-基础单字.tsv':
            continue
        for line in file.read_text().splitlines():
            if line and not line.startswith('#'):
                text, syllables = line.split('\t')[:2]
                authored.add((text, syllables.replace(' ', '')))
    rows = []
    chars = set()
    for char, fields in sorted(props.items()):
        if 'kGB0' not in fields or 'kMandarin' not in fields:
            continue
        # First kMandarin value is the zh-Hans preference per UAX #38.
        primary = plain_pinyin(fields['kMandarin'].split()[0])
        readings = {primary: 0}
        for reading, count in re.findall(r'([^\s(),]+)\((\d+)\)', fields.get('kHanyuPinlu', '')):
            code = plain_pinyin(reading)
            readings[code] = max(readings.get(code, 0), int(count))
        for code, count in sorted(readings.items()):
            if not re.fullmatch('[a-z]+', code) or (char, code) in authored:
                continue
            # Historic Unihan reading counts are only a base ranking hint.
            weight = 60 + min(800, count * 10)
            rows.append('\t'.join([char, code, '', '', '', '', str(weight), '基础单字']))
            chars.add(char)
    if not rows:
        raise ValueError('No fallback entries produced; existing output is preserved')
    header = ['# Unicode Unihan ' + VERSION + ' derived GB2312 single-character fallback.',
              '# Copyright © 1991-2026 Unicode, Inc. Unicode License V3; see unicode-license.txt.',
              '# Only phonetic data; no Wubi codes or foreign vocabulary translations.',
              '# Regenerate with script/import_unihan.py; source and hashes: Unihan-SOURCE.json.']
    output = ROOT / 'data/06-基础单字.tsv'
    output.write_text('\n'.join(header + rows) + '\n', encoding='utf-8')
    (ROOT / 'data/unicode-license.txt').write_text(license_text, encoding='utf-8')
    manifest = {'source': 'https://www.unicode.org/Public/' + VERSION + '/ucd/Unihan.zip',
                'license': 'https://www.unicode.org/license.txt', 'unicodeVersion': VERSION,
                'archiveSHA256': ARCHIVE_SHA256, 'entryCount': len(rows), 'characterCount': len(chars),
                'derivedSHA256': hashlib.sha256(output.read_bytes()).hexdigest(),
                'properties': ['kGB0', 'kMandarin', 'kHanyuPinlu'],
                'scope': 'GB2312 characters; primary zh-Hans and attested kHanyuPinlu readings. No translations.'}
    (ROOT / 'data/Unihan-SOURCE.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'entries': len(rows), 'characters': len(chars)}))


if __name__ == '__main__':
    main()
