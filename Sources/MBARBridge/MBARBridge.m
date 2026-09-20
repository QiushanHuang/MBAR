// Runtime bridge adapted from Pelmet MBAssessmentShim.m.
// Copyright (c) 2026 Gabriel Faucon; MBAR modifications 2026.
// GPL-3.0: see LICENSE and THIRD_PARTY_NOTICES.md.
#import "MBARBridge.h"
#import <dlfcn.h>
#import <objc/message.h>
static Class configClass, assertionClass;
static void loadAPI(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (!dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore", RTLD_LAZY)) return;
        configClass = NSClassFromString(@"MBAssessmentModeConfiguration");
        assertionClass = NSClassFromString(@"MBAssessmentModeAssertion");
    });
}
BOOL MBARHidingAvailable(void) {
    loadAPI();
    return [configClass instancesRespondToSelector:NSSelectorFromString(@"initWithAllowedSystemItems:allowedBundleIdentifiers:")]
        && [assertionClass instancesRespondToSelector:NSSelectorFromString(@"activateWithConfiguration:completionHandler:")]
        && [assertionClass instancesRespondToSelector:NSSelectorFromString(@"invalidate")];
}
id MBARCreateAssertion(NSArray<NSString *> *allowedBundles, void (^completion)(NSError *)) {
    if (!MBARHidingAvailable()) return nil;
    @try {
        NSArray *systemItems = @[@0, @1, @2, @3, @4, @5, @6, @7, @8];
        id (*make)(id, SEL, id, id) = (void *)objc_msgSend;
        id config = make([configClass alloc], NSSelectorFromString(@"initWithAllowedSystemItems:allowedBundleIdentifiers:"), systemItems, allowedBundles);
        if (!config) return nil;
        id handle = [[assertionClass alloc] init];
        if (!handle) return nil;
        void (*activate)(id, SEL, id, id) = (void *)objc_msgSend;
        activate(handle, NSSelectorFromString(@"activateWithConfiguration:completionHandler:"), config, completion);
        return handle;
    } @catch (NSException *exception) {
        completion([NSError errorWithDomain:@"MBAR" code:1 userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"菜单栏接口调用失败"}]);
        return nil;
    }
}
void MBARReleaseAssertion(id assertion) {
    if (!assertion) return;
    @try {
        SEL selector = NSSelectorFromString(@"invalidate");
        if ([assertion respondsToSelector:selector]) {
            void (*invalidate)(id, SEL) = (void *)objc_msgSend;
            invalidate(assertion, selector);
        }
    } @catch (NSException *exception) { NSLog(@"MBAR: release failed: %@", exception.reason); }
}
