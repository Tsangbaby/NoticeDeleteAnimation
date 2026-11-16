#!/usr/bin/env python3
"""Portable source/metadata contracts. NOT Apple SDK compilation or hook validation."""
from pathlib import Path
import json,plistlib,re,unittest,importlib.util
ROOT=Path(__file__).resolve().parents[1]
class SourceContracts(unittest.TestCase):
    def test_source_closure(self):
        make=(ROOT/'Makefile').read_text()
        paths=re.findall(r'src/[A-Za-z0-9_]+\.m',make)
        self.assertEqual(set(paths),{str(p.relative_to(ROOT)) for p in (ROOT/'src').glob('*.m')})
        self.assertEqual(len(paths),len(set(paths)))
        self.assertIn('src/NLNotificationDismissalSnapshot.m',paths)
        self.assertIn('src/DustShaderSource.m',paths)
        self.assertNotIn('stubs/',make)
    def test_metal_embedding(self):
        spec=importlib.util.spec_from_file_location('shader',ROOT/'Scripts/generate_shader.py')
        m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
        shader=(ROOT/'src/DustShader.metal').read_bytes()
        self.assertEqual((ROOT/'src/DustShaderSource.m').read_bytes(),m.generate(shader))
        self.assertIn(b'nlDustVertex',shader);self.assertIn(b'nlDustFragment',shader)
        renderer=(ROOT/'src/NLDustRenderer.m').read_text()
        self.assertIn('extern const char *NLDustMetalSource',renderer)
        self.assertNotIn('static const char *NLDustMetalSource;',renderer)
    def test_metadata(self):
        c=dict(s.split(': ',1) for s in (ROOT/'control').read_text().splitlines() if ': ' in s)
        self.assertEqual(c['Package'],'com.example.noticelisttweak')
        self.assertEqual(c['Version'],'1.0.1+rebuild1')
        self.assertIn('firmware (>= 15.0)',c['Depends'])
        for directory in ('layout','prefs'):
            for f in (ROOT/directory).rglob('*.plist'):plistlib.loads(f.read_bytes())
    def test_preferences_registration(self):
        entry=plistlib.loads((ROOT/'layout/Library/PreferenceLoader/Preferences/com.example.noticelisttweak.plist').read_bytes())['entry']
        info=plistlib.loads((ROOT/'layout/Library/PreferenceBundles/NoticeListTweak.bundle/Info.plist').read_bytes())
        self.assertEqual(entry['bundle'],info['CFBundleExecutable']);self.assertIs(entry['isController'],True)
        self.assertEqual(entry['detail'],info['NSPrincipalClass']);self.assertEqual(info['NSPrincipalClass'],'NLRootListController')
        self.assertIn('makefiles/common.mk',(ROOT/'prefs/Makefile').read_text())
    def test_shared_declarations(self):
        h=(ROOT/'src/NLNotificationListHooks.h').read_text()
        self.assertIn('NSUInteger index, BOOL animated',h)
        snapshot=(ROOT/'src/NLNotificationDismissalSnapshot.h').read_text()
        self.assertIn('#import "NLDustRenderer.h"',snapshot)
        self.assertNotIn('@interface NLDustRenderer',snapshot)
        definitions=sum(len(re.findall(r'^BOOL\s+NLExistingNotificationSnapshotActive\([^;]+\)\s*\{',p.read_text(),re.M)) for p in (ROOT/'src').glob('*.m'))
        self.assertEqual(definitions,1)
    def test_hook_retries_are_idempotent(self):
        s=(ROOT/'src/NLNotificationHookLoader.m').read_text()
        for name in ('NLOriginalClearAll','NLOriginalRemove','NLOriginalRemoveDisplaced'):self.assertIn('!'+name,s)
        self.assertIn('NLABIMethod(listViewClass, basicSel, "v", 2, basicArguments)',s)
        self.assertIn('NLABIMethod(listViewClass, displacedSel, "v", 3, displacedArguments)',s)
    def test_scalar_calls_have_scalar_abi(self):
        icon=(ROOT/'src/NLIconDust.m').read_text();lock=(ROOT/'src/NLLockScreenDust.m').read_text()
        for sel in ('isDragging','isFolderIcon','isWidgetIcon'):
            self.assertIn('NLABIReadBool(',icon);self.assertNotIn('NLIconGet(icon, NSSelectorFromString(@"'+sel+'"))',icon)
        self.assertNotIn('[gesture performSelector:@selector(state)]',lock)
        self.assertIn('@encode(NSInteger)',lock)
        self.assertIn('uninstall1, 3, "@"',icon)
    def test_no_original_binary_fallback_or_stubs(self):
        self.assertFalse((ROOT/'pkg').exists())
        for p in (ROOT/'src').glob('*.m'):
            self.assertNotIn('stubs/',p.read_text())
            self.assertNotIn('/pkg/',p.read_text())
        workflow=(ROOT/'.github/workflows/roothide-rebuild.yml').read_text()
        self.assertIn('THEOS_PACKAGE_SCHEME=roothide',workflow)
        self.assertNotIn('continue-on-error',workflow)
if __name__=='__main__':unittest.main(verbosity=2)
