//
//  AppDelegate.m
//  LLWeChat
//
//  Created by GYJZH on 7/16/16.
//  Copyright © 2016 GYJZH. All rights reserved.
//

#import "AppDelegate.h"
#import "LLUtils.h"
#import "LLClientManager.h"
#import "LLGDConfig.h"
#import "LLEmotionModelManager.h"
#import "LLUserProfile.h"
#import "LLConfig.h"
#import "UIImage+LLExt.h"
#import <AMapFoundationKit/AMapFoundationKit.h>
#import "LLAudioManager.h"
#import "LLMessageThumbnailManager.h"
#import "ApproxySDK.h"
#import "ApproxySDKOptions.h"

@interface AppDelegate ()

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    [[LLEmotionModelManager sharedManager] prepareEmotionModel];
    
#ifdef __IPHONE_11_0
//    if (@available(ios 11.0,*))
//    {
//        UIScrollView.appearance.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
//        UITableView.appearance.estimatedRowHeight = 0;
//        UITableView.appearance.estimatedSectionFooterHeight = 0;
//        UITableView.appearance.estimatedSectionHeaderHeight = 0;
//    }
#endif

    [self configureAPIKey];//配置高德地图
    [self initializeSDK];
    [self initUIAppearance];
    [self playTrick];
    
//    [self registerRemoteNotification];

    //准备用户登录
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [UIColor whiteColor];
    [self.window makeKeyAndVisible];
    
    [[LLClientManager sharedManager] prepareLogin];
    
    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application {
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    
//    [[EMClient sharedClient] applicationDidEnterBackground:application];
//    [[LLAudioManager sharedManager] stopRecording];
    [[LLAudioManager sharedManager] stopPlaying];
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    
//    [[EMClient sharedClient] applicationWillEnterForeground:application];
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

#pragma mark - View Controller

- (void)showRootControllerForLoginStatus:(BOOL)successed {
    UIStoryboard *storyboard = [LLUtils mainStoryboard];

    if (successed) {
        
        self.mainViewController = [[LLMainViewController alloc] init];
        self.loginViewController = nil;
        self.window.rootViewController = self.mainViewController;
    }else {
        self.loginViewController = [storyboard instantiateViewControllerWithIdentifier:SB_LOGIN_VC_ID];
        self.mainViewController = nil;

        self.window.rootViewController = self.loginViewController;
        
    }

}


#pragma mark - 初始化SDK

- (void)initializeSDK {
    
//#warning 初始化环信SDK
//#warning SDK注册 APNS文件的名字, 需要与后台上传证书时的名字一一对应
//#warning 本项目没有使用离线推送功能
    NSString *apnsCertName = nil;
#if DEBUG
    apnsCertName = @"chatdemoui_dev";
#else
    apnsCertName = @"chatdemoui";
#endif
    
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *appkey = [ud stringForKey:@"identifier_appkey"];
    if (!appkey) {
        appkey = EASE_MOB_APP_KEY;
        [ud setObject:appkey forKey:@"identifier_appkey"];
    }

//    //初始化EMClient
//    EMOptions *options = [EMOptions optionsWithAppkey:appkey];
//    options.apnsCertName = apnsCertName;
//    options.isAutoAcceptGroupInvitation = NO;
//    options.isAutoAcceptFriendInvitation = NO;
//    options.isAutoLogin = YES;
//    options.enableConsoleLog = YES;
//    options.isSandboxMode = NO; //YES为SDK内部测试使用
//
//    [[EMClient sharedClient] initializeSDKWithOptions:options];
    ApproxySDKOptions *options = [ApproxySDKOptions optionsWithAppkey:appkey];
//  [options setClusterIP:APPROXY_CLUSTERIP];
//  [options setClusterPort:APPROXY_CLUSTERPO];
    
    [options setClusterGroup:APPROXY_CLUSTERGROUP];
    [options setIsAutoLogin:YES];
    
    
    //注册密码错误事件
    [ApproxySDK nf_subscribe:self selector:@selector(onLoginPassError:) name:@"onLoginFail"];
    //注册登录状态事件
    [ApproxySDK nf_subscribe:self selector:@selector(onLoginSta:) name:@"onLoginSta"];
    //注册登录成功事件
    [ApproxySDK nf_subscribe:self selector:@selector(onLoginSucc:) name:@"onLoginSucc"];
    //注册消息接收回调
    [ApproxySDK nf_subscribe:self selector:@selector(onReceiveMessages:) name:@"onReceiveMessages"];
    ApproxySDK *sdk = [ApproxySDK getInstance];
    
    [sdk initSDK:options];

}

- (void)initUIAppearance {
    [UINavigationBar appearance].tintColor = [UIColor whiteColor];
    [UINavigationBar appearance].barTintColor = [UIColor blackColor];
    [UINavigationBar appearance].barStyle = UIBarStyleBlack;
    [[UIBarButtonItem appearanceWhenContainedIn:[UINavigationBar class], nil] setTitleTextAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:16]} forState:UIControlStateNormal];
    
    //设置返回按钮
    UIEdgeInsets insets = UIEdgeInsetsMake(0, 0, -1, 0);
    UIImage *image = [UIImage imageNamed:@"barbuttonicon_back"];    
    UIImage *backArrowImage = [image imageWithAlignmentRectInsets:insets];

    [UINavigationBar appearance].backIndicatorImage = backArrowImage;
    [UINavigationBar appearance].backIndicatorTransitionMaskImage = [UIImage imageWithColor:[UIColor clearColor] size:backArrowImage.size];
    
    [[UIBarButtonItem appearance] setBackButtonTitlePositionAdjustment:UIOffsetMake(-4, 0) forBarMetrics:UIBarMetricsDefault];
    
    [[UINavigationBar appearance] setTitleTextAttributes:@{NSFontAttributeName : [UIFont boldSystemFontOfSize:18], NSForegroundColorAttributeName : [UIColor whiteColor]}];
    [[UINavigationBar appearance] setTranslucent:NO];

}

