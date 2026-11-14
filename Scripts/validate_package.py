#!/usr/bin/env python3
"""Read-only DEB/Mach-O acceptance gate. Never executes package maintenance scripts."""
import sys, struct, json, hashlib, subprocess, plistlib
from pathlib import Path

def check(deb, extracted):
    fields = subprocess.check_output(['dpkg-deb', '--field', str(deb)], text=True)
    control = dict(line.split(': ', 1) for line in fields.splitlines() if ': ' in line and not line.startswith(' '))
    for key, value in {'Package':'com.tsangbaby.noticedeleteanimation', 'Name':'NoticeDeleteAnimation',
                       'Author':'Tsangbaby','Maintainer':'Tsangbaby','Architecture':'iphoneos-arm64e'}.items():
        assert control[key] == value, (key, control.get(key))
    assert 'firmware (>= 15.0)' in control['Depends']
    dylibs = list(extracted.rglob('NoticeDeleteAnimation.dylib'))
    assert len(dylibs) == 1
    dylib = dylibs[0]
    relative = dylib.relative_to(extracted).as_posix()
    assert relative == 'Library/MobileSubstrate/DynamicLibraries/NoticeDeleteAnimation.dylib', relative
    plist = dylib.with_suffix('.plist')
    assert plistlib.loads(plist.read_bytes()) == {'Filter':{'Bundles':['com.apple.springboard']}}
    data = dylib.read_bytes()
    assert data[:4] == b'\xca\xfe\xba\xbe', 'Expected universal Mach-O'
    count = struct.unpack_from('>I', data, 4)[0]
    assert count == 2
    slices = []
    for i in range(count):
        cpu, subtype, offset, size, align = struct.unpack_from('>IIIII', data, 8 + 20*i)
        assert cpu == 0x100000c
        blob = data[offset:offset+size]
        assert len(blob) == size and blob[:4] == b'\xcf\xfa\xed\xfe'
        header = struct.unpack_from('<8I', blob)
        assert header[3] == 6, 'Expected MH_DYLIB'
        cursor, commands = 32, []
        minimum, sdk, identifier, signature = None, None, None, False
        deps = []
        for _ in range(header[4]):
            cmd, length = struct.unpack_from('<II',blob,cursor)
            assert length >= 8 and cursor+length <= len(blob)
            commands.append(cmd)
            if cmd == 0x32:
                platform, minimum, sdk, tools = struct.unpack_from('<4I',blob,cursor+8)
                assert platform == 2
            elif cmd == 0x25:
                minimum, sdk = struct.unpack_from('<2I',blob,cursor+8)
            elif cmd in (0xd, 0xc, 0x80000018, 0x8000001f):
                start = struct.unpack_from('<I',blob,cursor+8)[0]
                value = blob[cursor+start:cursor+length].split(b'\0')[0].decode()
                if cmd == 0xd: identifier=value
                else: deps.append(value)
            elif cmd == 0x1d:
                so, ss = struct.unpack_from('<II',blob,cursor+8)
                assert ss > 0 and so+ss <= len(blob)
                signature = True
            elif cmd in (0x21, 0x2c):
                assert struct.unpack_from('<I',blob,cursor+16)[0] == 0
            cursor += length
        assert minimum == 0x000f0000, minimum
        assert signature
        assert identifier == '@loader_path/.jbroot/Library/MobileSubstrate/DynamicLibraries/NoticeDeleteAnimation.dylib', identifier
        assert not any('/var/jb' in dep for dep in deps), deps
        assert any('substrate' in dep.lower() for dep in deps), deps
        slices.append({'cpu':hex(cpu),'subtype':hex(subtype),'min_ios':'15.0',
                       'sdk':f'{sdk>>16}.{(sdk>>8)&255}.{sdk&255}', 'signed':signature,
                       'install_name':identifier,'dependencies':deps})
    assert {int(s['subtype'],16)&0xffffff for s in slices} == {0,2}
    return {'package':control,'dylib_path':relative,'slices':slices,'bytes':deb.stat().st_size,
            'sha256':hashlib.sha256(deb.read_bytes()).hexdigest(),'result':'PASS'}
if __name__=='__main__':
    print(json.dumps(check(Path(sys.argv[1]),Path(sys.argv[2])),indent=2))
