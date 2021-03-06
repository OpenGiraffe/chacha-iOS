//
//  LLClientManager.m
//  LLWeChat
//
//  Created by GYJZH on 7/20/16.
//  Copyright © 2016 GYJZH. All rights reserved.
//

#import "LLClientManager.h"
#import "LLUtils.h"
#import "LLConfig.h"
#import "LLChatManager.h"
#import "LLUserProfile.h"
#import "LLPushOptions.h"
#import "LLMessageCellManager.h"
#import "LLMessageModelManager.h"
#import "LLRTCView.h"

#import "AppDelegate.h"
#import "ApproxySDK.h"
#import "ApproxySDKOptions.h"

#define KNOTIFICATION_LOGINCHANGE @"NOTIFICATION_LOGINCHANG"

@interface LLClientManager ()

@end


@implementation LLClientManager

CREATE_SHARED_MANAGER(LLClientManager)

- (instancetype)init {
    self = [super init];
    if (self) {
//        [[ApproxySDK getInstance] addDelegate:self delegateQueue:nil];
        [[[ApproxySDK getInstance] getNotify] addDelegate:self delegateQueue:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(loginStateChange:)
                                                     name:KNOTIFICATION_LOGINCHANGE
                                                   object:nil];
    }
    
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - 用户注册 -

- (void)registerWithUsername:(NSString *)username password:(NSString *)password {
    MBProgressHUD *HUD = [LLUtils showActivityIndicatiorHUDWithTitle:@"正在注册..."];
    
    WEAK_SELF;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        ApxErrorCode *error = [[ApproxySDK getInstance] registerWithUsername:username szLoginPass:password];
        if (!error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                HUD.label.text = @"注册成功，正在登陆...";
            });
            
            [weakSelf loginWithUsername:username password:password HUD:HUD];
        }else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [LLUtils hideHUD:HUD animated:YES];
                [weakSelf didRegisterFailedWithError:error];
            });
        }
        
    });
}


- (void)didRegisterFailedWithError:(ApxErrorCode *)error {
    switch (error.errorCode)
    {
        case ApxErrorServerNotReachable:
            [LLUtils showMessageAlertWithTitle:nil message:@"连接服务器失败!"];
            break;
        case ApxErrorUserAlreadyExist:
            [LLUtils showMessageAlertWithTitle:nil message:@"用户名已存在"];
            break;
        case ApxErrorNetworkUnavailable:
            [LLUtils showMessageAlertWithTitle:nil message:@"网路连接失败"];
            break;
        case ApxErrorServerTimeout:
            [LLUtils showMessageAlertWithTitle:nil message:@"连接超时"];
            break;
        default:
            [LLUtils showMessageAlertWithTitle:nil message:@"无法注册"];
            break;
    }

}


#pragma mark - 处理登录、登出

- (void)prepareLogin {
//    [self loginWithResult:[EMClient sharedClient].isAutoLogin];
    [self loginWithResult:[ApproxySDK getInstance].isAutoLogin];
}

- (void)loginWithResult:(BOOL)successed {
    if (!successed) {
        //删除所有缓存的MessageCell
        [[LLMessageCellManager sharedManager] deleteAllCells];
        //删除所有缓存的MessageModel
        [[LLMessageModelManager sharedManager] deleteAllMessageModels];
    }
    [[LLUtils appDelegate] showRootControllerForLoginStatus:successed];
}


- (void)loginWithUsername:(NSString *)username password:(NSString *)password {
    MBProgressHUD *HUD = [LLUtils showActivityIndicatiorHUDWithTitle:@"正在登录..."];
    [self loginWithUsername:username password:password HUD:HUD];
}


