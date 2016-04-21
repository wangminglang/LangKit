//
//  LangMemoryCache.m
//  LangKit
//
//  Created by WangMinglang on 16/4/18.
//  Copyright © 2016年 好价. All rights reserved.
//

#import "LangMemoryCache.h"
#import <libkern/OSAtomic.h>
#import <UIKit/UIKit.h>
#import <pthread.h>
#import <QuartzCore/QuartzCore.h>

static inline dispatch_queue_t LangMemoryCacheGetReleaseQueue() {
    return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
}

@interface _LangLinkedMapNode : NSObject
{
    @package
    __unsafe_unretained _LangLinkedMapNode *_prev;
    __unsafe_unretained _LangLinkedMapNode *_next;
    
    id _key;
    id _value;
    NSUInteger _cost;
    NSTimeInterval _time;
}
@end

@implementation _LangLinkedMapNode

@end

@interface _LangLinkedMap : NSObject
{
    @package
    CFMutableDictionaryRef _dic;
    NSUInteger _totalCost;
    NSUInteger _totalCount;
    _LangLinkedMapNode *_head;
    _LangLinkedMapNode *_tail;
    BOOL _releaseOnMainThread;
    BOOL _releaseAsynchronously;
}

- (void)insertNodeAtHead:(_LangLinkedMapNode *)node;

- (void)bringNodeToHead:(_LangLinkedMapNode *)node;

- (void)removeNode:(_LangLinkedMapNode *)node;

- (_LangLinkedMapNode *)removeTailNode;

- (void)removeAll;

@end

@implementation _LangLinkedMap

- (instancetype)init {
    self = [super init];
    _dic = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    _releaseOnMainThread = NO;
    _releaseAsynchronously = YES;
    return self;
}

- (void)dealloc {
    CFRelease(_dic);
}

- (void)insertNodeAtHead:(_LangLinkedMapNode *)node {
    CFDictionarySetValue(_dic, (__bridge const void *)(node->_key), (__bridge const void *)(node));
    _totalCost += node->_cost;
    _totalCount ++;
    if (_head) {
        node->_next = _head;
        _head->_prev = node;
        _head = node;
    }else {
        _head = _tail = node;
    }
}

- (void)bringNodeToHead:(_LangLinkedMapNode *)node {
    if (_head == node) {
        return;
    }
    
    if (_tail == node) {
        _tail = node->_prev;
        _tail->_next = nil;
    }else {
        node->_prev->_next = node->_next;
        node->_next->_prev = node->_prev;
    }
    
    node->_next = _head;
    node->_prev = nil;
    _head->_prev = node;
    _head = node;
}

- (void)removeNode:(_LangLinkedMapNode *)node {
    CFDictionaryRemoveValue(_dic, (__bridge const void *)(node->_key));
    _totalCost -= node->_cost;
    _totalCount--;
    if (node->_next) {
        node->_next->_prev = node->_prev;
    }
    if (node->_prev) {
        node->_prev->_next = node->_next;
    }
    if (_head == node) {
        _head = node->_next;
    }
    if (_tail == node) {
        _tail = node->_prev;
    }
}

- (_LangLinkedMapNode *)removeTailNode {
    if (!_tail) {
        return nil;
    }
    
    _LangLinkedMapNode *tail = _tail;
    CFDictionaryRemoveValue(_dic, (__bridge const void *)(_tail->_key));
    _totalCost -= _tail->_cost;
    _totalCount--;
    if (_head == _tail) {
        _head = _tail = nil;
    }else {
        _tail = _tail->_prev;
        _tail->_next = nil;
    }
    return tail;
}

- (void)removeAll {
    _totalCost = 0;
    _totalCount = 0;
    _head = nil;
    _tail = nil;
    if (CFDictionaryGetCount(_dic) > 0) {
        CFMutableDictionaryRef holder = _dic;
        _dic = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        if (_releaseAsynchronously) {
            dispatch_queue_t queue = _releaseOnMainThread ? dispatch_get_main_queue() : LangMemoryCacheGetReleaseQueue();
            dispatch_async(queue, ^{
                CFRelease(holder);
            });
        }else if (_releaseOnMainThread && !pthread_main_np()) {
            dispatch_async(dispatch_get_main_queue(), ^{
                CFRelease(holder);
            });
        }else {
            CFRelease(holder);
        }
    }
}

@end


@implementation LangMemoryCache
{
    OSSpinLock _lock;
    _LangLinkedMap *_lru;
    dispatch_queue_t _queue;
}

- (instancetype)init {
    self = super.init;
    _lock = OS_SPINLOCK_INIT;
    _lru = [_LangLinkedMap new];
    _queue = dispatch_queue_create("come.lang.cache.memory", DISPATCH_QUEUE_SERIAL);
    
    _countLimit = NSUIntegerMax;
    _costLimit = NSUIntegerMax;
    _ageLimit = DBL_MAX;
    _autoTrimInterval = 5.0;
    _shouldRemoveAllObjectsOnMemoryWarning = YES;
    _shouldRemoveAllObjectsWhenEnteringBackground = YES;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_appDidReceiveMemoryWarningNotification) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_appDidEnterBackgroundNotification) name:UIApplicationDidEnterBackgroundNotification object:nil];
    
    [self _trimRecursively];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
    [_lru removeAll];
}

