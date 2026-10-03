/* IOKitLib.h — tvOS shim.
 *
 * Apple TV SDK has no IOKit.framework, but wine/system.c (SMBIOS + platform
 * info) and win32u sysparams include it unconditionally under __APPLE__.
 * These declarations only need to COMPILE enough for Wine; at runtime the
 * calls return a null/empty result, which Wine already handles ("can't find
 * service" path). Battery/SMBIOS info is cosmetic on tvOS.
 */
#ifndef __IOKIT_IOKITLIB_H
#define __IOKIT_IOKITLIB_H

#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>

typedef uint32_t io_object_t;
typedef io_object_t io_service_t;
typedef io_object_t io_connect_t;
typedef io_object_t io_registry_entry_t;
typedef io_object_t io_iterator_t;
typedef uint32_t mach_port_t;
typedef char io_name_t[128];
typedef char io_string_t[512];

#define IO_OBJECT_NULL ((io_object_t)0)
#define kIOMasterPortDefault ((mach_port_t)0)
#define kIORegistryIterateRecursively 0x00000001UL

#define kIOPlatformSerialNumberKey CFSTR("IOPlatformSerialNumber")
#define kIOPlatformUUIDKey CFSTR("IOPlatformUUID")
#define kIOPlatformExpertDeviceNameKey CFSTR("IOPlatformExpertDevice")
#define kIOBundleIdentifierKey CFSTR("CFBundleIdentifier")
#define kIOPropertyMatchKey CFSTR("IOPropertyMatch")

static inline io_service_t IOServiceGetMatchingService(mach_port_t master, CFDictionaryRef matching)
{
    (void)master;
    if (matching) CFRelease(matching);
    return IO_OBJECT_NULL;
}

static inline CFMutableDictionaryRef IOServiceMatching(const char *name)
{
    (void)name;
    return CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                     &kCFTypeDictionaryKeyCallBacks,
                                     &kCFTypeDictionaryValueCallBacks);
}

static inline CFMutableDictionaryRef IOServiceNameMatching(const char *name)
{
    return IOServiceMatching(name);
}

static inline CFTypeRef IORegistryEntryCreateCFProperty(io_registry_entry_t entry,
                                                        CFStringRef key,
                                                        CFAllocatorRef allocator,
                                                        uint32_t options)
{
    (void)entry; (void)key; (void)allocator; (void)options;
    return NULL;
}

static inline kern_return_t IOObjectRelease(io_object_t object)
{
    (void)object;
    return 0;
}

static inline io_service_t IOIteratorNext(io_iterator_t iter)
{
    (void)iter;
    return IO_OBJECT_NULL;
}

#endif /* __IOKIT_IOKITLIB_H */