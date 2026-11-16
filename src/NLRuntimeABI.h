// Exact call ABI helpers for reconstructed runtime dispatch. No selector probing
// may reinterpret a scalar as an Objective-C object under ARC.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <string.h>
#include <stdlib.h>

static inline const char *NLABIUnqualified(const char *type) {
    if (!type) return "";
    while (*type && strchr("rnNoORV", *type)) ++type;
    return type;
}
static inline BOOL NLABITypeMatches(const char *actual, const char *expected) {
    const char *type = NLABIUnqualified(actual);
    if (strcmp(expected, "@") == 0) return type[0] == '@' && type[1] != '?';
    if (strcmp(expected, "@?") == 0) return strcmp(type, "@?") == 0;
    if (strcmp(expected, "B") == 0) return strcmp(type, "B") == 0 || strcmp(type, "c") == 0;
    return strcmp(type, expected) == 0;
}
static inline BOOL NLABIMethod(Class cls, SEL selector, const char *result,
                               unsigned int count, const char *const *arguments) {
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!method || method_getNumberOfArguments(method) != count + 2) return NO;
    char *type = method_copyReturnType(method);
    BOOL valid = type && NLABITypeMatches(type, result);
    free(type);
    for (unsigned int i = 0; valid && i < count; ++i) {
        type = method_copyArgumentType(method, i + 2);
        valid = type && NLABITypeMatches(type, arguments[i]);
        free(type);
    }
    return valid;
}
static inline BOOL NLABIReadBool(id object, SEL selector) {
    if (!object || !NLABIMethod(object_getClass(object), selector, "B", 0, NULL)) return NO;
    return ((BOOL (*)(id, SEL))[object methodForSelector:selector])(object, selector);
}
