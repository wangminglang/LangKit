//
//  LangKVStorage.h
//  LangKit
//
//  Created by WangMinglang on 16/4/18.
//  Copyright © 2016年 好价. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LangKVStorageItem : NSObject

@property (nonatomic, copy) NSString *key;

@property (nonatomic, copy) NSString *fileName;

@property (nonatomic, assign) int size;

@property (nonatomic, strong) NSData *value;

@property (nonatomic, assign) int modTime;

@property (nonatomic, assign) int accessTime;

@property (nonatomic, strong) NSData *extendedData;

@end

typedef enum : NSUInteger {
    LangKVStorageTypeFile = 0,
    LangKVStorageTypeSQLite = 1,
    LangKVStorageTypeMixed = 2,
} LangKVStorageType;

@interface LangKVStorage : NSObject

#pragma mark - Attribute
@property (nonatomic, readonly) NSString *path;

@property (nonatomic, readonly) LangKVStorageType type;

@property (nonatomic, assign) BOOL errorLogsEnabled;

#pragma mark - Initializer
- (instancetype)init UNAVAILABLE_ATTRIBUTE;

- (instancetype)new UNAVAILABLE_ATTRIBUTE;

- (instancetype)initWithPath:(NSString *)path type:(LangKVStorageType)type NS_DESIGNATED_INITIALIZER;

#pragma mark - SaveItems
- (BOOL)saveItem:(LangKVStorageItem *)item;

- (BOOL)saveItemWithKey:(NSString *)key value:(NSData *)value;

- (BOOL)saveItemWithKey:(NSString *)key
                  value:(NSData *)value
               filename:(NSString *)filename
           extendedData:(NSData *)extendedData;

- (BOOL)removeItemForKey:(NSString *)key;

- (BOOL)removeItemForKeys:(NSArray *)keys;

- (BOOL)removeItemsLargerThanSize:(int)size;

- (BOOL)removeItemsEarlierThanTime:(int)time;

- (BOOL)removeItemsToFitSize:(int)maxSize;

- (BOOL)removeItemsToFitCount:(int)maxCount;

- (BOOL)removeAllItems;

- (void)removeAllItemsWithProgressBlock:(void (^)(int removeCount, int totalCount))progress endBlock:(void (^)(BOOL error))end;

- (LangKVStorageItem *)getItemForKey:(NSString *)key;

- (LangKVStorageItem *)getItemInfoForKey:(NSString *)key;

- (NSData *)getItemValueForKey:(NSString *)key;

- (NSArray *)getItemForKeys:(NSArray *)keys;

- (NSArray *)getItemInfoForKeys:(NSArray *)keys;

- (BOOL)itemExistsForKey:(NSString *)key;

- (int)getItemsCount;

- (int)getItemsSize;

@end
