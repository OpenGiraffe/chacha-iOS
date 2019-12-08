//
//  LLMessageUploader.m
//  LLWeChat
//
//  Created by GYJZH on 9/17/16.
//  Copyright © 2016 GYJZH. All rights reserved.
//

#import "LLMessageUploader.h"
#import "LLChatManager.h"
#import "LLUtils.h"
#import "ApproxySDKOptions.h"
#import "ApproxySDK.h"


@interface LLMessageUploader ()

@property (nonatomic) dispatch_queue_t queue_upload;

@property (nonatomic) dispatch_semaphore_t semaphore;

@end

@implementation LLMessageUploader


+ (instancetype)imageUploader {
    static LLMessageUploader *_instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _instance = [[LLMessageUploader alloc] initWithQueueLabel:@"IMAGE_UPLOADER" concurrentNum:1];
    });
    
    return _instance;
}

+ (instancetype)videoUploader {
    static LLMessageUploader *_instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _instance = [[LLMessageUploader alloc] initWithQueueLabel:@"VIDEO_UPLOADER" concurrentNum:1];
    });
    
    return _instance;
}

+ (instancetype)defaultUploader {
    static LLMessageUploader *_instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _instance = [[LLMessageUploader alloc] initWithQueueLabel:@"DEFAULT_UPLOADER" concurrentNum:6];
    });
    
    return _instance;
}

- (instancetype)initWithQueueLabel:(NSString *)label concurrentNum:(long)semaphore {
    self = [super init];
    if (self) {
        _queue_upload = dispatch_queue_create(label.UTF8String, DISPATCH_QUEUE_CONCURRENT);
        _semaphore = dispatch_semaphore_create(semaphore);
    }
    
    return self;
}

- (void)asynUploadMessage:(LLMessageModel *)model {
    [self upload:model];

}

- (void)upload:(LLMessageModel *)messageModel {
    WEAK_SELF;
    dispatch_async(_queue_upload, ^{
        [weakSelf uploadBlock:messageModel];
    });
}

- (void)uploadBlock:(LLMessageModel *)messageModel {
    NSLog(@"Before Wait");
    dispatch_semaphore_wait(self.semaphore, DISPATCH_TIME_FOREVER);

    BOOL needProgress = NO;
    if (messageModel.messageBodyType == kLLMessageBodyTypeVideo ||
        messageModel.messageBodyType == kLLMessageBodyTypeImage) {
        needProgress = YES;
    }
    
    BOOL needResend = NO;
    if (messageModel.sdk_message.status == kLLMessageStatusFailed)
        needResend = YES;
    
    WEAK_SELF;
    void (^progressBlock)(int _progress) = ^(int _progress) {
        messageModel.fileUploadProgress = _progress;
        [messageModel setNeedsUpdateUploadStatus];
        
        [[LLChatManager sharedManager] postMessageUploadStatusChangedNotification:messageModel];
    };
    
    void (^completeBlock)(ApproxySDKMessage *message, ApxErrorCode *_error) = ^(ApproxySDKMessage *message, ApxErrorCode *_error) {
        NSLog(@"Message Upload Complete messageId=[%@]", messageModel.messageId);

        dispatch_semaphore_signal(weakSelf.semaphore);
        
        LLSDKError *error = _error ? [LLSDKError errorWithErrorCode:_error] : nil;
        messageModel.error = error;
        [messageModel setNeedsUpdateUploadStatus];
        
        //消息上行成功
        if (_error.errorCode == ApxErrorCode.Mes_upOK.errorCode
            || _error.errorCode == ApxErrorCode.Mes_dstUserOffline.errorCode
            || _error.errorCode == ApxErrorCode.Mes_pushOK.errorCode) {
            [messageModel updateMessage:message updateReason:kLLMessageModelUpdateReasonUploadComplete];
            messageModel.fileUploadProgress = 100;
            [messageModel internal_setMessageStatus:kLLMessageStatusSuccessed];
            [[LLChatManager sharedManager] postMessageUploadStatusChangedNotification:messageModel];
        }else{
            NSLog(@"消息上行失败：errorCode:%d, errorMsg:%@",_error.errorCode,_error.errorMsg);
            //消息上行失败
            [messageModel internal_setMessageStatus:kLLMessageStatusFailed];
            
            [[LLChatManager sharedManager] postMessageUploadStatusChangedNotification:messageModel];
        }
        
    };

    if (needResend) {
        [[ApproxySDK getInstance].chatManager asyncResendMessage:messageModel.sdk_message progress: needProgress ? progressBlock : nil completion:completeBlock];
        
    }else {
        [[ApproxySDK getInstance].chatManager asyncSendMessage:messageModel.sdk_message progress: needProgress ? progressBlock : nil completion:completeBlock];
    }
    
    //将状态设置为《传送中》
    [messageModel internal_setMessageStatus:kLLMessageStatusDelivering];
    [[LLChatManager sharedManager] postMessageUploadStatusChangedNotification:messageModel];
}



@end
