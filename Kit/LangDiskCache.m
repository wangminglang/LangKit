//
//  LangDiskCache.m
//  LangKit
//
//  Created by WangMinglang on 16/4/18.
//  Copyright © 2016年 好价. All rights reserved.
//

#import "LangDiskCache.h"
#import "LangKVStorage.h"
#import "NSString+YYAdd.h"
#import <objc/runtime.h>

#define Lock() dispatch_semaphore_wait(_lock, DISPATCH_TIME_FOREVER)
#define Unlock() dispatch_semaphore_signal(_lock)

static const int extended_data_key;

static int64_t _LangDiskSpaceFree() {
    NSError *error = nil;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:&error];
    if (error) {
        return -1;
    }
    int64_t space = [[attrs objectForKey:NSFileSystemFreeSize] longLongValue];
    if (space < 0) {
        return -1;
    }
    return space;
}

@implementation LangDiskCache
{
    LangKVStorage *_kv;
    dispatch_semaphore_t _lock;
    dispatch_queue_t _queue;
}

- (void)_trimRecursively {
    __weak typeof(self) _self = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_autoTimeInterval * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        __strong typeof(_self) self = _self;
        if (!self) {
            return ;
        }
        [self _trimInBackground];
        [self _trimRecursively];
    });
}

- (void)_trimInBackground {
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        if (!self) {
            return ;
        }
        dispatch_semaphore_wait(self->_lock, DISPATCH_TIME_FOREVER);
        [self _trimToCost:self.costLimit];
        [self _trimToCount:self.countLimit];
        [self _trimToAge:self.ageLimit];
        [self _trimToFreeDiskSpace:self.freeDiskSpaceLimit];
        dispatch_semaphore_signal(self->_lock);
    });
}

- (void)_trimToCost:(NSUInteger)costLimit {
    if (costLimit >= INT_MAX) {
        return;
    }
    [_kv removeItemsToFitSize:(int)costLimit];
}

- (void)_trimToCount:(NSUInteger)countLimit {
    if (countLimit >= INT_MAX) {
        return;
    }
    [_kv removeItemsToFitCount:(int)countLimit];
}

- (void)_trimToAge:(NSTimeInterval)ageLimit {
    if (ageLimit <= 0) {
        [_kv removeAllItems];
        return;
    }
    long timestap = time(NULL);
    if (timestap <= ageLimit) {
        return;
    }
    long age = timestap - ageLimit;
    if (age >= INT_MAX) {
        return;
    }
    [_kv removeItemsEarlierThanTime:(int)age];
}

- (void)_trimToFreeDiskSpace:(NSUInteger)targetFreeDiskSpace {
    if (targetFreeDiskSpace == 0) {
        return;
    }
    int64_t totalBytes = [_kv getItemsSize];
    if (totalBytes <= 0) {
        return;
    }
    int64_t diskFreeBytes = _LangDiskSpaceFree();
    if (diskFreeBytes < 0) {
        return;
    }
    int64_t needTrimBytes = targetFreeDiskSpace - diskFreeBytes;
    if (needTrimBytes <= 0) {
        return;
    }
    int64_t costLimit = totalBytes - needTrimBytes;
    if (costLimit < 0) {
        costLimit = 0;
    }
    [self _trimToCost:(int)costLimit];
}

- (NSString *)_filenameForKey:(NSString *)key {
    NSString *filename = nil;
    if (_customFilenameBlock) {
        filename = _customFilenameBlock(key);
    }
    if (!filename) {
        filename = key.md5String;
    }
    return filename;
}

#pragma mark - public
- (instancetype)init {
    @throw [NSException exceptionWithName:@"LangDiskCache init error" reason:@"LangDiskCache must be initialized with a path. Use 'initWithPath:' or 'initWithPath:inlineThreshold:' instead." userInfo:nil];
    return [self initWithPath:nil inlineThreshold:0];
}

- (instancetype)initWithPath:(NSString *)path {
    return [self initWithPath:path inlineThreshold:1024 * 20];//20k
}

- (instancetype)initWithPath:(NSString *)path inlineThreshold:(NSUInteger)threshold {
    self = [super init];
    if (!self) {
        return nil;
    }
    
    LangKVStorageType type;
    if (threshold == 0) {
        type = LangKVStorageTypeFile;
    }else if (threshold == NSUIntegerMax) {
        type = LangKVStorageTypeSQLite;
    }else {
        type = LangKVStorageTypeMixed;
    }
    
    LangKVStorage *kv = [[LangKVStorage alloc] initWithPath:path type:type];
    if (!kv) {
        return nil;
    }
    
    _kv = kv;
    _path = path;
    _lock = dispatch_semaphore_create(1);
    _queue = dispatch_queue_create("com.lang.cache.disk", DISPATCH_QUEUE_CONCURRENT);
    _inlineThreshold = threshold;
    _countLimit = NSUIntegerMax;
    _costLimit = NSUIntegerMax;
    _ageLimit = DBL_MAX;
    _freeDiskSpaceLimit = 0;
    _autoTimeInterval = 60;
    
    [self _trimRecursively];
    return self;
}

- (BOOL)containsObjectForKey:(NSString *)key {
    if (!key) {
        return NO;
    }
    Lock();
    BOOL contains = [_kv itemExistsForKey:key];
    Unlock();
    return contains;
}

