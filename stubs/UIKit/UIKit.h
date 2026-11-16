// 最小桩：仅用于 clang -fsyntax-only 语法检查，不参与真实构建。
#ifndef NL_STUB_UIKIT_H
#define NL_STUB_UIKIT_H

#import <Foundation/Foundation.h>

@protocol UICoordinateSpace <NSObject>
@property (nonatomic, readonly) CGRect bounds;
@end


typedef struct CGColor *CGColorRef;
typedef struct CGPath *CGPathRef;
typedef struct CGDataProvider *CGDataProviderRef;
typedef uint32_t CGBitmapInfo;
typedef uint32_t CGImageAlphaInfo;
enum {
    kCGImageAlphaNone = 0,
    kCGImageAlphaPremultipliedLast = 1,
    kCGImageAlphaPremultipliedFirst = 2,
    kCGImageAlphaOnly = 7,
};
enum {
    kCGBitmapByteOrderDefault = 0,
    kCGBitmapByteOrder32Little = 2 << 12,
    kCGBitmapByteOrder32Big = 4 << 12,
};

enum {
    UIViewAutoresizingNone = 0,
    UIViewAutoresizingFlexibleLeftMargin = 1 << 0,
    UIViewAutoresizingFlexibleWidth = 1 << 1,
    UIViewAutoresizingFlexibleRightMargin = 1 << 2,
    UIViewAutoresizingFlexibleTopMargin = 1 << 3,
    UIViewAutoresizingFlexibleHeight = 1 << 4,
    UIViewAutoresizingFlexibleBottomMargin = 1 << 5
};

typedef enum {
    UIGestureRecognizerStatePossible,
    UIGestureRecognizerStateBegan,
    UIGestureRecognizerStateChanged,
    UIGestureRecognizerStateEnded,
    UIGestureRecognizerStateCancelled,
    UIGestureRecognizerStateFailed,
} UIGestureRecognizerState;

typedef enum {
    UIBarButtonItemStylePlain,
    UIBarButtonItemStyleBordered,
} UIBarButtonItemStyle;

typedef enum {
    UIWindowLevelNormal = 0,
} UIWindowLevel;

@class CAAnimation, UIView, UIViewController, UIWindow, UIScreen, UIColor, UIFont, UIImage,
       CALayer, CADisplayLink, UIWindowScene, UIWindowScene, UIScene,
       UIApplication, UIGestureRecognizer, UITextView, UIImageView, UIPasteboard,
       UICollectionView, UICollectionViewCell, NSLayoutConstraint, UIBarButtonItem,
       UINavigationItem, UINavigationController;

@protocol CAAnimationDelegate <NSObject>
@optional
- (void)animationDidStop:(id)animation finished:(BOOL)flag;
@end

CGRect CGRectMake(CGFloat x, CGFloat y, CGFloat w, CGFloat h);
CGRect CGRectIntersection(CGRect a, CGRect b);
CGRect CGRectOffset(CGRect r, CGFloat dx, CGFloat dy);
CGRect CGRectInset(CGRect r, CGFloat dx, CGFloat dy);
BOOL CGRectIsNull(CGRect r);
BOOL CGRectIsEmpty(CGRect r);
BOOL CGRectIntersectsRect(CGRect a, CGRect b);
CGPoint CGPointMake(CGFloat x, CGFloat y);
CGSize CGSizeMake(CGFloat w, CGFloat h);

void UIGraphicsBeginImageContextWithOptions(CGSize size, BOOL opaque, CGFloat scale);
CGContextRef UIGraphicsGetCurrentContext(void);
UIImage *UIGraphicsGetImageFromCurrentImageContext(void);
void UIGraphicsEndImageContext(void);
void CGContextTranslateCTM(CGContextRef ctx, CGFloat tx, CGFloat ty);

size_t CGImageGetWidth(CGImageRef image);
size_t CGImageGetHeight(CGImageRef image);
uint32_t CGImageGetBitmapInfo(CGImageRef image);
CGImageAlphaInfo CGImageGetAlphaInfo(CGImageRef image);
size_t CGImageGetBitsPerPixel(CGImageRef image);
size_t CGImageGetBitsPerComponent(CGImageRef image);
size_t CGImageGetBytesPerRow(CGImageRef image);
CGDataProviderRef CGImageGetDataProvider(CGImageRef image);
CFDataRef CGDataProviderCopyData(CGDataProviderRef provider);

@interface UIColor : NSObject
+ (UIColor *)clearColor;
+ (UIColor *)systemBackgroundColor;
+ (UIColor *)labelColor;
+ (UIColor *)whiteColor;
+ (UIColor *)blackColor;
@end

@interface UIFont : NSObject
+ (UIFont *)systemFontOfSize:(CGFloat)size;
@end

@interface UIImage : NSObject
- (CGImageRef)CGImage;
- (instancetype)initWithCGImage:(CGImageRef)image;
@end

@interface UIScreen : NSObject
+ (UIScreen *)mainScreen;
- (CGRect)bounds;
- (CGFloat)scale;
@property (nonatomic, readonly) id coordinateSpace;
@end

@interface CALayer : NSObject
+ (instancetype)layer;
@property (nonatomic) CGRect frame;
@property (nonatomic) CGRect bounds;
@property (nonatomic, strong) CALayer *mask;
@property (nonatomic) CGFloat contentsScale;
@property (nonatomic) BOOL opaque;
- (void)removeAllAnimations;
- (void)addSublayer:(CALayer *)layer;
@end

@protocol MTLDrawableStub <NSObject>
@end

@protocol CAMetalDrawable <NSObject>
@property (nonatomic, readonly) id texture;
@end

