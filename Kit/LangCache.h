//
//  LangCache.h
//  LangKit
//
//  Created by WangMinglang on 16/4/18.
//  Copyright © 2016年 好价. All rights reserved.
//

#import <Foundation/Foundation.h>

@class LangMemoryCache, LangDiskCache;

@interface LangCache : NSObject

@property (nonatomic, readonly, copy) NSString *name;

@property (nonatomic, readonly, strong) LangMemoryCache *memoryCache;

@property (nonatomic, readonly, strong) LangDiskCache *diskCache;

- (instancetype)initWithName:(NSString *)name;
- (instancetype)initWithPath:(NSString *)path;

- (instancetype)init UNAVAILABLE_ATTRIBUTE;
- (instancetype)new UNAVAILABLE_ATTRIBUTE;

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

- (void)removeAllObjectsWithProgerssBlock:(void (^)(int removeCount, int totalCount))progerss endBlock:(void (^)(BOOL error))end;

@end
