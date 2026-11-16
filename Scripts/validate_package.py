#!/usr/bin/env python3
"""Read-only actual DEB, RootHide Mach-O, source-shader and signature-page gate."""
from pathlib import Path,PurePosixPath
import hashlib,io,json,plistlib,struct,sys,tarfile
ROOT=Path(__file__).resolve().parents[1]

def untar(data):
    result={}
    with tarfile.open(fileobj=io.BytesIO(data),mode='r:*') as t:
        for m in t:
            p=PurePosixPath(m.name)
            assert not p.is_absolute() and '..' not in p.parts
            assert not m.issym() and not m.islnk()
            if m.isdir():continue
            assert m.isfile(),m.name
            name=p.as_posix().removeprefix('./');assert name not in result
            result[name]=t.extractfile(m).read()
    return result

def parse_macho(data,kind,shader):
    assert data[:4]==b'\xca\xfe\xba\xbe'
    count=struct.unpack_from('>I',data,4)[0];assert count==2
    slices=[]
    for i in range(count):
        cpu,sub,off,size,align=struct.unpack_from('>5I',data,8+20*i)
        assert cpu==0x100000c and off+size<=len(data)
        thin=data[off:off+size];assert thin[:4]==b'\xcf\xfa\xed\xfe'
        ncmds=struct.unpack_from('<I',thin,16)[0];cursor=32
        deps=[];minimum=None;ident=None;cs=None;symtab=None
        for _ in range(ncmds):
            cmd,n=struct.unpack_from('<II',thin,cursor);assert n>=8 and cursor+n<=len(thin)
            if cmd==0x32:
                platform,minimum=struct.unpack_from('<II',thin,cursor+8);assert platform==2
            elif cmd==0x25:minimum=struct.unpack_from('<I',thin,cursor+8)[0]
            elif cmd in (0xd,0xc,0x80000018,0x8000001f):
                start=struct.unpack_from('<I',thin,cursor+8)[0]
                value=thin[cursor+start:cursor+n].split(b'\0')[0].decode()
                if cmd==0xd:ident=value
                else:deps.append(value)
            elif cmd==0x1d:cs=struct.unpack_from('<II',thin,cursor+8)
            elif cmd==2:symtab=struct.unpack_from('<4I',thin,cursor+8)
            elif cmd in (0x21,0x2c):assert struct.unpack_from('<I',thin,cursor+16)[0]==0
            cursor+=n
        assert minimum==0xf0000 and cs
        assert not any('/var/jb' in d for d in deps)
        if kind=='main':
            assert ident=='@loader_path/.jbroot/Library/MobileSubstrate/DynamicLibraries/NoticeDeleteAnimation.dylib',ident
            assert any('substrate' in d for d in deps) and any('Metal.framework' in d for d in deps)
            assert shader in thin,'actual shader text missing from rebuilt binary'
            for cls in ('NLDustRenderer','NLWithdrawalEffect','NLNotificationDismissalSnapshot','NLNotificationHookLoader'):
                assert cls.encode()+b'\0' in thin,cls
        else:
            assert any('Preferences.framework' in d for d in deps)
            for cls in ('NLRootListController','NLBannerStatusController'):assert cls.encode()+b'\0' in thin
        undefined=[]
        if symtab:
            so,nsyms,stro,strsize=symtab;strings=thin[stro:stro+strsize]
            for k in range(nsyms):
                si,nt,section,desc,val=struct.unpack_from('<IBBHQ',thin,so+16*k)
                if nt & 0xe == 0 and section==0 and si:
                    name=strings[si:].split(b'\0')[0].decode()
                    if name.startswith(('_NL','_OBJC_CLASS_$_NL','_OBJC_METACLASS_$_NL')):undefined.append(name)
        assert not undefined,undefined
        sig=thin[cs[0]:cs[0]+cs[1]];magic,length,num=struct.unpack_from('>III',sig)
        assert magic==0xfade0cc0 and length<=len(sig)
        directories=[]
        for k in range(num):
            slot,offset=struct.unpack_from('>II',sig,12+k*8)
            if slot!=0 and not 0x1000<=slot<=0x1005:continue
            cd=sig[offset:];v=struct.unpack_from('>9I',cd);assert v[0]==0xfade0c02
            ho,slots,limit=v[4],v[7],v[8];hs,ht,platform,page=struct.unpack_from('4B',cd,36)
            alg={1:'sha1',2:'sha256',3:'sha256',4:'sha384'}[ht]
            assert 0<page<=20 and limit<=cs[0] and slots==(limit+(1<<page)-1)//(1<<page)
            for j in range(slots):
                actual=hashlib.new(alg,thin[j*(1<<page):min(limit,(j+1)*(1<<page))]).digest()[:hs]
                assert actual==cd[ho+j*hs:ho+(j+1)*hs],(kind,i,alg,j)
            directories.append({'hash':alg,'pages':slots})
        assert directories
        slices.append({'subtype':hex(sub),'minimum':'15.0','identifier':ident,'dependencies':deps,'own_undefined':undefined,'signature_directories':directories})
    assert {int(s['subtype'],16)&0xffffff for s in slices}=={0,2}
    return slices

