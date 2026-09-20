#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
BOOL MBARHidingAvailable(void);
id _Nullable MBARCreateAssertion(NSArray<NSString *> *allowedBundles, void (^completion)(NSError * _Nullable));
void MBARReleaseAssertion(id _Nullable assertion);
NS_ASSUME_NONNULL_END
