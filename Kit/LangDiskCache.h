//
//  LangDiskCache.h
//  LangKit
//
//  Created by WangMinglang on 16/4/18.
//  Copyright © 2016年 好价. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LangDiskCache : NSObject

#pragma mark - attribute
@property (nonatomic, copy) NSString *name;

@property (nonatomic, readonly) NSString *path;

@property (nonatomic, readonly) NSUInteger inlineThreshold;

@property (nonatomic, copy) NSData *(^customArchiveBlock)(id object);

@property (nonatomic, copy) id (^customUnarchiveBlock)(NSData *data);

@property (nonatomic, copy) NSString *(^customFilenameBlock)(NSString *key);

#pragma mark - Limit
@property (nonatomic, assign) NSUInteger countLimit;

@property (nonatomic, assign) NSUInteger costLimit;

@property (nonatomic, assign) NSTimeInterval ageLimit;

@property (nonatomic, assign) NSUInteger freeDiskSpaceLimit;

@property (nonatomic, assign) NSTimeInterval autoTimeInterval;

#pragma mark - initializer
- (instancetype)init UNAVAILABLE_ATTRIBUTE;
- (instancetype)new UNAVAILABLE_ATTRIBUTE;

- (instancetype)initWithPath:(NSString *)path;
- (instancetype)initWithPath:(NSString *)path inlineThreshold:(NSUInteger)threshold NS_DESIGNATED_INITIALIZER;

#pragma mark - Access Methods
- (BOOL)containsObjectForKey:(NSString *)key;

- (void)containsObjectForKey:(NSString *)key withBlock:(void (^)(NSString *key, BOOL contains))block;

- (id<NSCoding>)objectForKey:(NSString *)key;

- (void)objectForKey:(NSString *)key withBlock:(void (^)(NSString *key, id<NSCoding> object))block;

- (void)setObject:(id<NSCoding>)object forKey:(NSString *)key;

- (void)setObject:(id<NSCoding>)object forKey:(NSString *)key withBlock:(void (^)(void))block;

- (void)removeObjectForKey:(NSString *)key;

- (void)removeObjectForKey:(NSString *)key withBlock:(void (^)(NSString *key))block;

- (void)removeAllObjects;

- (void)removeAllObjectsWithBlock:(void (^)(void))block;

- (void)removeAllObjectsWithProgressBlock:(void (^)(int removedCount, int totalCount))progerss endBlock:(void (^)(BOOL error))end;

- (NSInteger)totalCount;

- (void)totalCountWithBlock:(void (^)(NSInteger totalCount))block;

- (NSInteger)totalCost;

- (void)totalCostWithBlock:(void (^)(NSInteger totalCost))block;

- (void)trimToCount:(NSUInteger)count;

- (void)trimToCount:(NSUInteger)count withBlock:(void (^)(void))block;

- (void)trimToCost:(NSUInteger)cost;

- (void)trimToCost:(NSUInteger)cost withBlock:(void (^)(void))block;

- (void)trimToAge:(NSTimeInterval)age;

- (void)trimToAge:(NSTimeInterval)age withBlock:(void (^)(void))block;

#pragma <#arguments#>
+ (void)setExtendedData:(NSData *)extendedData toObject:(id)object;

+ (NSData *)getExtendedDataFromObject:(id)object;

@end
