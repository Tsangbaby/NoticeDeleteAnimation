#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

NS_ASSUME_NONNULL_BEGIN
// Use the toolchain's real Preferences declarations, never a fake superclass ABI.
FOUNDATION_EXPORT NSMutableArray<PSSpecifier *> *NDAMakeSettingsSpecifiers(
    PSListController *target, NSString *diagnosticsFooter);
NS_ASSUME_NONNULL_END
