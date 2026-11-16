#!/usr/bin/env python3
"""Generate/check a bounded source file manifest, never include caches or binaries."""
import argparse,hashlib,json
from pathlib import Path
r=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');a=p.parse_args()
excluded={'.git','.theos','.ci-theos','.ci-frameworks','build-evidence','packages','__pycache__','work','pkg'}
files=sorted(f for f in r.rglob('*') if f.is_file() and not excluded.intersection(f.relative_to(r).parts) and f.name!='SOURCE-MANIFEST.json')
m={f.relative_to(r).as_posix():hashlib.sha256(f.read_bytes()).hexdigest() for f in files}
assert len({p.casefold() for p in m})==len(m),'case-insensitive filesystem path collision'
out=r/'SOURCE-MANIFEST.json'
if a.check:assert json.loads(out.read_text())==m,'manifest drift'
else:out.write_text(json.dumps(m,indent=2,sort_keys=True)+'\n')
print('SOURCE MANIFEST PASS:',len(m),'files')