- (void)loginWithUsername:(NSString *)username password:(NSString *)password HUD:(MBProgressHUD *)HUD {
    WEAK_SELF;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
            ApxErrorCode *err = [[ApproxySDK getInstance] loginWithUserName:username szLoginPass:password];
            if(err && err.errorCode == ApxErrorCode.BS_OK.errorCode){
                //获取消息推送通知
                [weakSelf loadPushOptionsFromServer];
                //获取联系人
                [[LLContactManager sharedManager] asynGetContactsFromServer:nil];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    [LLUtils hideHUD:HUD animated:YES];
                    [weakSelf loginWithResult:YES];
                });
                
            }else{
                dispatch_async(dispatch_get_main_queue(), ^{
                    [LLUtils hideHUD:HUD animated:YES];
                    [LLUtils showMessageAlertWithTitle:nil message:err.errorMsg];
                });
            }
        
    });
}


- (void)logout {
    MBProgressHUD *HUD = [LLUtils showActivityIndicatiorHUDWithTitle:@"正在退出..."];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [[ApproxySDK getInstance] logouWithUserName];
//        EMError *error = [[EMClient sharedClient] logout:YES];
//
        dispatch_async(dispatch_get_main_queue(), ^{
//            if (error != nil) {
//                [LLUtils showTextHUD:@"解除消息通知失败"];
//            }

            [LLUtils hideHUD:HUD animated:YES];
            [[NSNotificationCenter defaultCenter] postNotificationName:KNOTIFICATION_LOGINCHANGE object:@NO];
        });
    });
}

- (void)didAutoLoginWithError:(ApxErrorCode *)aError {
    if (aError) {
        [self loginWithResult:NO];
        [self didLoginFailedWithError:aError];
    }else {
        [self loadPushOptionsFromServer];
    }

}

- (void)loginStateChange:(NSNotification *)notification {
    BOOL loginSuccess = [notification.object boolValue];
    [self loginWithResult:loginSuccess];
}


- (void)didLoginFromOtherDevice {
    [LLUtils showMessageAlertWithTitle:@"提示" message:@"您已在其他设备登录"];
    [self loginWithResult:NO];
}


- (void)didRemovedFromServer {
    [LLUtils showMessageAlertWithTitle:@"提示" message:@"您的账号已注销"];
    [self loginWithResult:NO];
}

- (void)didLoginFailedWithError:(ApxErrorCode *)error {
    switch (error.errorCode)
    {
        case LLSDKErrorUserAuthenticationFailed:
            [LLUtils showMessageAlertWithTitle:nil message:@"用户验证失败"];
            break;
        case LLSDKErrorServerNotReachable:
            [LLUtils showMessageAlertWithTitle:nil message:@"连接服务器失败!"];
            break;
        case LLSDKErrorNetworkUnavailable:
            [LLUtils showMessageAlertWithTitle:nil message:@"网路连接失败"];
            break;
        case LLSDKErrorServerTimeout:
            [LLUtils showMessageAlertWithTitle:nil message:@"连接超时"];
            break;
        default:
            [LLUtils showMessageAlertWithTitle:nil message:@"无法登陆"];
            break;
    }

    
    [self loginWithResult:NO];
}


#pragma mark - 推送设置 -

- (void)loadPushOptionsFromServer {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [[ApproxySDK getInstance] getPushOptionsFromServer:^(ApxPushOptions *options, ApxErrorCode *errorCode) {
            if (errorCode && errorCode.errorCode == 1000) {
                LLPushOptions *llPushOptions = [LLUserProfile myUserProfile].pushOptions;
                llPushOptions.displayStyle = (LLPushDisplayStyle)options.displayStyle;
                llPushOptions.noDisturbSetting = (LLPushNoDisturbSetting)options.noDisturbStatus;
                llPushOptions.noDisturbingStartH = options.noDisturbingStartH;
                llPushOptions.noDisturbingEndH = options.noDisturbingEndH;
                llPushOptions.isAlertSoundEnabled = options.isAlertSoundEnabled;
                llPushOptions.isVibrateEnabled = options.isVibrateEnabled;
                llPushOptions.isMomentsUpdateEnabled = options.isMomentsUpdateEnabled;
                
//                NSString *key = [NSString stringWithFormat:@"%@_%@",userName, PUSH_OPTIONS_VIBRATE_KEY];
//
//                id setting = [userDefaults objectForKey:key];
//                if (setting) {
//                    llPushOptions.isVibrateEnabled = [setting boolValue];
//                }else {
//                    llPushOptions.isVibrateEnabled = YES;
//                }
//
//                key = [NSString stringWithFormat:@"%@_%@",userName, PUSH_OPTIONS_SOUND_KEY];
//                setting = [userDefaults objectForKey:key];
//                if (setting) {
//                    llPushOptions.isAlertSoundEnabled = [setting boolValue];
//                }else {
//                    llPushOptions.isAlertSoundEnabled = YES;
//                }
                
            }else {
                NSLog(@"PushOptions Error");
            }
        }];
    });
}