- (void)_trimRecursively {
    __weak typeof(self) _self = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_autoTrimInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(_self) self = _self;
        if (!self) {
            return ;
        }
        [self _trimInBackground];
        [self _trimRecursively];
    });
}

- (void)_trimInBackground {
    dispatch_async(_queue, ^{
        [self _trimToCost:self->_costLimit];
        [self _trimToCount:self->_countLimit];
        [self _trimToAge:self->_ageLimit];
    });
}

- (void)_appDidReceiveMemoryWarningNotification {
    if (self.didReceiveMemoryWarningBlock) {
        self.didReceiveMemoryWarningBlock(self);
    }
    if (self.shouldRemoveAllObjectsOnMemoryWarning) {
        [self removeAllObjects];
    }
}

- (void)_appDidEnterBackgroundNotification {
    if (self.didEnterBackgroundBlock) {
        self.didEnterBackgroundBlock(self);
    }
    if (self.shouldRemoveAllObjectsWhenEnteringBackground) {
        [self removeAllObjects];
    }
}

- (NSUInteger)totalCount {
    OSSpinLockLock(&_lock);
    NSUInteger count = _lru->_totalCount;
    OSSpinLockUnlock(&_lock);
    return count;
}

- (NSUInteger)totalCost {
    OSSpinLockLock(&_lock);
    NSUInteger totalCost = _lru->_totalCost;
    OSSpinLockUnlock(&_lock);
    return totalCost;
}

- (BOOL)releaseOnMainThread {
    OSSpinLockLock(&_lock);
    BOOL releaseOnMainThread = _lru->_releaseOnMainThread;
    OSSpinLockUnlock(&_lock);
    return releaseOnMainThread;
}

- (void)setReleaseOnMainThread:(BOOL)releaseOnMainThread {
    OSSpinLockLock(&_lock);
    _lru->_releaseOnMainThread = releaseOnMainThread;
    OSSpinLockUnlock(&_lock);
}

- (BOOL)releaseAsynchronously {
    OSSpinLockLock(&_lock);
    BOOL releaseAsynchronously = _lru->_releaseAsynchronously;
    OSSpinLockUnlock(&_lock);
    return releaseAsynchronously;
}

- (void)setReleaseAsynchronously:(BOOL)releaseAsynchronously {
    OSSpinLockLock(&_lock);
    _lru->_releaseAsynchronously = releaseAsynchronously;
    OSSpinLockUnlock(&_lock);
}

#pragma mark - Access Methods
- (BOOL)containsObjectForKey:(id)key {
    if (!key) {
        return NO;
    }
    OSSpinLockLock(&_lock);
    BOOL contains = CFDictionaryContainsKey(_lru->_dic, (__bridge const void *)(key));
    OSSpinLockUnlock(&_lock);
    return contains;
}

- (id)objectForKey:(id)key {
    if (!key) {
        return nil;
    }
    OSSpinLockLock(&_lock);
    _LangLinkedMapNode *node = CFDictionaryGetValue(_lru->_dic, (__bridge const void *)(key));
    if (node) {
        node->_time = CACurrentMediaTime();
        [_lru bringNodeToHead:node];
    }
    OSSpinLockUnlock(&_lock);
    return node ? node->_value : nil;
}

- (void)setObject:(id)object forKey:(id)key {
    [self setObject:object forKey:key withCost:0];
}

- (void)setObject:(id)object forKey:(id)key withCost:(NSUInteger)cost {
    if (!key) {
        return;
    }
    if (!object) {
        [self removeObjectForKey:key];
        return;
    }
    OSSpinLockLock(&_lock);
    _LangLinkedMapNode *node = CFDictionaryGetValue(_lru->_dic, (__bridge const void *)(key));
    NSTimeInterval now = CACurrentMediaTime();
    if (node) {
        _lru->_totalCost -= node->_cost;
        _lru->_totalCost += cost;
        node->_cost = cost;
        node->_time = now;
        node->_value = object;
        [_lru bringNodeToHead:node];
    }else {
        node = [_LangLinkedMapNode new];
        node->_cost = cost;
        node->_time = now;
        node->_key = key;
        node->_value = object;
        [_lru insertNodeAtHead:node];
    }
    
    if (_lru->_totalCost > _costLimit) {
        dispatch_async(_queue, ^{
            [self trimToCost:_costLimit];
        });
    }
    
    if (_lru->_totalCount > _countLimit) {
        _LangLinkedMapNode *node = [_lru removeTailNode];
        if (_lru->_releaseAsynchronously) {
            dispatch_queue_t queue = _lru->_releaseOnMainThread ? dispatch_get_main_queue() : LangMemoryCacheGetReleaseQueue();
            dispatch_async(queue, ^{
                [node class];
            });
        }else if (_lru->_releaseOnMainThread && !pthread_main_np()) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [node class];
            });
        }
    }
    OSSpinLockUnlock(&_lock);
}

