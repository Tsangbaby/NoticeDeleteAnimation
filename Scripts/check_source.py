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
        self.assertEqual(c['Package'],'com.tsangbaby.noticedeleteanimation')
        self.assertEqual(c['Version'],'0.1.0~alpha8')
        self.assertIn('firmware (>= 15.0)',c['Depends'])
        for directory in ('layout','prefs'):
            for f in (ROOT/directory).rglob('*.plist'):plistlib.loads(f.read_bytes())
        stage_filter=(ROOT/'NoticeDeleteAnimation.plist').read_bytes()
        self.assertEqual(stage_filter,(ROOT/'layout/Library/MobileSubstrate/DynamicLibraries/NoticeDeleteAnimation.plist').read_bytes())
        self.assertEqual(plistlib.loads(stage_filter),{'Filter':{'Bundles':['com.apple.springboard']}})
    def test_preferences_registration(self):
        entry=plistlib.loads((ROOT/'layout/Library/PreferenceLoader/Preferences/com.tsangbaby.noticedeleteanimation.plist').read_bytes())['entry']
        info=plistlib.loads((ROOT/'layout/Library/PreferenceBundles/NoticeDeleteAnimation.bundle/Info.plist').read_bytes())
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
    def test_alpha8_identity_is_consistent(self):
        c=dict(s.split(': ',1) for s in (ROOT/'control').read_text().splitlines() if ': ' in s)
        self.assertEqual(c['Name'],'NoticeDeleteAnimation')
        self.assertEqual(c['Author'],'Tsangbaby');self.assertEqual(c['Maintainer'],'Tsangbaby')
        self.assertEqual(c['Conflicts'],'com.example.noticelisttweak');self.assertEqual(c['Replaces'],c['Conflicts'])
        for directory in ('src','prefs','layout'):
            for p in (ROOT/directory).rglob('*'):
                if p.is_file() and p.suffix not in ('.png','.pyc'):
                    s=p.read_text()
                    self.assertNotIn('com.example.noticelisttweak',s,str(p))
                    self.assertNotIn('NoticeListTweak',s,str(p))
        self.assertIn('TWEAK_NAME = NoticeDeleteAnimation',(ROOT/'Makefile').read_text())
        self.assertIn('BUNDLE_NAME = NoticeDeleteAnimation',(ROOT/'prefs/Makefile').read_text())
    def test_alpha8_card_capture_and_banner_binding(self):
        s=(ROOT/'src/NLNotificationDismissalSnapshot.m').read_text()
        r=(ROOT/'src/NLDustRenderer.m').read_text()
        b=(ROOT/'src/NLBannerDust.m').read_text()
        w=(ROOT/'src/NLWithdrawalEffect.m').read_text()
        self.assertIn('NLNotificationCardInRow',s)
        self.assertIn('NLNotificationCardStillMatches',s)
        self.assertIn('NLNotificationOpaqueInterior',s)
        self.assertIn('[window drawViewHierarchyInRect:',s)
        self.assertIn('kCGBlendModeDestinationIn',s)
        self.assertIn('renderer.completion',s)
        self.assertIn('self.invalidated = YES',r)
        self.assertIn('status != MTLCommandBufferStatusCompleted',r)
        self.assertIn('[self removeFromSuperview]',r)
        self.assertNotIn('NLBannerFindRequest(',b)
        self.assertNotIn('notificationIdentifier',b)
        self.assertIn('NLBannerResolveRequest',b)
        self.assertIn('effect ? NO : animated',b)
        self.assertIn('NLBannerDismissInProgress = NO',b)
        self.assertIn('NLMakeRenderGeometry(cardRect',w)
        self.assertIn('cardFrame:localCard',w)
        self.assertIn('renderer.frame = rendererFrame',w)
        workflow=(ROOT/'.github/workflows/roothide-rebuild.yml').read_text()
        for name in ('test_renderer_native.sh','test_banner_native.sh','test_geometry_native.sh'):
            self.assertIn(name,workflow)
    def test_no_original_binary_fallback_or_stubs(self):
        self.assertFalse((ROOT/'pkg').exists())
        for p in (ROOT/'src').glob('*.m'):
            self.assertNotIn('stubs/',p.read_text())
            self.assertNotIn('/pkg/',p.read_text())
        workflow=(ROOT/'.github/workflows/roothide-rebuild.yml').read_text()
        self.assertIn('THEOS_PACKAGE_SCHEME=roothide',workflow)
        self.assertNotIn('continue-on-error',workflow)
if __name__=='__main__':unittest.main(verbosity=2)
