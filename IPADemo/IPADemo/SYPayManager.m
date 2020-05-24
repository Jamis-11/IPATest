//
//  SYPayManager.m
//  null
//
//  Created by Null on 2020/5/8.
//  Copyright © 2020年 Null. All rights reserved.
//

#import "SYPayManager.h"
#import <StoreKit/StoreKit.h>


@interface SYPayManager ()<SKProductsRequestDelegate, SKPaymentTransactionObserver>

@property (strong, nonatomic) SKPayment * payment;
@property (strong, nonatomic) SKMutablePayment * g_payment;
@property (nonatomic, strong) NSString * payProductIdentifier;

@property (nonatomic, copy) SYCompleteBlock paySuccessBlock;
@property (nonatomic, copy) SYFailureBlock  payErrorBlock;

@end

@implementation SYPayManager

+ (instancetype)sharedManager {
    static dispatch_once_t onceToken;
    static SYPayManager * storeManagerSharedInstance;
    dispatch_once(&onceToken, ^{
        storeManagerSharedInstance = [[SYPayManager alloc] init];
         [[SKPaymentQueue defaultQueue] addTransactionObserver:storeManagerSharedInstance];
    });
    return storeManagerSharedInstance;
}

- (void)showMessage:(NSString *)message {
    UIAlertController * alert = [UIAlertController alertControllerWithTitle:message message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    UIViewController * rootVC = [UIApplication sharedApplication].delegate.window.rootViewController;
    [rootVC presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Apple Pay

- (NSString *)localPathForStore:(NSString *)filename {
    NSString * path = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).lastObject;
    path = [path stringByAppendingPathComponent:@"applePay_receipts"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        // Directory does not exist so create it
        [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    }
    if (filename) {
        path = [path stringByAppendingPathComponent:filename];
    }
    return path;
}

- (void)storeReceipt:(NSData *)receipt orderId:(NSString *)orderId {
    BOOL flag = [receipt writeToFile:[self localPathForStore:orderId] atomically:YES];
    NSLog(@"%s storeReceipt - %@", __func__, flag?@"true":@"false");
}

- (void)removeReceiptWithOrderId:(NSString *)orderId {
    NSError * error;
    NSFileManager * manager = [[NSFileManager alloc] init];
    if ([manager fileExistsAtPath:[self localPathForStore:orderId]]) {
        [manager removeItemAtPath:[self localPathForStore:orderId] error:&error];
    }
    NSLog(@"%s %@", __func__, error);
}

- (NSArray *)localReceipts {
    NSString * dir = [self localPathForStore:nil];
    NSFileManager * manager = [[NSFileManager alloc] init];
    NSArray * files = [manager subpathsAtPath:dir];
    return files;
}

- (void)retryVerifyLocalCacheReceipt {
    NSArray * receipts = [self localReceipts];
    if (!receipts || receipts.count == 0) {
        return;
    }
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [receipts enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSString * path = [self localPathForStore:obj];
            NSData * data = [NSData dataWithContentsOfFile:path];
            [self verifyReceipt:data orderId:obj complete:^{
                [self removeReceiptWithOrderId:obj];
            }];
        }];
    });
}

- (void)applePayForProduct:(NSString *)identifier
                   orderId:(NSString *)orderId
                   success:(SYCompleteBlock)success
                   failure:(SYFailureBlock)failure {
    if ([SKPaymentQueue canMakePayments]) {
        self.order_id = orderId;
        self.isInPayment = YES;
        self.payErrorBlock = failure;
        self.paySuccessBlock = success;
        self.payProductIdentifier = identifier;
        [self requestProductData:identifier];
    } else {
        [self showMessage:@"请设置允许应用内付费购买"];
//         [SYHUDView showMessage:@"请设置允许应用内付费购买"];
    }
}

- (void)requestProductData:(NSString *)type {
    //根据商品ID查找商品信息
    NSArray *product = [[NSArray alloc] initWithObjects:type, nil];
    NSSet * nsset = [NSSet setWithArray:product];
    //创建SKProductsRequest对象，用想要出售的商品的标识来初始化， 然后附加上对应的委托对象。
    //该请求的响应包含了可用商品的本地化信息。
    SKProductsRequest *request = [[SKProductsRequest alloc] initWithProductIdentifiers:nsset];
    request.delegate = self;
    [request start];
}

- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response {
    //接收商品信息
    NSArray *product = response.products;
    if ([product count] == 0) {
        if (self.payErrorBlock) {
            self.payErrorBlock([NSError errorWithDomain:@"apple.pay.error" code:-1001 userInfo:@{@"message":@"无有效商品"}]);
        }
        return;
    }
    // SKProduct对象包含了在App Store上注册的商品的本地化信息。
    SKProduct *storeProduct = nil;
    for (SKProduct *pro in product) {
        if ([pro.productIdentifier isEqualToString:self.payProductIdentifier]) {
            storeProduct = pro;
        }
    }
    //创建一个支付对象，并放到队列中
    self.g_payment = [SKMutablePayment paymentWithProduct:storeProduct];
    //设置购买的数量
    self.g_payment.quantity = 1;
    [[SKPaymentQueue defaultQueue] addPayment:self.g_payment];
}

