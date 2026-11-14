#import "NDABridge.h"
#import <math.h>

// These are allocation guards, not a substitute for the caller's full-chain
// visibility decision. No parent/window snapshot or layer-render fallback.
static BOOL NDAFiniteCaptureRect(CGRect rect) {
    CGFloat right = rect.origin.x + rect.size.width;
    CGFloat bottom = rect.origin.y + rect.size.height;
    return isfinite(rect.origin.x) && isfinite(rect.origin.y) &&
        isfinite(rect.size.width) && isfinite(rect.size.height) &&
        rect.size.width > 0 && rect.size.height > 0 &&
        isfinite(right) && isfinite(bottom) &&
        right > rect.origin.x && bottom > rect.origin.y;
}

UIImage * _Nullable NDACaptureRegion(UIView *view, CGRect region, CGFloat scale) {
    // Do not even ask a UIView for geometry off the main thread.
    if (!NSThread.isMainThread || !view || !isfinite(scale) || scale <= 0 || scale > 2) return nil;
    @try {
        CGRect bounds = view.bounds;
        if (!NDAFiniteCaptureRect(bounds) || !NDAFiniteCaptureRect(region) ||
            bounds.size.width > 2048 || bounds.size.height > 2048) return nil;
        // Exact source-local containment: never standardize, intersect, expand,
        // or tolerate an epsilon that could admit hidden notification pixels.
        if (region.origin.x < bounds.origin.x || region.origin.y < bounds.origin.y ||
            region.origin.x + region.size.width > bounds.origin.x + bounds.size.width ||
            region.origin.y + region.size.height > bounds.origin.y + bounds.size.height) return nil;

        CGFloat pixelWidth = region.size.width * scale;
        CGFloat pixelHeight = region.size.height * scale;
        // The caller rounds inward first. Reject non-integral extents rather
        // than asking UIKit to round outward into an extra edge pixel. Origins
        // remain source-local (including nonzero/negative bounds origins).
        if (!isfinite(pixelWidth) || !isfinite(pixelHeight) ||
            pixelWidth < 1 || pixelHeight < 1 || pixelWidth > 4096 || pixelHeight > 4096 ||
            pixelWidth != floor(pixelWidth) || pixelHeight != floor(pixelHeight) ||
            ceil(pixelWidth) * ceil(pixelHeight) > 220000) return nil;

        CGRect target = (CGRect){
            {bounds.origin.x - region.origin.x, bounds.origin.y - region.origin.y},
            bounds.size
        };
        if (!isfinite(target.origin.x) || !isfinite(target.origin.y)) return nil;
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
        format.scale = scale;
        format.opaque = NO;
        format.preferredRange = UIGraphicsImageRendererFormatRangeStandard;
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:region.size format:format];
        __block BOOL drawn = NO;
        UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            CGContextRef cg = context.CGContext;
            if (!cg) return;
            CGContextSaveGState(cg);
            @try {
                CGContextClipToRect(cg, (CGRect){CGPointZero, region.size});
                // Do not interpolate a full-view backing across the crop boundary:
                // a reconstruction filter can mix hidden-side texels into edge pixels.
                // Tile filtering later samples ONLY this cropped backing.
                CGContextSetInterpolationQuality(cg, kCGInterpolationNone);
                CGContextSetShouldAntialias(cg, NO);
                // Draw the FULL source at its original logical size, translated
                // so region.min maps to output zero. Drawing only region.size
                // here would rescale hidden source content into the crop.
                drawn = [view drawViewHierarchyInRect:target afterScreenUpdates:NO];
            } @finally {
                CGContextRestoreGState(cg);
            }
        }];
        CGImageRef cgImage = image.CGImage;
        if (!drawn || !cgImage || CGImageGetWidth(cgImage) != (size_t)pixelWidth ||
            CGImageGetHeight(cgImage) != (size_t)pixelHeight) return nil;
        return image;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

UIImage * _Nullable NDACaptureView(UIView *view, CGFloat scale) {
    if (!NSThread.isMainThread || !view) return nil;
    @try {
        return NDACaptureRegion(view, view.bounds, scale);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}
