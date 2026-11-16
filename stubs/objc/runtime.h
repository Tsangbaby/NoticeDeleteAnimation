// 最小桩：仅用于 clang -fsyntax-only 语法检查。
#ifndef NL_STUB_OBJC_RUNTIME_H
#define NL_STUB_OBJC_RUNTIME_H

#include <stddef.h>
#include <stdint.h>

typedef struct objc_class *Class;
typedef struct objc_object { Class isa; } *id;
typedef struct objc_selector *SEL;
typedef struct objc_method *Method;
typedef struct objc_ivar *Ivar;
typedef void (*IMP)(void);

typedef enum {
    OBJC_ASSOCIATION_ASSIGN = 0,
    OBJC_ASSOCIATION_RETAIN_NONATOMIC = 1,
    OBJC_ASSOCIATION_COPY_NONATOMIC = 3,
    OBJC_ASSOCIATION_RETAIN = 01401,
    OBJC_ASSOCIATION_COPY = 01403,
} objc_AssociationPolicy;

typedef enum {
    NSPointerFunctionsStrongMemory = 0,
    NSPointerFunctionsOpaqueMemory = 2,
    NSPointerFunctionsObjectPointerPersonality = 4,
    NSPointerFunctionsWeakMemory = 5 << 8,
} NSPointerFunctionsOptions;

Class object_getClass(id obj);
Class class_getSuperclass(Class cls);
Method class_getInstanceMethod(Class cls, SEL name);
Method class_getClassMethod(Class cls, SEL name);
unsigned int method_getNumberOfArguments(Method m);
char *method_copyReturnType(Method m);
char *method_copyArgumentType(Method m, unsigned int index);
const char *method_getTypeEncoding(Method m);
IMP method_getImplementation(Method m);
IMP class_getMethodImplementation(Class cls, SEL name);
BOOL class_addMethod(Class cls, SEL name, IMP imp, const char *types);
BOOL class_respondsToSelector(Class cls, SEL sel);
void objc_setAssociatedObject(id object, const void *key, id value, objc_AssociationPolicy policy);
id objc_getAssociatedObject(id object, const void *key);
void objc_removeAssociatedObjects(id object);
id objc_retain(id obj);
void objc_release(id obj);
id objc_autorelease(id obj);
id objc_retainAutoreleasedReturnValue(id obj);
id objc_autoreleaseReturnValue(id obj);
id objc_retainAutorelease(id obj);
void objc_storeStrong(id *location, id obj);
void objc_destroyWeak(id *location);
id objc_loadWeakRetained(id *location);
id objc_storeWeak(id *location, id obj);
id objc_begin_catch(void *exc_buf);
void objc_end_catch(void);
void objc_exception_rethrow(void);
void objc_enumerationMutation(id obj);
Class objc_getClass(const char *name);
const char *class_getName(Class cls);

#endif