- (void)request:(SKRequest *)request didFailWithError:(NSError *)error {
    if (self.payErrorBlock) {
        self.payErrorBlock(error);
    }
}

- (void)requestDidFinish:(SKRequest *)request {
    NSLog(@"商品信息返回结束");
}

//监听购买结果
- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray *)transaction {
    for (SKPaymentTransaction *tran in transaction) {
        // 如果小票状态是购买完成
        if (SKPaymentTransactionStatePurchased == tran.transactionState) {
            [self completeTransaction:tran];
            //商品购买成功可调用本地接口
        } else if (SKPaymentTransactionStateRestored == tran.transactionState) {
            // 将交易从交易队列中删除
            [[SKPaymentQueue defaultQueue] finishTransaction:tran];
        } else if (SKPaymentTransactionStateFailed == tran.transactionState) {
            // 支付失败
            // 将交易从交易队列中删除
            if (self.payErrorBlock) {
                NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:0];
                [userInfo setValue:tran.error.localizedDescription forKey:@"NSLocalizedDescription"];
                NSError *error = [[NSError alloc] initWithDomain:NSLocalizedDescriptionKey code:0 userInfo:userInfo];
                self.payErrorBlock(error);
            }
            [[SKPaymentQueue defaultQueue] finishTransaction:tran];
        }
    }
}
//交易结束
- (void)completeTransaction:(SKPaymentTransaction *)transaction {
    [self verifyPruchase:self.order_id];
    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
}
#pragma mark 验证购买凭据

//测试验证地址:https://sandbox.itunes.apple.com/verifyReceipt
//正式验证地址:https://buy.itunes.apple.com/verifyReceipt
- (void)verifyPruchase:(NSString *)orderId {
    // 验证凭据，获取到苹果返回的交易凭据
    // appStoreReceiptURL iOS7.0增加的，购买交易完成后，会将凭据存放在该地址
    NSURL *receiptURL = [[NSBundle mainBundle] appStoreReceiptURL];
    // 从沙盒中获取到购买凭据
    NSData *receiptData = [NSData dataWithContentsOfURL:receiptURL];
    if (!receiptData || !orderId) {
        return;
    }
    // 暂存支付凭证
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [self storeReceipt:receiptData orderId:orderId];
    });
    NSString *encodeStr = [receiptData base64EncodedStringWithOptions:NSDataBase64EncodingEndLineWithLineFeed];
    NSLog(@"%s, %@", __func__, encodeStr);

    //  调用后台接口，验证支付凭证， 验证z成功后删除本地缓存的支付凭证
//      dispatch_async(dispatch_get_global_queue(0, 0), ^{
//          [self removeReceiptWithOrderId:orderId];
//      });

    self.isInPayment = NO;
}


- (void)verifyReceipt:(NSData *)data orderId:(NSString *)orderId complete:(dispatch_block_t)handler {
    if (!data || !orderId) {
        return;
    }
    NSString *encodeStr = [data base64EncodedStringWithOptions:NSDataBase64EncodingEndLineWithLineFeed];
    NSDictionary *param = @{@"order_id":orderId, @"receipt":encodeStr};
//    调用后台接口，验证支付凭证
}

// 测试验证本地支付凭证
- (void)localVerifyReceipt {
    NSError *error;
    NSURL *receiptURL = [[NSBundle mainBundle] appStoreReceiptURL];
    // 从沙盒中获取到购买凭据
    NSData *receiptData = [NSData dataWithContentsOfURL:receiptURL];
    NSString * encodeStr = [receiptData base64EncodedStringWithOptions:NSDataBase64EncodingEndLineWithLineFeed];
    // 秘钥: 7f223145617f44c3b2d133391dd468ff
    NSDictionary *requestContents = @{@"receipt-data":encodeStr,@"password":@"7f223145617f44c3b2d133391dd468ff"};
    NSData *requestData = [NSJSONSerialization dataWithJSONObject:requestContents
                                                          options:0
                                                            error:&error];
    
    //In the test environment, use https://sandbox.itunes.apple.com/verifyReceipt
    //In the real environment, use https://buy.itunes.apple.com/verifyReceipt
    
//     NSString *serverString = @"https://buy.itunes.apple.com/verifyReceipt";
    NSString *serverString = @"https://sandbox.itunes.apple.com/verifyReceipt";
    NSURL * storeURL = [NSURL URLWithString:serverString];
    NSMutableURLRequest * storeRequest = [NSMutableURLRequest requestWithURL:storeURL];
    [storeRequest setHTTPMethod:@"POST"];
    [storeRequest setHTTPBody:requestData];
    
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    [NSURLConnection sendAsynchronousRequest:storeRequest queue:queue
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        if (connectionError) {
            // 无法连接服务器,购买校验失败
            NSLog(@"appStoreReceipt 验证结果： %@",connectionError);
        } else {
            NSError *error;
            NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
            NSLog(@"appStoreReceipt 验证结果: %@",jsonResponse);
        }
    }];
}

@end
