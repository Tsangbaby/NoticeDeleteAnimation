#ifndef NL_STUB_PSSPECIFIER_H
#define NL_STUB_PSSPECIFIER_H
#include <Foundation/Foundation.h>
@interface PSSpecifier : NSObject
- (id)propertyForKey:(NSString *)key;
- (void)setProperty:(id)value forKey:(NSString *)key;
@end
#endif
