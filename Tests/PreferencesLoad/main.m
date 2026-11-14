// Real simulator UIKit/Preferences test; never substitutes a fake superclass.
#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

static void require(BOOL ok, NSString *message) {
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
int main(int argc, char **argv) {
    @autoreleasepool {
        require(argc == 4, @"arguments: bundle registration mode");
        NSString *path = @(argv[1]);
        NSDictionary *entry = [NSDictionary dictionaryWithContentsOfFile:@(argv[2])][@"entry"];
        BOOL old = [@(argv[3]) isEqual:@"old"];
        NSBundle *bundle = [NSBundle bundleWithPath:path];
        PSListController *root = [PSListController new];
        typedef NSArray *(*Parse)(NSDictionary *, id, id, NSString *, NSBundle *, NSString **, NSString **, PSListController *, NSMutableArray **);
        Parse parse = (Parse)dlsym(RTLD_DEFAULT, "SpecifiersFromPlist");
        require(parse != NULL, @"real Preferences parser present");
        NSMutableDictionary *localEntry = [entry mutableCopy];
        localEntry[@"bundlePath"] = path;
        NSMutableArray *controllers = nil;
        NSArray *specs = parse(@{@"items":@[localEntry]}, nil, root, @"NoticeDeleteAnimation", bundle, NULL, NULL, root, &controllers);
        require(specs.count == 1, @"real parser returned entry");
        PSSpecifier *s = specs[0];
        // Same lazy-bundle property assignment as official prefs.xm:460-463.
        NSString **lazyKey = dlsym(RTLD_DEFAULT, "PSLazilyLoadedBundleKey");
        require(lazyKey != NULL, @"lazy-load key available");
        [s setProperty:path forKey:*lazyKey];
        SEL lazy = NSSelectorFromString(@"lazyLoadBundle:");
        require([root respondsToSelector:lazy], @"system lazy loader available");
        ((void(*)(id,SEL,id))objc_msgSend)(root,lazy,s);
        NSError *error = nil;
        require(bundle.isLoaded || [bundle loadAndReturnError:&error], [error description] ?: @"bundle loaded");
        Class principal = bundle.principalClass;
        require([NSStringFromClass(principal) isEqual:@"NDASettingsController"], @"Swift @objc principalClass resolved");
        SEL detail = NSSelectorFromString(@"detailControllerClass");
        Class selected = [s respondsToSelector:detail] ? ((Class(*)(id,SEL))objc_msgSend)(s,detail) : object_getIvar(s, class_getInstanceVariable([s class], "detailControllerClass"));
        fprintf(stdout, "REGISTRATION mode=%s selected=%s principal=%s\n", argv[3], NSStringFromClass(selected).UTF8String ?: "nil", NSStringFromClass(principal).UTF8String);
        if (!old) require(selected == principal, @"system selected exact Swift controller, not generic fallback");
        // Exercise principal even when old registration selects a generic controller.
        PSListController *controller = [principal new];
        controller.specifier = s;
        NSMutableArray *items = controller.specifiers;
        require(items.count == 5, @"static rows with empty diagnostics");
        Ivar ivar = class_getInstanceVariable([PSListController class], "_specifiers");
        require(ivar != NULL, @"real superclass has model ivar");
        id model = object_getIvar(controller, ivar);
        if (old) {
            require(model != items, @"negative alpha3 Swift cache diverges from superclass model");
            puts("PASS negative alpha3: missing explicit detail and detached superclass model reproduced");
            return 0;
        }
        require(model == items, @"getter updates superclass model");
        [controller loadViewIfNeeded];
        [controller viewWillAppear:NO];
        require(controller.navigationItem.rightBarButtonItem != nil, @"Swift lifecycle installed refresh");
        require(controller.specifiers.count == 5, @"rows after lifecycle");
        ((void(*)(id,SEL))objc_msgSend)(controller, NSSelectorFromString(@"nda_refreshDiagnostics"));
        require(controller.specifiers.count == 5, @"rows after explicit refresh");
        require(object_getIvar(controller,ivar) == controller.specifiers, @"refresh model stays synchronized");
        require([controller numberOfGroups] == 3, @"three actual Preferences groups");
        require([controller rowsForGroup:0] == 1 && [controller rowsForGroup:1] == 1, @"Enabled and refresh table rows");
        puts("PASS real UIKit/Preferences registration, principal, lifecycle, empty-domain static rows, refresh and superclass table model");
        return 0;
    }
}
