// 最小桩：仅用于 clang -fsyntax-only 语法检查，不参与真实构建。
#ifndef NL_STUB_FOUNDATION_H
#define NL_STUB_FOUNDATION_H

#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>
#include <stdbool.h>

typedef long NSInteger;
typedef unsigned long NSUInteger;
typedef double CGFloat;
typedef signed char BOOL;
#define YES ((BOOL)1)
#define NO  ((BOOL)0)
#define nil ((id)0)
#define MIN(a,b) ((a)<(b)?(a):(b))
#define MAX(a,b) ((a)>(b)?(a):(b))
unsigned int arc4random_uniform(unsigned int upper_bound);
#define NSNotFound ((NSInteger)0x7fffffffffffffffL)
#define Nil ((Class)0)
#define NULL ((void *)0)
#define FOUNDATION_EXPORT extern
#define NS_ASSUME_NONNULL_BEGIN
#define NS_ASSUME_NONNULL_END
#define NS_ENUM(t,n) enum n : t n; enum n : t
#define NS_OPTIONS(t,n) enum n : t n; enum n : t

typedef struct { CGFloat x, y; } CGPoint;
typedef struct { CGFloat width, height; } CGSize;
typedef struct { CGPoint origin; CGSize size; } CGRect;
static const CGRect CGRectZero = {{0, 0}, {0, 0}};

typedef struct CGImage *CGImageRef;
typedef struct CGContext *CGContextRef;
typedef struct __CFString *CFStringRef;
typedef struct __CFType *CFTypeRef;
typedef const void *CFPropertyListRef;
typedef struct __CFData *CFDataRef;
typedef struct __CFNumber *CFNumberRef;
typedef struct __CFBoolean *CFBooleanRef;
typedef struct __CFNotificationCenter *CFNotificationCenterRef;
typedef struct __CFAllocator *CFAllocatorRef;

typedef NSInteger CFIndex;
typedef unsigned long CFOptionFlags;
typedef long CFTypeID;
typedef double CFTimeInterval;

enum { kCFNumberDoubleType = 13 };
enum { kCFNumberSInt32Type = 3 };

typedef struct {
    NSUInteger state;
    __unsafe_unretained id *itemsPtr;
    unsigned long *mutationsPtr;
    NSUInteger extra[5];
} NSFastEnumerationState;

@protocol NSFastEnumeration
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                  objects:(id *)buffer
                                    count:(NSUInteger)len;
@end

@class NSString;

@protocol NSObject
- (BOOL)respondsToSelector:(SEL)sel;
- (id)performSelector:(SEL)sel;
- (id)performSelector:(SEL)sel withObject:(id)obj;
- (id)performSelector:(SEL)sel withObject:(id)a withObject:(id)b;
- (BOOL)isKindOfClass:(Class)cls;
- (Class)class;
- (id)copy;
@end

__attribute__((objc_root_class))
@interface NSObject <NSObject>
+ (instancetype)alloc;
+ (instancetype)new;
+ (Class)class;
+ (BOOL)isSubclassOfClass:(Class)cls;
- (instancetype)init;
- (void)dealloc;
- (id)retain;
- (oneway void)release;
- (id)autorelease;
- (NSUInteger)hash;
- (BOOL)isEqual:(id)obj;
- (id)description;
- (id)debugDescription;
- (Class)superclass;
+ (void)cancelPreviousPerformRequestsWithTarget:(id)target;
+ (void)cancelPreviousPerformRequestsWithTarget:(id)target selector:(SEL)sel object:(id)obj;
- (void)performSelector:(SEL)sel withObject:(id)obj afterDelay:(double)delay;
- (void)performSelectorOnMainThread:(SEL)sel withObject:(id)obj waitUntilDone:(BOOL)wait;
@end

void NSLog(NSString *format, ...);

@interface NSString : NSObject
+ (instancetype)stringWithUTF8String:(const char *)s;
+ (instancetype)stringWithFormat:(NSString *)fmt, ...;
- (NSUInteger)length;
- (BOOL)isEqualToString:(NSString *)s;
- (NSString *)substringToIndex:(NSUInteger)index;
- (NSString *)stringByAppendingFormat:(NSString *)fmt, ...;
- (BOOL)boolValue;
- (double)doubleValue;
- (unsigned long)unsignedIntegerValue;
- (const char *)UTF8String;
@end

@interface NSMutableString : NSString
+ (instancetype)string;
- (void)appendString:(NSString *)s;
- (void)appendFormat:(NSString *)fmt, ...;
@end

@interface NSNumber : NSObject
+ (NSNumber *)numberWithBool:(BOOL)v;
+ (NSNumber *)numberWithInt:(int)v;
+ (NSNumber *)numberWithUnsignedLong:(unsigned long)v;
+ (NSNumber *)numberWithUnsignedInteger:(NSUInteger)v;
+ (NSNumber *)numberWithDouble:(double)v;
- (BOOL)boolValue;
- (int)intValue;
- (unsigned long)unsignedIntegerValue;
- (double)doubleValue;
@end