def check(deb,extract=None):
    raw=Path(deb).read_bytes();assert raw[:8]==b'!<arch>\n';p=8;members={}
    while p<len(raw):
        h=raw[p:p+60];assert h[58:60]==b'`\n';name=h[:16].decode().strip().rstrip('/');n=int(h[48:58]);assert name not in members
        members[name]=raw[p+60:p+60+n];p+=60+n+(n%2)
    assert members['debian-binary']==b'2.0\n'
    controls=untar(next(v for k,v in members.items() if k.startswith('control.tar')))
    text=controls['control'].decode()
    fields=dict(s.split(': ',1) for s in text.splitlines() if ': ' in s and not s.startswith(' '))
    for key,val in {'Package':'com.tsangbaby.noticedeleteanimation','Name':'NoticeDeleteAnimation','Version':'0.1.0~alpha8','Author':'Tsangbaby','Maintainer':'Tsangbaby','Architecture':'iphoneos-arm64e'}.items():assert fields[key]==val,(key,fields[key])
    assert fields['Conflicts']=='com.example.noticelisttweak' and fields['Replaces']==fields['Conflicts']
    assert 'preferenceloader' in fields['Depends'] and 'firmware (>= 15.0)' in fields['Depends']
    files=untar(next(v for k,v in members.items() if k.startswith('data.tar')))
    main='Library/MobileSubstrate/DynamicLibraries/NoticeDeleteAnimation.dylib'
    bundle='Library/PreferenceBundles/NoticeDeleteAnimation.bundle/'
    prefs=bundle+'NoticeDeleteAnimation'
    entry='Library/PreferenceLoader/Preferences/com.tsangbaby.noticedeleteanimation.plist'
    allowed={main,main.removesuffix('.dylib')+'.plist',entry,prefs,bundle+'Info.plist',bundle+'Root.plist'}
    allowed.update(bundle+p for p in ('icon.png','Logo.png','icon@2x.png','icon@3x.png'))
    assert set(files)<=allowed,(set(files)-allowed)
    assert {main,prefs,entry,bundle+'Info.plist',bundle+'Root.plist'}<=set(files)
    registration=plistlib.loads(files[entry])['entry'];assert registration['bundle']=='NoticeDeleteAnimation' and registration['detail']=='NLRootListController' and registration['isController'] is True
    info=plistlib.loads(files[bundle+'Info.plist']);assert info['NSPrincipalClass']=='NLRootListController' and info['CFBundleExecutable']=='NoticeDeleteAnimation'
    filter_data=plistlib.loads(files[main.removesuffix('.dylib')+'.plist']);assert 'SpringBoard' in str(filter_data) or 'com.apple.springboard' in str(filter_data)
    root_plist=plistlib.loads(files[bundle+'Root.plist']);assert root_plist['title']=='NoticeDeleteAnimation'
    assert info['CFBundleIdentifier']=='com.tsangbaby.noticedeleteanimation.preferences'
    assert info['CFBundleDisplayName']=='NoticeDeleteAnimation' and registration['label']=='NoticeDeleteAnimation'
    for item in root_plist['items']:
        if 'defaults' in item:assert item['defaults']=='com.tsangbaby.noticedeleteanimation'
        if 'PostNotification' in item:assert item['PostNotification']=='com.tsangbaby.noticedeleteanimation/preferencesChanged'
    for name,data in files.items():
        assert 'NoticeListTweak' not in name and 'com.example.' not in name
        if name.endswith(('.dylib','NoticeDeleteAnimation')):
            assert b'com.example.noticelisttweak' not in data and b'[NoticeListTweak]' not in data
    shader=(ROOT/'src/DustShader.metal').read_bytes()
    binaries={}
    for kind,name in [('main',main),('prefs',prefs)]:
        binaries[kind]={'sha256':hashlib.sha256(files[name]).hexdigest(),'bytes':len(files[name]),'slices':parse_macho(files[name],kind,shader)}
    if extract:
        out=Path(extract);out.mkdir(parents=True,exist_ok=True)
        for name,data in files.items():
            target=out/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
    return {'result':'PASS','deb':str(deb),'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),'control':fields,'files':sorted(files),'registration':registration,'info':info,'shader_sha256':hashlib.sha256(shader).hexdigest(),'binaries':binaries}
if __name__=='__main__':
    print(json.dumps(check(sys.argv[1],sys.argv[2] if len(sys.argv)>2 else None),indent=2,ensure_ascii=False))
