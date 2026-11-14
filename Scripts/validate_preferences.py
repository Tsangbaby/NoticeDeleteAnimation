#!/usr/bin/env python3
"""Read-only check of Settings registration and universal Preferences executable."""
import plistlib,struct,sys,json
from pathlib import Path
root=Path(sys.argv[1])
registration=root/'Library/PreferenceLoader/Preferences/NoticeDeleteAnimation.plist'
bundle=root/'Library/PreferenceBundles/NDAPreferences.bundle'
assert registration.is_file(), registration
r=plistlib.loads(registration.read_bytes())
entry=r['entry']
assert entry['bundle']=='NDAPreferences'
assert entry['detail']=='NDASettingsController'
info=plistlib.loads((bundle/'Info.plist').read_bytes())
assert info['NSPrincipalClass']=='NDASettingsController'
binary=bundle/info['CFBundleExecutable']
data=binary.read_bytes()
assert data[:4]==b'\xca\xfe\xba\xbe'
count=struct.unpack_from('>I',data,4)[0]
assert count==2
slices=[]
for i in range(count):
    cpu,subtype,offset,size,align=struct.unpack_from('>5I',data,8+20*i)
    assert cpu==0x100000c
    blob=data[offset:offset+size]
    assert blob[:4]==b'\xcf\xfa\xed\xfe'
    h=struct.unpack_from('<8I',blob)
    assert h[3] in (6,8)
    minimum=None; signature=False;deps=[];cursor=32
    for _ in range(h[4]):
        cmd,length=struct.unpack_from('<2I',blob,cursor)
        assert length>=8 and cursor+length<=len(blob)
        if cmd==0x32:
            platform,minimum=struct.unpack_from('<2I',blob,cursor+8)
            assert platform==2
        elif cmd==0x25: minimum=struct.unpack_from('<I',blob,cursor+8)[0]
        elif cmd==0x1d:
            start,n=struct.unpack_from('<2I',blob,cursor+8)
            assert n>0 and start+n<=len(blob)
            signature=True
        elif cmd in (0xc,0x80000018,0x8000001f):
            start=struct.unpack_from('<I',blob,cursor+8)[0]
            deps.append(blob[cursor+start:cursor+length].split(b'\0')[0].decode())
        cursor+=length
    assert minimum==0xf0000,minimum
    assert signature
    assert any('Preferences.framework' in d for d in deps),deps
    assert not any('/var/jb' in d for d in deps),deps
    slices.append({'cpu':hex(cpu),'subtype':hex(subtype),'min_ios':'15.0','signature':signature,'deps':deps})
assert {int(s['subtype'],16)&0xffffff for s in slices}=={0,2}
print(json.dumps({'registration':r,'info':info,'slices':slices,'result':'PASS'},indent=2))
