//
//  Helper.h
//  SeparableSSS
//
//  Created by yushroom on 8/19/15.
//  Copyright (c) 2015 yushroom. All rights reserved.
//

#ifndef SeparableSSS_PathHelper_h
#define SeparableSSS_PathHelper_h

#include <string>
#include <CoreFoundation/CoreFoundation.h>

static std::string IOS_bundle_path( CFStringRef subDir, CFStringRef name, CFStringRef ext)
{
    CFURLRef url = CFBundleCopyResourceURL(CFBundleGetMainBundle(), name, ext, subDir);
    UInt8 path[1024];
    CFURLGetFileSystemRepresentation(url, true, path, sizeof(path));
    CFRelease(url);
    return std::string((const char*)path);
}
#define IOS_PATH(subDir, name, ext) IOS_bundle_path(CFSTR(subDir), CFSTR(name), CFSTR(ext))

#endif
