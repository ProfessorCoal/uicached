
// Logos by Dustin Howett
// See http://iphonedevwiki.net/index.php/Logos

#import <notify.h>
#import <unistd.h>
#import <sys/stat.h>
#import <sys/types.h>
#import <objc/runtime.h>

@interface NSMutableArray (Cydia)
- (void) addInfoDictionary:(NSDictionary *)info;
@end

@implementation NSMutableArray (Cydia)

- (void) addInfoDictionary:(NSDictionary *)info {
    [self addObject:info];
}

- (NSArray *) allInfoDictionaries {
    return self;
}

@end

@interface NSMutableDictionary (Cydia)
- (void) addInfoDictionary:(NSDictionary *)info;
@end

@implementation NSMutableDictionary (Cydia)

- (void) addInfoDictionary:(NSDictionary *)info {
    NSString *bundle = [info objectForKey:@"CFBundleIdentifier"];
    [self setObject:info forKey:bundle];
}

- (NSArray *) allInfoDictionaries {
    return [self allValues];
}

@end

@interface LSApplicationWorkspace : NSObject
+ (id) defaultWorkspace;
- (BOOL) registerApplication:(id)application;
- (BOOL) unregisterApplication:(id)application;
- (BOOL) invalidateIconCache:(id)bundle;
- (BOOL) registerApplicationDictionary:(id)application;
- (BOOL) installApplication:(id)application withOptions:(id)options;
- (BOOL) _LSPrivateRebuildApplicationDatabasesForSystemApps:(BOOL)system internal:(BOOL)internal user:(BOOL)user;
@end

%hook SpringBoard

-(void)applicationDidFinishLaunching:(id)application {
    %orig;
    Class $LSApplicationWorkspace(objc_getClass("LSApplicationWorkspace"));
    LSApplicationWorkspace *workspace($LSApplicationWorkspace == nil ? nil : [$LSApplicationWorkspace defaultWorkspace]);
    
    if (kCFCoreFoundationVersionNumber > 1000)
        if ([workspace respondsToSelector:@selector(_LSPrivateRebuildApplicationDatabasesForSystemApps:internal:user:)]) {
            if (![workspace _LSPrivateRebuildApplicationDatabasesForSystemApps:YES internal:YES user:NO])
                fprintf(stderr, "failed to rebuild application databases");
            return;
        }
    
    NSString *home(NSHomeDirectory());
    NSString *path([NSString stringWithFormat:@"%@/Library/Caches/com.apple.mobile.installation.plist", home]);
    
    @try {
        system("killall lsd");
        
        if ([workspace respondsToSelector:@selector(invalidateIconCache:)])
            while (![workspace invalidateIconCache:nil])
                sleep(1);
        
        if (NSMutableDictionary *cache = [NSMutableDictionary dictionaryWithContentsOfFile:path]) {
            NSFileManager *manager = [NSFileManager defaultManager];
            NSError *error = nil;
            
            NSMutableDictionary *bundles([NSMutableDictionary dictionaryWithCapacity:16]);
            
            id after = [cache objectForKey:@"System"];
            if (after == nil) { error:
                fprintf(stderr, "%s\n", error == nil ? strerror(errno) : [[error localizedDescription] UTF8String]);
                goto cached;
            }
            
            id before([after copy]);
            [after removeAllObjects];
            
            NSArray *cached([cache objectForKey:@"InfoPlistCachedKeys"]);
            
            NSMutableSet *removed([NSMutableSet set]);
            for (NSDictionary *info in [before allInfoDictionaries])
                if (NSString *path = [info objectForKey:@"Path"])
                    [removed addObject:path];
            
            if (NSArray *apps = [manager contentsOfDirectoryAtPath:@"/Applications" error:&error]) {
                for (NSString *app in apps)
                    if ([app hasSuffix:@".app"]) {
                        NSString *path = [@"/Applications" stringByAppendingPathComponent:app];
                        NSString *plist = [path stringByAppendingPathComponent:@"Info.plist"];
                        
                        if (NSMutableDictionary *info = [NSMutableDictionary dictionaryWithContentsOfFile:plist]) {
                            if (NSString *identifier = [info objectForKey:@"CFBundleIdentifier"]) {
                                [bundles setObject:path forKey:identifier];
                                [removed removeObject:path];
                                
                                if (cached != nil) {
                                    NSMutableDictionary *merged([before objectForKey:identifier]);
                                    if (merged == nil)
                                        merged = [NSMutableDictionary dictionary];
                                    else
                                        merged = [merged mutableCopy];
                                    
                                    for (NSString *key in cached)
                                        if (NSObject *value = [info objectForKey:key])
                                            [merged setObject:value forKey:key];
                                        else
                                            [merged removeObjectForKey:key];
                                    
                                    info = merged;
                                }
                                
                                [info setObject:path forKey:@"Path"];
                                [info setObject:@"System" forKey:@"ApplicationType"];
                                [after addInfoDictionary:info];
                            } else
                                fprintf(stderr, "%s missing CFBundleIdentifier", [app UTF8String]);
                        }
                    }
            } else goto error;
            
            [cache writeToFile:path atomically:YES];
            
            if (workspace != nil) {
                if ([workspace respondsToSelector:@selector(invalidateIconCache:)]) {
                    for (NSString *identifier in bundles)
                        [workspace invalidateIconCache:identifier];
                } else {
                    for (NSString *identifier in bundles) {
                        NSString *path([bundles objectForKey:identifier]);
                        [workspace unregisterApplication:[NSURL fileURLWithPath:path]];
                    }
                }
                
                for (NSString *identifier in bundles) {
                    NSString *path([bundles objectForKey:identifier]);
                    if (kCFCoreFoundationVersionNumber >= 800)
                        [workspace registerApplicationDictionary:[after objectForKey:identifier]];
                    else
                        [workspace registerApplication:[NSURL fileURLWithPath:path]];
                }
                
                for (NSString *path in removed)
                    [workspace unregisterApplication:[NSURL fileURLWithPath:path]];
            }
        } else fprintf(stderr, "cannot open cache file. incorrect user?\n");
    cached:
        
        if (kCFCoreFoundationVersionNumber >= 550.32) {
            unlink([[NSString stringWithFormat:@"%@/Library/Caches/com.apple.springboard-imagecache-icons", home] UTF8String]);
            unlink([[NSString stringWithFormat:@"%@/Library/Caches/com.apple.springboard-imagecache-icons.plist", home] UTF8String]);
            
            unlink([[NSString stringWithFormat:@"%@/Library/Caches/com.apple.springboard-imagecache-smallicons", home] UTF8String]);
            unlink([[NSString stringWithFormat:@"%@/Library/Caches/com.apple.springboard-imagecache-smallicons.plist", home] UTF8String]);
            
            system([[NSString stringWithFormat:@"rm -rf %@/Library/Caches/SpringBoardIconCache", home] UTF8String]);
            system([[NSString stringWithFormat:@"rm -rf %@/Library/Caches/SpringBoardIconCache-small", home] UTF8String]);
            
            system([[NSString stringWithFormat:@"rm -rf %@/Library/Caches/com.apple.IconsCache", home] UTF8String]);
        }
        
        system("killall installd");
        
    } @finally {
        
    }
    
    notify_post("com.apple.mobile.application_installed");
}

%end
