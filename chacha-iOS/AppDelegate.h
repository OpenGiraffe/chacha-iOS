//
//  AppDelegate.h
//  LLWeChat
//
//  Created by GYJZH on 7/16/16.
//  Copyright © 2016 GYJZH. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "LLLoginViewController.h"
#import "LLMainViewController.h"

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

@property (nonatomic) LLLoginViewController *loginViewController;

@property (nonatomic) LLMainViewController *mainViewController;

- (void)showRootControllerForLoginStatus:(BOOL)successed;
// 密码错误
- (void) onLoginPassError:(id)o;
// 登录状态
- (void) onLoginSta:(id)o;
- (void) onLoginSucc:(id)o;
- (void) onReceiveMessages:(id)o;
@end

