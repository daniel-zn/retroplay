// Add this as the Objective-C Bridging Header on the iOS app target after linking mGBA.xcframework.
// Do not invent that the framework is present in git.
#import <mgba/core/core.h>
#import <mgba/core/interface.h>
#import <mgba/core/config.h>
#import <mgba-util/vfs.h>
