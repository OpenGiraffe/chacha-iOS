//
//  LLContactModel.m
//  LLWeChat
//
//  Created by GYJZH on 9/9/16.
//  Copyright © 2016 GYJZH. All rights reserved.
//

#import "LLContactModel.h"
#import "LLUtils.h"

@implementation LLContactModel

- (instancetype)initWithBuddy:(NSString *)buddy {
    self = [super init];
    if (self) {
        _userName = buddy;
        _openID = buddy;
        _pinyinOfUserName = [LLUtils pinyinOfString:_userName];
        _nickname = @"";
        _avatarImage = [UIImage imageNamed:@"icon_avatar"];
    }
    
    return self;
}

- (instancetype)initWithBuddy:(NSString *)buddy openID:(NSString *)openID {
    self = [super init];
    if (self) {
        _userName = buddy;
        _openID = openID;
        _pinyinOfUserName = [LLUtils pinyinOfString:_userName];
        _nickname = buddy;
        _avatarImage = [UIImage imageNamed:@"icon_avatar"];
    }
    
    return self;
}

- (instancetype)initWithBuddy:(NSString *)buddy openID:(NSString *)openID avatar:(NSString *)avatar {
    self = [super init];
    if (self) {
        _userName = buddy;
        _openID = openID;
        _pinyinOfUserName = [LLUtils pinyinOfString:_userName];
        _nickname = buddy;
        if(avatar != nil && [ApproxySDKUtil isFileExist:avatar fullPath:YES]){
            _avatarImage = [UIImage imageWithContentsOfFile:avatar];
        }else{
            _avatarImage = [UIImage imageNamed:@"icon_avatar"];
        }
    }
    
    return self;
}


@end
