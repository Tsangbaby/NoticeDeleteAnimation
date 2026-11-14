#!/usr/bin/env python3
"""Package source only; verify every ZIP member against a SHA256 file manifest."""
from pathlib import Path
import hashlib
import json
import zipfile

root = Path(__file__).resolve().parents[1]
version = next(line.split(': ', 1)[1].strip() for line in (root / 'control').read_text().splitlines()
               if line.startswith('Version: ')).replace('~', '-')
output = root.parent / f'NoticeDeleteAnimation-{version}-source.zip'
files = sorted(p for p in root.rglob('*') if p.is_file() and
               not any(part in {'.git', '.build', '.theos', '__pycache__', 'packages'}
                       for part in p.relative_to(root).parts) and p.name != 'SOURCE-MANIFEST.json')
manifest = {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
manifest_path = root / 'SOURCE-MANIFEST.json'
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for path in files + [manifest_path]:
        archive.write(path, (Path(root.name) / path.relative_to(root)).as_posix())
with zipfile.ZipFile(output) as archive:
    assert archive.testzip() is None
    assert len(archive.namelist()) == len(manifest) + 1
    for name, digest in manifest.items():
        assert hashlib.sha256(archive.read(root.name + '/' + name)).hexdigest() == digest
print(json.dumps({'file': str(output), 'members': len(manifest) + 1,
                  'size': output.stat().st_size,
                  'sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
                  'manifest_files_verified': len(manifest)}, indent=2))