- (void)removeObjectForKey:(id)key {
    if (!key) {
        return;
    }
    OSSpinLockLock(&_lock);
    _LangLinkedMapNode *node = CFDictionaryGetValue(_lru->_dic, (__bridge const void *)(key));
    if (node) {
        [_lru removeNode:node];
        _LangLinkedMapNode *node = [_lru removeTailNode];
        if (_lru->_releaseAsynchronously) {
            dispatch_queue_t queue = _lru->_releaseOnMainThread ? dispatch_get_main_queue() : LangMemoryCacheGetReleaseQueue();
            dispatch_async(queue, ^{
                [node class];
            });
        }else if (_lru->_releaseOnMainThread && !pthread_main_np()) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [node class];
            });
        }
    }
    OSSpinLockUnlock(&_lock);
}

- (void)removeAllObjects {
    OSSpinLockLock(&_lock);
    [_lru removeAll];
    OSSpinLockUnlock(&_lock);
}

#pragma mark - Trim
- (void)trimToCount:(NSUInteger)count {
    if (count == 0) {
        [self removeAllObjects];
        return;
    }
    [self _trimToCount:count];
}

- (void)trimToCost:(NSUInteger)cost {
    [self _trimToCost:cost];
}

- (void)trimToAge:(NSTimeInterval)age {
    [self _trimToAge:age];
}

- (void)_trimToCount:(NSUInteger)countLimit {
    BOOL finish = NO;
    OSSpinLockLock(&_lock);
    if (countLimit == 0) {
        [_lru removeAll];
        finish = YES;
    }else if (_lru->_totalCount <= countLimit) {
        finish = YES;
    }
    OSSpinLockUnlock(&_lock);
    if (finish) {
        return;
    }
    
    NSMutableArray *holder = [NSMutableArray new];
    while (!finish) {
        if (OSSpinLockTry(&_lock)) {
            if (_lru->_totalCount > countLimit) {
                _LangLinkedMapNode *node = [_lru removeTailNode];
                if (node) {
                    [holder addObject:node];
                }
            }else {
                finish = YES;
            }
            OSSpinLockUnlock(&_lock);
        }else {
            usleep(10 * 1000); //10ms
        }
    }
    
    if (holder.count) {
        dispatch_queue_t queue = _lru->_releaseOnMainThread ? dispatch_get_main_queue() : LangMemoryCacheGetReleaseQueue();
        dispatch_async(queue, ^{
            [holder count];
        });
    }
}

- (void)_trimToCost:(NSUInteger)costLimit {
    BOOL finish = NO;
    OSSpinLockLock(&_lock);
    if (costLimit == 0) {
        [_lru removeAll];
        finish = YES;
    }else if (_lru->_totalCost <= costLimit) {
        finish = YES;
    }
    OSSpinLockUnlock(&_lock);
    if (finish) {
        return;
    }
    
    NSMutableArray *holder = [NSMutableArray new];
    while (!finish) {
        if (OSSpinLockTry(&_lock)) {
            if (_lru->_totalCost > costLimit) {
                _LangLinkedMapNode *node = [_lru removeTailNode];
                if (node) {
                    [holder addObject:node];
                }else {
                    finish = YES;
                }
                OSSpinLockUnlock(&_lock);
            }
        }else {
            usleep(10 * 1000); //10ms
        }
    }
    
    if (holder.count) {
        dispatch_queue_t queue = _lru->_releaseOnMainThread ? dispatch_get_main_queue() : LangMemoryCacheGetReleaseQueue();
        dispatch_async(queue, ^{
            [holder count];
        });
    }
}

- (void)_trimToAge:(NSUInteger)ageLimit {
    BOOL finish = NO;
    NSTimeInterval now = CACurrentMediaTime();
    OSSpinLockLock(&_lock);
    if (ageLimit <= 0) {
        [_lru removeAll];
        finish = YES;
    }else if (!_lru->_tail || now - _lru->_tail->_time <= ageLimit) {
        finish = YES;
    }
    OSSpinLockUnlock(&_lock);
    if (finish) {
        return;
    }
    
    NSMutableArray *holder = [NSMutableArray new];
    while (!finish) {
        if (OSSpinLockTry(&_lock)) {
            if (_lru->_tail && now - _lru->_tail->_time > ageLimit) {
                _LangLinkedMapNode *node = [_lru removeTailNode];
                if (node) {
                    [holder addObject:node];
                }
            }else {
                finish = YES;
            }
            OSSpinLockUnlock(&_lock);
        }else {
            usleep(10 * 1000);//10ms
        }
    }
    
    if (holder.count) {
        dispatch_queue_t queue = _lru->_releaseOnMainThread ? dispatch_get_main_queue() : LangMemoryCacheGetReleaseQueue();
        dispatch_async(queue, ^{
            [holder count];
        });
    }
}


@end