@interface NSArray<__covariant ObjectType> : NSObject <NSFastEnumeration>
+ (instancetype)array;
+ (instancetype)arrayWithObjects:(const id [])objects count:(NSUInteger)cnt;
- (NSUInteger)count;
- (id)objectAtIndexedSubscript:(NSUInteger)idx;
- (NSUInteger)indexOfObjectIdenticalTo:(id)obj;
- (id)firstObject;
@end

@interface NSMutableArray<__covariant ObjectType> : NSArray<ObjectType>
- (void)addObject:(id)obj;
- (void)removeObject:(id)obj;
- (void)removeObjectIdenticalTo:(id)obj;
@end

@interface NSDictionary<__covariant KeyType, __covariant ObjectType> : NSObject <NSFastEnumeration>
+ (instancetype)dictionary;
+ (instancetype)dictionaryWithObjects:(const id [])objects
                              forKeys:(const id [])keys
                                count:(NSUInteger)cnt;
+ (instancetype)dictionaryWithContentsOfFile:(NSString *)path;
- (id)objectForKeyedSubscript:(id)key;
- (NSArray *)allValues;
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)flag;
@end

@interface NSMutableDictionary<__covariant KeyType, __covariant ObjectType> : NSDictionary<KeyType, ObjectType>
- (void)setObject:(id)obj forKeyedSubscript:(id)key;
@end

@interface NSSet<__covariant ObjectType> : NSObject <NSFastEnumeration>
- (NSUInteger)count;
- (BOOL)containsObject:(id)obj;
@end

@interface NSMutableSet<ObjectType> : NSSet<ObjectType>
+ (NSMutableSet *)set;
- (void)addObject:(id)obj;
- (void)removeObject:(id)obj;
@end

@interface NSHashTable<__covariant ObjectType> : NSObject <NSFastEnumeration>
+ (instancetype)hashTableWithOptions:(NSUInteger)options;
- (void)addObject:(id)obj;
- (BOOL)containsObject:(id)obj;
- (NSUInteger)count;
@end

@interface NSValue : NSObject
@end

@interface NSDate : NSObject
+ (instancetype)date;
- (double)timeIntervalSince1970;
@end

@interface NSBundle : NSObject
+ (NSBundle *)mainBundle;
+ (NSBundle *)bundleForClass:(Class)cls;
- (NSString *)bundleIdentifier;
- (NSString *)pathForResource:(NSString *)name ofType:(NSString *)ext;
@end

@interface NSThread : NSObject
+ (BOOL)isMainThread;
+ (void)detachNewThreadSelector:(SEL)sel toTarget:(id)target withObject:(id)arg;
@end

@interface NSRunLoop : NSObject
+ (NSRunLoop *)mainRunLoop;
@end

@interface NSError : NSObject
- (NSString *)localizedDescription;
@end

@interface NSException : NSObject
- (NSString *)name;
- (NSString *)reason;
@end

@interface NSNotification : NSObject
@end

@interface NSNotificationCenter : NSObject
+ (NSNotificationCenter *)defaultCenter;
- (void)addObserver:(id)observer selector:(SEL)sel name:(NSString *)name object:(id)obj;
- (void)removeObserver:(id)observer name:(NSString *)name object:(id)obj;
@end

@interface NSIndexPath : NSObject
@end

@interface NSMutableIndexSet : NSObject
@end

extern NSString *const NSRunLoopCommonModes;
extern NSString *const UIApplicationDidFinishLaunchingNotification;
extern NSString *const UIApplicationDidBecomeActiveNotification;

FOUNDATION_EXPORT NSString *NSStringFromClass(Class cls);
FOUNDATION_EXPORT Class NSClassFromString(NSString *name);
FOUNDATION_EXPORT SEL NSSelectorFromString(NSString *name);
FOUNDATION_EXPORT NSString *NSStringFromCGRect(CGRect rect);

FOUNDATION_EXPORT CFStringRef __bridge_cf(NSString *);
#define CFSTR(x) ((CFStringRef)(x))

CFTypeID CFGetTypeID(CFTypeRef cf);
CFTypeID CFBooleanGetTypeID(void);
CFTypeID CFNumberGetTypeID(void);
BOOL CFBooleanGetValue(CFBooleanRef b);
BOOL CFNumberGetValue(CFNumberRef n, long type, void *value);
void CFRelease(CFTypeRef cf);
CFStringRef CFRetain(CFTypeRef cf);
CFTypeRef CFPreferencesCopyAppValue(CFStringRef key, CFStringRef appID);
void CFPreferencesSetAppValue(CFStringRef key, CFPropertyListRef value, CFStringRef appID);
BOOL CFPreferencesAppSynchronize(CFStringRef appID);
CFNotificationCenterRef CFNotificationCenterGetDarwinNotifyCenter(void);
void CFNotificationCenterPostNotification(CFNotificationCenterRef center, CFStringRef name,
                                          const void *object, CFTypeRef userInfo,
                                          BOOL deliverImmediately);
CFIndex CFDataGetLength(CFDataRef data);
const unsigned char *CFDataGetBytePtr(CFDataRef data);


// --- GCD / blocks 最小声明 ---
typedef long dispatch_once_t;
typedef void *dispatch_queue_t;
void dispatch_once(dispatch_once_t *predicate, void (^block)(void));

#endif