#pragma mark - 配置高德地图

- (void)configureAPIKey {
    if ([APIKey length] == 0) {
        [LLUtils showMessageAlertWithTitle:@"OK" message:@"apiKey为空，请检查key是否正确设置。"];
    }
//    [AMapServices sharedServices].enableHTTPS = YES;
    [AMapServices sharedServices].apiKey = (NSString *)APIKey;
}


#pragma mark - 注册Apple 推送通知


// 注册推送
- (void)registerRemoteNotification
{
    UIApplication *application = [UIApplication sharedApplication];
    application.applicationIconBadgeNumber = 0;
    
    //IOS8.0,需要先注册通知类型
    if([application respondsToSelector:@selector(registerUserNotificationSettings:)])
    {
        UIUserNotificationType notificationTypes = UIUserNotificationTypeBadge | UIUserNotificationTypeSound | UIUserNotificationTypeAlert;
        UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:notificationTypes categories:nil];
        [application registerUserNotificationSettings:settings];
    }
    
#if !TARGET_OS_SIMULATOR
    //iOS8 注册APNS
    if ([application respondsToSelector:@selector(registerForRemoteNotifications)]) {
        [application registerForRemoteNotifications];
    }
#endif
}

- (void)application:(UIApplication *)application didRegisterUserNotificationSettings:(UIUserNotificationSettings *)notificationSettings {
    NSMutableArray *strs = [[NSMutableArray alloc] init];
    if (notificationSettings.types & UIUserNotificationTypeBadge) {
        [strs addObject:@"Badge"];
    }
    if (notificationSettings.types & UIUserNotificationTypeSound) {
        [strs addObject:@"Sound"];
    }
    
    if (notificationSettings.types & UIUserNotificationTypeAlert) {
        [strs addObject:@"Alert"];
    }
    
    
    NSLog(@"允许的通知类型有: %@", [strs componentsJoinedByString:@", "]);
}

// 将得到的deviceToken传给SDK
- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
//        [[EMClient sharedClient] bindDeviceToken:deviceToken];
    });
}

// 注册deviceToken失败
- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error
{
    [LLUtils showMessageAlertWithTitle:NSLocalizedString(@"apns.failToRegisterApns", @"Fail to register apns") message:error.description];
    
}

#pragma mark - Local Notification -

- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification {
    
}


#pragma mark - Remote Notification - 

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo {
    
}

#pragma mark - Trick - 

- (void)playTrick {
//    UITextField *textField = [[UITextField alloc] init];
//    [self.window addSubview:textField];
//    [textField becomeFirstResponder];
//    [textField removeFromSuperview];
}

#pragma mark - Event -
// 密码错误
- (void) onLoginPassError:(id)o{
    NSDictionary *data = [o valueForKey:@"userInfo"];
    NSLog(@"onLoginPassError: %@",data[@"szUserName"]);
    
    //密码错误 跳转到登录页面
//    [[LLUtils appDelegate] showRootControllerForLoginStatus:false];
    [[LLClientManager sharedManager] didAutoLoginWithError:ApxErrorCode.User_LoginPassError];
}

- (void) onLoginSta:(id)o{
    NSDictionary *data = [o valueForKey:@"userInfo"];
    NSLog(@"onLoginSta: %@",data[@"szUserReason"]);
    NSString *reason = data[@"szUserReason"];
    if([reason containsString:@"未记住用户名"] || [reason containsString:@"未记住密码"]){
        //用这个代码能保证执行的是UI线程
        dispatch_async(dispatch_get_main_queue(), ^{
            //跳转到登录页面
            [[LLUtils appDelegate] showRootControllerForLoginStatus:false];
        });
        return ;
    }
}
- (void) onLoginSucc:(id)o{
    NSDictionary *data = [o valueForKey:@"userInfo"];
    NSLog(@"onLoginSucc: %@",data[@"szUserName"]);
    
    void (^completeBlock)(ContactUser *myInfo) = ^(ContactUser *myInfo){
        if(myInfo){
            [[LLUserProfile myUserProfile] initUserProfileWithUserName:myInfo.loginName nickName:myInfo.name?myInfo.name:nil avatarURL:[ApproxySDKUtil isFileExist:myInfo.avatar fullPath:YES]?myInfo.avatar:nil];
        }else{
            [[LLUserProfile myUserProfile] initUserProfileWithUserName:[ApproxySDK getInstance].currentUserName nickName:nil avatarURL:nil];
        }
    };
                                                   
    //获取个人用户信息
    [[ApproxySDK getInstance] getMyInfo:completeBlock];
    
    //加载推送信息等
    [[LLClientManager sharedManager] didAutoLoginWithError:nil];
}

- (void) onReceiveMessages:(id)o {
    ApproxySDKMessage *message = [o valueForKey:@"userInfo"];
    NSLog(@"onReceiveMessages: %@", message);
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray *array = [[[NSArray alloc] init]arrayByAddingObject:message];
        [[LLChatManager sharedManager] didReceiveMessages:array];
    });
    
}

- (void)dealloc{
    [ApproxySDK nf_unsubscribe:self];
}
@end
