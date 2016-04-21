//
//  LangMemoryCache.h
//  LangKit
//
//  Created by WangMinglang on 16/4/18.
//  Copyright © 2016年 好价. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LangMemoryCache : NSObject

#pragma mark - Attribute
@property (nonatomic, copy) NSString *name;

@property (nonatomic, readonly) NSUInteger totalCount;

@property (nonatomic, readonly) NSUInteger totalCost;

#pragma mark - Limit
@property (nonatomic, assign) NSUInteger countLimit;

@property (nonatomic, assign) NSUInteger costLimit;

@property (nonatomic, assign) NSTimeInterval ageLimit;

@property (nonatomic, assign) NSTimeInterval autoTrimInterval;

@property (nonatomic, assign) BOOL shouldRemoveAllObjectsOnMemoryWarning;

@property (nonatomic, assign) BOOL shouldRemoveAllObjectsWhenEnteringBackground;

@property (nonatomic, copy) void (^didReceiveMemoryWarningBlock)(LangMemoryCache *cache);

@property (nonatomic, copy) void (^didEnterBackgroundBlock)(LangMemoryCache *cache);

@property (nonatomic, assign) BOOL releaseOnMainThread;

@property (nonatomic, assign) BOOL releaseAsynchronously;

#pragma mark - Access Methods
- (BOOL)containsObjectForKey:(id)key;

- (id)objectForKey:(id)key;

- (void)setObject:(id)object forKey:(id)key;

- (void)setObject:(id)object forKey:(id)key withCost:(NSUInteger)cost;

- (void)removeObjectForKey:(id)key;

- (void)removeAllObjects;

#pragma mark - Trim
- (void)trimToCount:(NSUInteger)count;

- (void)trimToCost:(NSUInteger)cost;

- (void)trimToAge:(NSTimeInterval)age;

@end
