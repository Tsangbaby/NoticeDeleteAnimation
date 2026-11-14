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
        self.assertIn('container.bounds = region.clipRect', source)
        self.assertIn('visibleSource(source, through: surface, window: window)', source)
        self.assertIn('handle.source?.isDescendant(of: surface) != true', source)
        self.assertIn('animation.duration = particle.duration', source)
        self.assertIn('hostVisible(window)', source)
        self.assertIn('NDAHostVisibility.allows(', source)
        self.assertIn('NDARecordEvent("capture.scene")', source)
        self.assertIn('tile.contents = cgImage', source)
        self.assertIn('$0.contents = nil', source)
        self.assertNotIn('UIWindow(', source)
        self.assertNotIn('source.alpha =', source)
        self.assertNotIn('source.isHidden =', source)
        self.assertNotIn('source.transform =', source)

    def test_diagnostics_are_allowlisted_and_install_is_idempotent(self):
        diagnostic = (ROOT / 'Sources/Bridge/NDADiagnostics.m').read_text()
        self.assertIn('[allowed containsObject:code]', diagnostic)
        self.assertIn('NSEC_PER_SEC / 2', diagnostic)
        self.assertNotIn('notificationRequest', diagnostic)
        self.assertNotIn('descriptionWithLocale', diagnostic)
        bridge = (ROOT / 'Sources/Bridge/NDABridge.m').read_text()
        for capability in ('top', 'group', 'two', 'three'):
            self.assertIn('!' + capability + 'Installed', bridge)
        self.assertNotIn('else if (modern2)', bridge)
        entry = (ROOT / 'Sources/Tweak/Entry.swift').read_text()
        self.assertIn('retries >= 60', entry)
        self.assertIn('timer?.invalidate()', entry)

    def test_settings_registration_and_domain(self):
        prefs = ROOT / 'Preferences'
        info = plistlib.loads((prefs / 'Resources/Info.plist').read_bytes())
        entry = plistlib.loads((ROOT / 'layout/Library/PreferenceLoader/Preferences/NoticeDeleteAnimation.plist').read_bytes())['entry']
        self.assertEqual(info['NSPrincipalClass'], 'NDASettingsController')
        self.assertEqual(entry['bundle'], info['CFBundleExecutable'])
        self.assertIs(entry['isController'], True)
        self.assertEqual(entry.get('detail'), info['NSPrincipalClass'])
        self.assertEqual(info['MinimumOSVersion'], '15.0')
        source = (prefs / 'NDASettingsController.swift').read_text()
        for key in ('DiagnosticsSummary', 'DiagnosticsUpdated', 'DiagnosticsPID'):
            self.assertIn(key, source)
        self.assertIn('com.tsangbaby.noticedeleteanimation', source)
        self.assertIn('SUBPROJECTS += Preferences', (ROOT / 'Makefile').read_text())
        self.assertIn('super.specifiers = items', source)
        self.assertIn('super.specifiers = newValue', source)
        self.assertLess(source.index('specifiers = NDAMakeSettingsSpecifiers'), source.index('super.viewDidLoad()'))
        factory = (prefs / 'NDAPreferencesBridge.m').read_text()
        self.assertIn('general, enabled, diagnostics, refresh, privacy, nil', factory)

    def test_production_gate_and_metadata(self):
        gate = (ROOT / 'Sources/Tweak/AncestorGate.swift').read_text()
        animator = (ROOT / 'Sources/Tweak/Animator.swift').read_text()
        writer = (ROOT / 'Sources/Bridge/NDADiagnostics.m').read_text()
        harness = (ROOT / 'Scripts/test_ancestors_native.sh').read_text()
        for reason in ('hidden', 'alpha', 'transform', 'sublayer', 'mask', 'animations', 'clipping', 'depth', 'hierarchy'):
            self.assertIn('ancestor.' + reason, writer)
            self.assertIn('.' + reason, gate)
        self.assertIn('NDAVisibleRegionPlanner.resolve(source', animator)
        self.assertIn('Sources/Tweak/AncestorGate.swift', harness)
        self.assertIn('Sources/Bridge/NDADiagnostics.m', harness)
        self.assertIn('depth < 64', gate)
        self.assertIn('effectiveAlpha >= 0.99', gate)
        self.assertIn('insetBy(dx: -0.5, dy: -0.5)', gate)
        self.assertIn('name.length > 80', writer)
        self.assertIn('/System/Library/', writer)
        self.assertIn('[ancestorCodes containsObject:code]', writer)
        self.assertIn('NoticeDeleteAnimation alpha7', writer)
        self.assertNotIn('view.description', writer)
        bridge = (ROOT / 'Sources/Bridge/NDABridge.m').read_text()
        for variant in ('2', '3'):
            self.assertEqual(bridge.count('originalListRemoval' + variant + '(self, cmd, index, handle ? NO : animated'), 1)

    def test_alpha6_geometry_uses_unchanged_predicate_operands(self):
        gate = (ROOT / 'Sources/Tweak/AncestorGate.swift').read_text()
        writer = (ROOT / 'Sources/Bridge/NDADiagnostics.m').read_text()
        animator = (ROOT / 'Sources/Tweak/Animator.swift').read_text()
        header = (ROOT / 'Sources/Bridge/NDABridge.h').read_text()
        self.assertIn('let sourceBounds = source.bounds', gate)
        self.assertIn('let ancestorBounds = view.bounds', gate)
        self.assertIn('let rect = source.convert(sourceBounds, to: view)', gate)
        self.assertIn('!ancestorBounds.insetBy(dx: -0.5, dy: -0.5).contains(rect)', gate)
        self.assertIn('sourceBounds: sourceBounds, sourceInAncestor: rect, ancestorBounds: ancestorBounds', gate)
        self.assertIn('NDARecordClippingFailure', header)
        self.assertIn('geometry.sourceBounds, geometry.sourceInAncestor, geometry.ancestorBounds', animator)
        for field in ('source_bounds=', 'ancestor_bounds=', 'source_in_ancestor=',
                      'local_intersection=', 'edge_overflow_ltrb=', 'local_overlap_permille=',
                      'contains_half_pt=', 'clamped='):
            self.assertIn(field, writer)
        self.assertIn('MAX(-32768, MIN(32768, value))', writer)
        self.assertIn('return @"invalid"', writer)
        self.assertIn('lastClipping = nil', writer)
        self.assertIn('clipping = lastClipping', writer)
        for bad in ('NSStringFromCGRect(', 'contentOffset =', 'setClipsToBounds:', 'CGRectOffset('):
            self.assertNotIn(bad, writer)
        self.assertNotIn('CSScrollView', gate)
        self.assertNotIn('contentOffset', gate)
        harness = (ROOT / 'Scripts/test_ancestors_native.sh').read_text()
        self.assertIn('1e6b54ed910cc307103698af0224e26667a32caa', harness)
        self.assertIn('73efa1ada05f13d0d8950e673406136794c7855f5b8b7ffe613e9dc0b9b72356', harness)
        self.assertIn('"$work/alpha5-baseline.swift"', harness)
        self.assertIn('exit 1', harness)
        self.assertNotIn('exit 0', harness)

    def test_alpha7_full_chain_crop_and_lifecycle_contract(self):
        planner = (ROOT / 'Sources/Tweak/VisibleRegion.swift').read_text()
        capture = (ROOT / 'Sources/Bridge/NDACapture.m').read_text()
        animator = (ROOT / 'Sources/Tweak/Animator.swift').read_text()
        bridge = (ROOT / 'Sources/Bridge/NDABridge.m').read_text()
        writer = (ROOT / 'Sources/Bridge/NDADiagnostics.m').read_text()
        workflow = (ROOT / '.github/workflows/roothide.yml').read_text()
        for required in ('NDAVisibleRegionPlanner.resolve(source', 'inwardAligned(scale: desiredScale',
                         'NDACaptureRegion(source, region.sourceRect, desiredScale)',
                         'region.isCaptureValid(source: source, surface: surface, window: window)',
                         'checkedAligned.sourceRect == region.sourceRect',
                         'checkedAligned.surfaceRect == region.surfaceRect',
                         'checkedAligned.clipRect == region.clipRect',
                         'handle.region.isValid(surface: surface, window: window)',
                         'handle.source?.window == nil', 'cgImage.width == width',
                         'container.bounds = region.clipRect'):
            self.assertIn(required, animator)
        self.assertNotIn('NDACaptureView(source', animator)
        self.assertNotIn('source.convert(source.bounds, to: surface)', animator)
        self.assertNotIn('source.alpha =', animator)
        for required in ('NDARecordRegionPrepared', 'Prepared region:', 'capture.partial',
                         'capture.full', 'source_crop=', 'surface_crop=', 'safe_clip='):
            self.assertIn(required, writer)
        for required in ('region.origin.x < bounds.origin.x', 'pixelWidth != floor(pixelWidth)',
                         'bounds.origin.x - region.origin.x', 'CGContextClipToRect',
                         'drawViewHierarchyInRect:target', 'CGImageGetWidth(cgImage) !='):
            self.assertIn(required, capture)
        for forbidden in ('renderInContext:', 'snapshotViewAfterScreenUpdates:', 'source.transform ='):
            self.assertNotIn(forbidden, capture)
        self.assertNotIn('UIGraphicsImageRenderer', bridge)
        self.assertIn('weak var view:', planner)
        self.assertIn('isCaptureValid', planner)
        self.assertIn('layer.masksToBounds', planner)
        self.assertIn('cornerRadius', planner)
        self.assertNotIn('CSScrollView', planner)
        self.assertNotIn('contentOffset =', planner)
        for script in ('test_visible_region_native.sh', 'test_capture_native.sh', 'test_partial_native.sh'):
            self.assertIn(script, workflow)
        self.assertIn('fix/partial-visibility-alpha7', workflow)

    def test_no_persistence_or_content_logging(self):
        for path in list((ROOT / 'Sources').rglob('*.swift')) + list((ROOT / 'Sources').rglob('*.m')):
            source = path.read_text()
            for forbidden in ('NSLog(', 'print(', 'UIImageWriteToSavedPhotosAlbum', 'pngData(', 'jpegData(', 'URLSession', 'write(to:'):
                self.assertNotIn(forbidden, source, f'{path}: {forbidden}')

if __name__ == '__main__':
    unittest.main(verbosity=2)
