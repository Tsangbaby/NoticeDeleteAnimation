#ifndef NL_STUB_PSLISTCONTROLLER_H
#define NL_STUB_PSLISTCONTROLLER_H
#include <UIKit/UIKit.h>
@class PSSpecifier;
@interface PSListController : UIViewController
{
    NSArray *_specifiers;
}
@property (nonatomic, strong) NSArray *specifiers;
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target bundle:(NSBundle *)bundle;
- (id)readPreferenceValue:(PSSpecifier *)specifier;
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
@end
#endif
