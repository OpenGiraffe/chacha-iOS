//
//  LLMessageSearchResultModel.h
//  LLWeChat
//
//  Created by GYJZH on 06/10/2016.
//  Copyright © 2016 GYJZH. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ApproxySDKOptions.h"

@interface LLMessageSearchResultModel : NSObject

@property (nonatomic) NSString *nickName;

@property (nonatomic) NSTimeInterval timestamp;

//SDK专用，Client代码不直接访问该变量
@property (nonatomic) ApproxySDKMessage * sdk_message;

- (instancetype)initWithMessage:(ApproxySDKMessage *)message;

@end
