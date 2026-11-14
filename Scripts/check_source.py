#!/usr/bin/env python3
"""Local grammar/metadata/contract checks, NOT a Swift typecheck or iOS build."""
from pathlib import Path
import json
import plistlib
import unittest
from tree_sitter import Language, Parser
import tree_sitter_swift

ROOT = Path(__file__).resolve().parents[1]

class SourceContracts(unittest.TestCase):
    def test_swift_grammar(self):
        parser = Parser(Language(tree_sitter_swift.language()))
        paths = sorted(ROOT.rglob('*.swift'))
        self.assertGreaterEqual(len(paths), 7)
        for path in paths:
            tree = parser.parse(path.read_bytes())
            bad = []
            def walk(node):
                if node.type == 'ERROR' or node.is_missing:
                    bad.append((node.type, node.start_point, node.end_point))
                for child in node.children:
                    walk(child)
            walk(tree.root_node)
            self.assertEqual(bad, [], str(path.relative_to(ROOT)))

    def test_metadata(self):
        fields = dict(line.split(': ', 1) for line in (ROOT / 'control').read_text().splitlines())
        self.assertEqual(fields['Package'], 'com.tsangbaby.noticedeleteanimation')
        self.assertEqual(fields['Name'], 'NoticeDeleteAnimation')
        self.assertEqual(fields['Author'], 'Tsangbaby')
        self.assertEqual(fields['Maintainer'], 'Tsangbaby')
        self.assertIn('firmware (>= 15.0)', fields['Depends'])

    def test_injection_filter(self):
        data = plistlib.loads((ROOT / 'NoticeDeleteAnimation.plist').read_bytes())
        self.assertEqual(data, {'Filter': {'Bundles': ['com.apple.springboard']}})

    def test_build_target_and_languages(self):
        source = (ROOT / 'Makefile').read_text()
        self.assertIn('TARGET = iphone:clang:latest:15.0', source)
        self.assertIn('ARCHS = arm64 arm64e', source)
        self.assertIn('SWIFT_VERSION = 5', source)
        self.assertIn('SWIFT_BRIDGING_HEADER = Sources/Bridge/NDABridge.h', source)
        self.assertNotIn('Orion', source)

    def test_hook_scope_and_originals(self):
        source = (ROOT / 'Sources/Bridge/NDABridge.m').read_text()
        self.assertIn('request != scope.request', source)
        self.assertIn('removeNotificationRequest:', source)
        self.assertIn('method_getNumberOfArguments', source)
        self.assertIn('method_copyArgumentType', source)
        self.assertIn('@finally { [scopes removeLastObject]; }', source)
        self.assertNotIn('viewWillDisappear', source)
        self.assertNotIn('method_exchangeImplementations', source)
        self.assertNotIn('objc_setAssociatedObject', source)
        self.assertNotIn('deleteItemsAtIndexPaths:', source)
        self.assertNotIn('deleteSections:', source)
        self.assertIn('@"contentViewController"', source)
        self.assertIn('@"NCNotificationGroupList"', source)

    def test_renderer_bounded_and_local(self):
        source = (ROOT / 'Sources/Tweak/Animator.swift').read_text()
        self.assertIn('admission.admit(', source)
        self.assertIn('admission.expire(', source)
        self.assertIn('admission.release(', source)
        self.assertIn('UIAccessibility.isReduceMotionEnabled', source)
        self.assertIn('container.bounds = surface.bounds', source)
        self.assertIn('visibleSource(source, through: surface, window: window)', source)
        self.assertIn('handle.source?.isDescendant(of: surface) != true', source)
        self.assertIn('animation.duration = particle.duration', source)
        self.assertIn('window.windowScene?.activationState == .foregroundActive', source)
        self.assertIn('tile.contents = cgImage', source)
        self.assertIn('$0.contents = nil', source)
        self.assertNotIn('UIWindow(', source)
        self.assertNotIn('source.alpha =', source)
        self.assertNotIn('source.isHidden =', source)
        self.assertNotIn('source.transform =', source)

    def test_no_persistence_or_content_logging(self):
        for path in list((ROOT / 'Sources').rglob('*.swift')) + list((ROOT / 'Sources').rglob('*.m')):
            source = path.read_text()
            for forbidden in ('NSLog(', 'print(', 'UIImageWriteToSavedPhotosAlbum', 'pngData(', 'jpegData(', 'URLSession', 'write(to:'):
                self.assertNotIn(forbidden, source, f'{path}: {forbidden}')

if __name__ == '__main__':
    unittest.main(verbosity=2)
