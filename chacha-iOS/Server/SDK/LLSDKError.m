//
//  LLSDKError.m
//  LLWeChat
//
//  Created by GYJZH on 8/16/16.
//  Copyright © 2016 GYJZH. All rights reserved.
//

#import "LLSDKError.h"
#import "ApproxySDKOptions.h"

@implementation LLSDKError

+ (instancetype)errorWithEMError:(ApxErrorCode *)error {
    LLSDKError *_error = [[LLSDKError alloc] initWithDescription:error.errorMsg code:(LLSDKErrorCode)error.errorCode];
    return _error;
}

- (instancetype)initWithDescription:(NSString *)aDescription code:(LLSDKErrorCode)aCode {
    self = [super init];
    if (self) {
        self.errorDescription = aDescription;
        self.errorCode = aCode;
    }
    
    return self;
}

+ (instancetype)errorWithDescription:(NSString *)aDescription code:(LLSDKErrorCode)aCode {
    LLSDKError *error = [[LLSDKError alloc] initWithDescription:aDescription code:aCode];
    return error;
}

@end