- (void)containsObjectForKey:(NSString *)key withBlock:(void (^)(NSString *key, BOOL contains))block {
    if (!block) {
        return;
    }
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        BOOL contains = [self containsObjectForKey:key];
        block(key, contains);
    });
    
}

- (id<NSCoding>)objectForKey:(NSString *)key {
    if (!key) {
        return nil;
    }
    Lock();
    LangKVStorageItem *item = [_kv getItemForKey:key];
    Unlock();
    if (!item.value) {
        return nil;
    }
    id object = nil;
    if (_customUnarchiveBlock) {
        object = _customUnarchiveBlock(item.value);
    }else {
        @try {
            object = [NSKeyedUnarchiver unarchiveObjectWithData:item.value];
        }
        @catch (NSException *exception) {
            
        }
    }
    if (object && item.extendedData) {
        [LangDiskCache setExtendedData:item.extendedData toObject:object];
    }
    return object;
}

- (void)objectForKey:(NSString *)key withBlock:(void (^)(NSString *key, id<NSCoding> object))block {
    if (!block) {
        return;
    }
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        id<NSCoding> object = [self objectForKey:key];
        block(key, object);
    });
}

- (void)setObject:(id<NSCoding>)object forKey:(NSString *)key {
    if (!key) {
        return;
    }
    if (!object) {
        [self removeObjectForKey:key];
        return;
    }
    
    NSData *extendedData = [LangDiskCache getExtendedDataFromObject:object];
    NSData *value = nil;
    if (_customArchiveBlock) {
        value = _customArchiveBlock(object);
    }else {
        @try {
            value = [NSKeyedArchiver archivedDataWithRootObject:object];
        }
        @catch (NSException *exception) {
            //nothing to do
        }
    }
    if (!value) {
        return;
    }
    NSString *filename = nil;
    if (_kv.type != LangKVStorageTypeSQLite) {
        if (value.length > _inlineThreshold) {
            filename = [self _filenameForKey:key];
        }
    }
    Lock();
    [_kv saveItemWithKey:key value:value filename:filename extendedData:extendedData];
    Unlock();
}

- (void)setObject:(id<NSCoding>)object forKey:(NSString *)key withBlock:(void (^)(void))block {
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        [self setObject:object forKey:key];
        if (block) {
            block();
        }
    });
}

- (void)removeObjectForKey:(NSString *)key {
    if (!key) {
        return;
    }
    Lock();
    [_kv removeItemForKey:key];
    Unlock();
}

- (void)removeObjectForKey:(NSString *)key withBlock:(void (^)(NSString *key))block {
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        [self removeObjectForKey:key];
        if (block) {
            block(key);
        }
    });
}

- (void)removeAllObjects {
    Lock();
    [_kv removeAllItems];
    Unlock();
}

- (void)removeAllObjectsWithBlock:(void (^)(void))block {
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        [self removeAllObjects];
        if (block) {
            block();
        }
    });
}

- (void)removeAllObjectsWithProgressBlock:(void (^)(int removedCount, int totalCount))progerss endBlock:(void (^)(BOOL error))end {
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        if (!self) {
            if (end) {
                end(YES);
            }
            return ;
        }
        Lock();
        [_kv removeAllItemsWithProgressBlock:progerss endBlock:end];
        Unlock();
    });
}

- (NSInteger)totalCount {
    Lock();
    int count = [_kv getItemsCount];
    Unlock();
    return count;
}

- (void)totalCountWithBlock:(void (^)(NSInteger))block {
    if (!block) {
        return;
    }
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        NSInteger totalCount = [self totalCount];
        block(totalCount);
    });
}

- (NSInteger)totalCost {
    Lock();
    int count = [_kv getItemsSize];
    Unlock();
    return count;
}

- (void)totalCostWithBlock:(void (^)(NSInteger))block {
    if (!block) {
        return;
    }
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        NSInteger totalCost = [self totalCost];
        block(totalCost);
    });
}

- (void)trimToCount:(NSUInteger)count {
    Lock();
    [self _trimToCount:count];
    Unlock();
}

- (void)trimToCount:(NSUInteger)count withBlock:(void (^)(void))block {
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        [self trimToCount:count];
        if (block) {
            block();
        }
    });
}

- (void)trimToCost:(NSUInteger)cost {
    Lock();
    [self _trimToCost:cost];
    Unlock();
}

- (void)trimToCost:(NSUInteger)cost withBlock:(void (^)(void))block {
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        [self trimToCost:cost];
        if (block) {
            block();
        }
    });
}

- (void)trimToAge:(NSTimeInterval)age {
    Lock();
    [self _trimToAge:age];
    Unlock();
}

- (void)trimToAge:(NSTimeInterval)age withBlock:(void (^)(void))block {
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        [self trimToAge:age];
        if (block) {
            block();
        }
    });
}

+ (void)setExtendedData:(NSData *)extendedData toObject:(id)object {
    if (!object) {
        return;
    }
    objc_setAssociatedObject(object, &extended_data_key, extendedData, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (NSData *)getExtendedDataFromObject:(id)object {
    if (!object) {
        return nil;
    }
    return (NSData *)objc_getAssociatedObject(object, &extended_data_key);
}


@end