- (void)savePushOptionsToServer {
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        ApxPushOptions *pushOptions = [ApproxySDK getInstance].pushOptions;
        LLPushOptions *llPushOptions = [LLUserProfile myUserProfile].pushOptions;
        
        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
        NSString *userName = [[ApproxySDK getInstance] getMyLoginName];
        NSString *key = [NSString stringWithFormat:@"%@_%@",userName, PUSH_OPTIONS_VIBRATE_KEY];
        [userDefaults setObject:@(llPushOptions.isVibrateEnabled) forKey:key];
        
        key = [NSString stringWithFormat:@"%@_%@",userName, PUSH_OPTIONS_SOUND_KEY];
        [userDefaults setObject:@(llPushOptions.isAlertSoundEnabled) forKey:key];
        [userDefaults synchronize];
        
        BOOL isUpdate = NO;
        if (pushOptions.displayStyle != llPushOptions.displayStyle) {
            isUpdate = YES;
            pushOptions.displayStyle = (ApxPushDisplayStyle)llPushOptions.displayStyle;
        }
        
        if (pushOptions.noDisturbStatus != llPushOptions.noDisturbSetting) {
            isUpdate = YES;
            pushOptions.noDisturbStatus = (ApxPushNoDisturbStatus)llPushOptions.noDisturbSetting;
        }
        if (pushOptions.isAlertSoundEnabled != llPushOptions.isAlertSoundEnabled) {
            isUpdate = YES;
            pushOptions.isAlertSoundEnabled = llPushOptions.isAlertSoundEnabled;
        }
        if (pushOptions.isVibrateEnabled != llPushOptions.isVibrateEnabled) {
            isUpdate = YES;
            pushOptions.isVibrateEnabled = llPushOptions.isVibrateEnabled;
        }
        if (pushOptions.isMomentsUpdateEnabled != llPushOptions.isMomentsUpdateEnabled) {
            isUpdate = YES;
            pushOptions.isMomentsUpdateEnabled = llPushOptions.isMomentsUpdateEnabled;
        }
        
        if (isUpdate) {
            [[ApproxySDK getInstance] updatePushOptionsToServer:^(ApxErrorCode *err) {
                if (err && err.errorCode == 1000) {
                    NSLog(@"更新推送设置成功");
                }else{
                    NSLog(@"更新推送设置失败");
                }
            }];
            
        }
           
    });
}


#pragma mark - 其他 -

- (void)didConnectionStateChanged:(ApxConnectionState)aConnectionState {
    _connectionState = aConnectionState;
  
    [[NSNotificationCenter defaultCenter] postNotificationName:LLConnectionStateDidChangedNotification object:self userInfo:@{@"connectionState":@(aConnectionState)}];
    if(aConnectionState == ApxConnectionConnected){
        [[NSNotificationCenter defaultCenter] postNotificationName:LLContactChangedNotification object:[LLContactManager sharedManager]];
    }
}

- (void)saveLastLoginUsername:(NSString *)username {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setValue:username forKey:LAST_LOGIN_USERNAME_KEY];
    [ud synchronize];
}

@end