@class MTLDeviceProtocolStub;
@interface CAMetalLayer : CALayer
@property (nonatomic) CGSize drawableSize;
@property (nonatomic, strong) id device;
@property (nonatomic) NSUInteger pixelFormat;
@property (nonatomic) BOOL framebufferOnly;
@property (nonatomic) NSUInteger maximumDrawableCount;
@property (nonatomic) BOOL allowsNextDrawableTimeout;
- (id<CAMetalDrawable>)nextDrawable;
@end

@interface CADisplayLink : NSObject
+ (CADisplayLink *)displayLinkWithTarget:(id)target selector:(SEL)sel;
@property (nonatomic) NSInteger preferredFramesPerSecond;
- (void)addToRunLoop:(NSRunLoop *)runloop forMode:(NSString *)mode;
- (void)invalidate;
@end

@interface UIView : NSObject
- (instancetype)initWithFrame:(CGRect)frame;
@property (nonatomic) CGRect frame;
@property (nonatomic) CGRect bounds;
@property (nonatomic) CGPoint center;
@property (nonatomic) CGFloat alpha;
@property (nonatomic, getter=isHidden) BOOL hidden;
@property (nonatomic, strong) UIColor *backgroundColor;
@property (nonatomic, getter=isOpaque) BOOL opaque;
@property (nonatomic) BOOL clipsToBounds;
@property (nonatomic) BOOL userInteractionEnabled;
@property (nonatomic) BOOL accessibilityElementsHidden;
@property (nonatomic) BOOL isAccessibilityElement;
@property (nonatomic) NSUInteger autoresizingMask;
@property (nonatomic, readonly) CALayer *layer;
@property (nonatomic, readonly, strong) UIView *superview;
@property (nonatomic, readonly, copy) NSArray *subviews;
@property (nonatomic, readonly, strong) UIWindow *window;
@property (nonatomic, readonly, strong) UIViewController *viewController;
- (void)addSubview:(UIView *)view;
- (void)removeFromSuperview;
- (BOOL)isDescendantOfView:(UIView *)view;
- (void)setNeedsLayout;
- (void)layoutIfNeeded;
- (BOOL)drawViewHierarchyInRect:(CGRect)rect afterScreenUpdates:(BOOL)after;
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view;
- (CGRect)convertRect:(CGRect)rect fromView:(UIView *)view;
- (CGRect)convertRect:(CGRect)rect toCoordinateSpace:(id)space;
- (CGRect)convertRect:(CGRect)rect fromCoordinateSpace:(id)space;
- (CGPoint)convertPoint:(CGPoint)point toView:(UIView *)view;
@end

@interface UIImageView : UIView
- (instancetype)initWithImage:(UIImage *)image;
@property (nonatomic, strong) UIImage *image;
@end

@interface UITextView : UIView
@property (nonatomic, copy) NSString *text;
@property (nonatomic) BOOL editable;
@property (nonatomic) BOOL selectable;
@property (nonatomic, strong) UIColor *textColor;
@property (nonatomic, strong) UIFont *font;
@end

@interface UIPasteboard : NSObject
+ (UIPasteboard *)generalPasteboard;
@property (nonatomic, copy) NSString *string;
@end

@interface UIGestureRecognizer : NSObject
@property (nonatomic, readonly) UIGestureRecognizerState state;
@end

@interface UIBarButtonItem : NSObject
- (instancetype)initWithTitle:(NSString *)title
                        style:(UIBarButtonItemStyle)style
                       target:(id)target
                       action:(SEL)action;
@end

@interface UINavigationItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) UIBarButtonItem *rightBarButtonItem;
@property (nonatomic, strong) UIBarButtonItem *leftBarButtonItem;
@end

@interface UIScene : NSObject
@end

@interface UIWindowScene : UIScene
@property (nonatomic, readonly) id<UICoordinateSpace> coordinateSpace;
@end

@interface UIViewController : NSObject
@property (nonatomic, strong) UIView *view;
@property (nonatomic, readonly) BOOL isViewLoaded;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, readonly) UINavigationItem *navigationItem;
@property (nonatomic, readonly, strong) UINavigationController *navigationController;
@property (nonatomic, readonly, copy) NSArray *childViewControllers;
- (void)viewWillAppear:(BOOL)animated;
- (void)viewDidAppear:(BOOL)animated;
- (void)setView:(UIView *)view;
- (void)addChildViewController:(UIViewController *)child;
@end

@interface UINavigationController : UIViewController
- (void)pushViewController:(UIViewController *)vc animated:(BOOL)animated;
@end

@interface UIWindow : UIView
@property (nonatomic, readonly) id<UICoordinateSpace> coordinateSpace;
- (instancetype)initWithWindowScene:(UIWindowScene *)scene;
- (instancetype)initWithFrame:(CGRect)frame;
@property (nonatomic) CGFloat windowLevel;
@property (nonatomic, strong) UIViewController *rootViewController;
@property (nonatomic, strong) UIScreen *screen;
@property (nonatomic, readonly) UIWindowScene *windowScene;
- (BOOL)canBecomeKeyWindow;
- (void)makeKeyAndVisible;
@end

@interface UIApplication : NSObject
+ (UIApplication *)sharedApplication;
@property (nonatomic, readonly) NSSet *connectedScenes;
@end

@interface UICollectionViewLayoutAttributes : NSObject
@end

@interface UICollectionViewCell : UIView
@end

@interface UICollectionView : UIView
- (UICollectionViewCell *)cellForItemAtIndexPath:(NSIndexPath *)path;
- (void)deleteItemsAtIndexPaths:(NSArray *)paths;
@end

BOOL UIAccessibilityIsReduceMotionEnabled(void);
double CACurrentMediaTime(void);

#endif
