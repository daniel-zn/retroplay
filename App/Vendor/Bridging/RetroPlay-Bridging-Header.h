// App-target bridging header. Defines must appear before mgba headers so
// mCoreFind / mCoreLoadFile / save helpers (gated on ENABLE_VFS) are visible.
#ifndef ENABLE_VFS
#define ENABLE_VFS 1
#endif
#ifndef ENABLE_DIRECTORIES
#define ENABLE_DIRECTORIES 1
#endif

#import <mgba/core/core.h>
#import <mgba/core/interface.h>
#import <mgba/core/config.h>
#import <mgba-util/common.h>
#import <mgba-util/image.h>
