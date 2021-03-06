//
//  LLClientManager.h
//  LLWeChat
//
//  Created by GYJZH on 7/20/16.
//  Copyright © 2016 GYJZH. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "LLViewController.h"
#import "ApproxySDKOptions.h"
#import "ApproxySDKNotify.h"

@interface LLClientManager : NSObject <ApproxySDKClientDelegate>

@property (nonatomic) ApxConnectionState connectionState;

+ (instancetype)sharedManager;

- (void)prepareLogin;

/**
 *  该方法后台登出，同时负责HUD显示
 */
- (void)logout;

//该方法为异步调用，同时负责HUD显示
- (void)registerWithUsername:(NSString *)username password:(NSString *)password;

/*
 * 该方法为异步调用,同时负责HUD显示
 *
 * */
- (void)loginWithUsername:(NSString *)username password:(NSString *)password;

- (void)loadPushOptionsFromServer;

- (void)savePushOptionsToServer;

@end
