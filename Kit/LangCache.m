//
//  LangCache.m
//  LangKit
//
//  Created by WangMinglang on 16/4/18.
//  Copyright © 2016年 好价. All rights reserved.
//

#import "LangCache.h"
#import "LangMemoryCache.h"
#import "LangDiskCache.h"

@implementation LangCache

- (instancetype)init {
    self = [super init];
    NSLog(@"Use \"initWithName\" or \"initWithPath\" to create LangCache instance.");
    return self;
}

- (instancetype)initWithName:(NSString *)name {
    if (name.length == 0) {
        return nil;
    }
    self = [super init];
    NSString *cacheFolder = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    NSString *path = [cacheFolder stringByAppendingPathComponent:name];
    return [self initWithPath:path];
}

- (instancetype)initWithPath:(NSString *)path {
    if (path.length == 0) {
        return nil;
    }
    LangDiskCache *diskCache = [[LangDiskCache alloc] initWithPath:path];
    if (!diskCache) {
        return nil;
    }
    NSString *name = [path lastPathComponent];
    LangMemoryCache *memoryCache = [LangMemoryCache new];
    memoryCache.name = name;
    
    self = [super init];
    _name = name;
    _memoryCache = memoryCache;
    _diskCache = diskCache;
    return self;
}

#pragma mark - access Methods
- (BOOL)containsObjectForKey:(NSString *)key {
    return [_memoryCache containsObjectForKey:key] || [_diskCache containsObjectForKey:key];
}

- (void)containsObjectForKey:(NSString *)key withBlock:(void (^)(NSString *key, BOOL contains))block {
    if (!block) {
        return;
    }
    if ([_memoryCache containsObjectForKey:key]) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            block(key, YES);
        });
    }else {
        [_diskCache containsObjectForKey:key withBlock:block];
    }
}

- (id<NSCoding>)objectForKey:(NSString *)key {
    id<NSCoding> object = [_memoryCache objectForKey:key];
    if (!object) {
        object = [_diskCache objectForKey:key];
        if (object) {
            [_memoryCache setObject:object forKey:key];
        }
    }
    return object;
}

- (void)objectForKey:(NSString *)key withBlock:(void (^)(NSString *key, id<NSCoding> object))block {
    if (block) {
        return;
    }
    id<NSCoding> object = [_memoryCache objectForKey:key];
    if (object) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            block(key, object);
        });
    }else {
        [_diskCache objectForKey:key withBlock:block];
    }
}

- (void)setObject:(id<NSCoding>)object forKey:(NSString *)key {
    [_memoryCache setObject:object forKey:key];
    [_diskCache setObject:object forKey:key];
}

- (void)setObject:(id<NSCoding>)object forKey:(NSString *)key withBlock:(void (^)(void))block {
    [_memoryCache setObject:object forKey:key];
    [_diskCache setObject:object forKey:key withBlock:block];
}

- (void)removeObjectForKey:(NSString *)key {
    [_memoryCache removeObjectForKey:key];
    [_diskCache removeObjectForKey:key];
}

- (void)removeObjectForKey:(NSString *)key withBlock:(void (^)(NSString *))block {
    [_memoryCache removeObjectForKey:key];
    [_diskCache removeObjectForKey:key withBlock:block];
}

- (void)removeAllObjects {
    [_memoryCache removeAllObjects];
    [_diskCache removeAllObjects];
}

- (void)removeAllObjectsWithBlock:(void (^)(void))block {
    [_memoryCache removeAllObjects];
    [_diskCache removeAllObjectsWithBlock:block];
}

- (void)removeAllObjectsWithProgerssBlock:(void (^)(int removeCount, int totalCount))progerss endBlock:(void (^)(BOOL error))end {
    [_memoryCache removeAllObjects];
    [_diskCache removeAllObjectsWithProgressBlock:progerss endBlock:end];
}

@end
