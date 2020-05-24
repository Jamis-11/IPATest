//
//  SYPayManager.h
//  null
//
//  Created by Null on 2020/5/8.
//  Copyright © 2020年 Null. All rights reserved.
//

#import <Foundation/Foundation.h>


typedef void(^SYCompleteBlock)(NSDictionary *resultDic);
typedef void(^SYFailureBlock)(NSError * error);

@interface SYPayManager : NSObject

// 是否在支付中
@property (nonatomic, assign) BOOL isInPayment;

@property (nonatomic,   copy) NSString * order_id;

+ (instancetype)sharedManager;

#pragma mark - Apple

- (void)applePayForProduct:(NSString *)identifier
                   orderId:(NSString *)orderId
                   success:(SYCompleteBlock)success
                   failure:(SYFailureBlock)failure;;

// 测试试用
- (void)localVerifyReceipt;

// 重试验证本地缓存的支付凭证
- (void)retryVerifyLocalCacheReceipt;

@end
