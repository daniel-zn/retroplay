// Requires GCC_PREPROCESSOR_DEFINITIONS ENABLE_VFS=1 ENABLE_DIRECTORIES=1 on the app target
// (set in project.yml) so mCoreFind / mCoreLoadFile are visible.
// App target Objective-C Bridging Header after linking mGBA.xcframework.
#import <mgba/core/core.h>
#import <mgba/core/interface.h>
#import <mgba/core/config.h>
#import <mgba-util/common.h>
#import <mgba-util/image.h>
