//
// Created by GYJZH on 7/19/16.
// Copyright (c) 2016 GYJZH. All rights reserved.
//

#import "LLChatManager.h"
#import "LLUtils.h"
#import "LLConfig.h"
#import "LLPushOptions.h"
#import "LLSDKError.h"
#import "LLUserProfile.h"
#import "LLLocationManager.h"
#import "LLChatManager+MessageExt.h"
#import "LLMessageAttachmentDownloader.h"
#import "LLMessageModelManager.h"
#import "LLMessageCellManager.h"
#import "LLMessageUploader.h"
#import "LLMessageThumbnailManager.h"
#import "LLMessageCacheManager.h"
#import "LLConversationModelManager.h"
#import "LLRTCView.h"

#import "ApproxySDKOptions.h"
#import "ApproxySDK.h"

#define NEW_MESSAGE_QUEUE_LABEL "NEW_MESSAGE_QUEUE"

static NSDate *lastPlaySoundDate;

@interface LLChatManager ()

@property (nonatomic) dispatch_queue_t messageQueue;

@property (nonatomic) dispatch_queue_t uploader_queue;

@property (nonatomic) dispatch_semaphore_t uploadImageSemaphore;

@property (nonatomic) dispatch_semaphore_t uploadVideoSemaphore;

@end


@implementation LLChatManager{
    LLRTCView *_presentView;
}

CREATE_SHARED_MANAGER(LLChatManager)

- (instancetype)init {
    self = [super init];
    if (self) {
        _messageQueue = dispatch_queue_create(NEW_MESSAGE_QUEUE_LABEL, DISPATCH_QUEUE_SERIAL );
        
        _uploadImageSemaphore = dispatch_semaphore_create(1);
        
        _uploadVideoSemaphore = dispatch_semaphore_create(1);

        [[[ApproxySDK getInstance] getNotify] addChatManagerDelegate:self delegateQueue:nil];
        lastPlaySoundDate = [NSDate date];
    }
    
    return self;
}

#pragma mark - 处理会话列表

- (void)processConversationList:(NSArray<ApproxySDKConversation *> *)conversationList {
    NSArray<LLConversationModel *> *conversationListModels = [[LLConversationModelManager sharedManager] updateConversationListAfterLoad:conversationList];
    
    WEAK_SELF;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf.conversationListDelegate conversationListDidChanged:conversationListModels];
    });

}


- (void)getAllConversationFromDB {
    NSLog(@"从数据库中加载会话");
    
    WEAK_SELF;
    dispatch_async(_messageQueue, ^{
//        NSArray<EMConversation *> *array = [[EMClient sharedClient].chatManager loadAllConversationsFromDB];
//        [weakSelf processConversationList:array];

        NSArray<ApproxySDKConversation *> *array = [[ApproxySDK getInstance].chatManager loadAllConversationsFromDB];
        [weakSelf processConversationList:array];
        
    });
}

- (void)getAllConversation {
    NSLog(@"从内存中加载会话");
    
    WEAK_SELF;
    dispatch_async(_messageQueue, ^{
//        NSArray<EMConversation *> *array = [[EMClient sharedClient].chatManager getAllConversations];
        NSArray<ApproxySDKConversation *> *array = [[ApproxySDK getInstance].chatManager getAllConversations];
        [weakSelf processConversationList:array];

    });
}


//会话列表发生改变 来自 ChatManagerDelegate
- (void)didUpdateConversationList:(NSArray *)aConversationList {
    NSLog(@"消息列表发生改变");
}

- (BOOL)deleteConversation:(LLConversationModel *)conversationModel {
    BOOL result = [[ApproxySDK getInstance].chatManager deleteConversation:conversationModel.sdk_conversation.conversationId deleteMessages:YES];
    if (result) {
        [[LLMessageCacheManager sharedManager] deleteConversation:conversationModel.conversationId];
        [[LLConversationModelManager sharedManager] removeConversationModel:conversationModel];
    }
    
    return result;
}


#pragma mark - 处理消息

- (void) preprocessMessageModel:(LLMessageModel *)messageModel priority:(LLMessageDownloadPriority)priority {
    
    if (messageModel.isFromMe) {
        LLMessageStatus messageStatus = messageModel.messageStatus;
        //需要上传的消息
        if (messageStatus == kLLMessageStatusPending) {
            [self sendMessage:messageModel needInsertToDB:NO];
        }
        
    }else {
        //下载缩略图
        [self asyncDownloadMessageThumbnail:messageModel completion:nil];

        //需要下载附件
        if (messageModel.messageBodyType == kLLMessageBodyTypeImage) {
            if (messageModel.messageDownloadStatus == kLLMessageDownloadStatusPending) {
                [self asynDownloadMessageAttachments:messageModel progress:nil completion:nil];
            }
        }else if (messageModel.messageBodyType == kLLMessageBodyTypeFile ||
            messageModel.messageBodyType == kLLMessageBodyTypeVoice ||
            messageModel.messageBodyType == kLLMessageBodyTypeLocation) {
            LLMessageDownloadStatus attachmentDownloadStatus = messageModel.messageDownloadStatus;
            
            if (attachmentDownloadStatus == kLLMessageDownloadStatusFailed ||
                attachmentDownloadStatus == kLLMessageDownloadStatusPending) {
                [self asynDownloadMessageAttachments:messageModel progress:nil completion:nil];
            }
        }
    }
   
}

# pragma mark - 音视频通话
//被叫方：接收到呼叫事件
- (void)didReceiveCall:(ApproxySDKMessage *)aMessage{
    
    ImCallin *im = (ImCallin *)aMessage.body.im;
    NSString *senderAgent = im.senderAgent;
    //显示等待接受界面
    [[ApproxySDK getInstance].contactManager asyncGetContactByID:senderAgent success:^(ContactUser *u) {
        dispatch_async(dispatch_get_main_queue(), ^{
            LLRTCView *presentView = nil;
            NSNumber *callType = im.callType;
            if([callType intValue] == ApxCallVA_AudioVideo){
                presentView = [[LLRTCView alloc] initWithIsVideo:YES isCallee:YES];
            }else{
                presentView = [[LLRTCView alloc] initWithIsVideo:NO isCallee:YES];
            }
            [presentView addChatManagerDelegate:self delegateQueue:nil];
            presentView.nickName = u.nickName;
            presentView.connectText = @"通话时长";
            presentView.netTipText = @"对方的网络状况良好";
            presentView.callin = im;
            NSString *swap = [[NSString alloc] initWithString:senderAgent];
            presentView.callin.senderAgent = im.recvierAgent;
            presentView.callin.recvierAgent = swap;
            [presentView show];
            _presentView = presentView;
        });
    } failure:^(ApxErrorCode *aError) {
    }];
}

//被叫方：呼叫方已经取消呼叫
- (void)didReceiveCancel:(ApproxySDKMessage *)aMessage{
    NSLog(@"对方已经取消..");
    dispatch_async(dispatch_get_main_queue(), ^{
        
        LLMessageModel *model = [LLMessageModel messageModelFromPool:aMessage];
        [self didReceiveMessages: [[NSArray alloc] initWithObjects:aMessage, nil]];
        if(_presentView ){
            [_presentView dismiss];
        }
    });
}

//呼叫方：被叫方已经接受通话
- (void)didReceiveAccept:(ApproxySDKMessage *)aMessage{
    NSLog(@"对方已经接受.. 开始通话..");
    if(_presentView ){
        [_presentView didReceiveAccept:aMessage];
    }
}
//呼叫方：被叫方已经拒绝通话
- (void)didReceiveReject:(ApproxySDKMessage *)aMessage{
    NSLog(@"..挂机..");
    dispatch_async(dispatch_get_main_queue(), ^{
        if(_presentView ){
            [_presentView dismiss];
        }
    });
}

//呼叫方或被叫方：对方点击了通话完成
- (void)didReceiveComplete:(ApproxySDKMessage *)aMessage{
    NSLog(@"通话结束..");
    dispatch_async(dispatch_get_main_queue(), ^{
        LLMessageModel *model = [LLMessageModel messageModelFromPool:aMessage];
        LLConversationModel *conversation = [[LLConversationModelManager sharedManager] conversationModelForConversationId:model.conversationId];
        [conversation.sdk_conversation insertMessage:model.sdk_message];
        
        if(_presentView ){
            [_presentView dismiss];
        }
    });
}

//收到视频帧
- (void) didReceiveVideoFrame:(IMStreamFrame *)frame{
    if(_presentView ){
        [_presentView didReceiveVideoFrame:frame];
    }
}

//收到音频帧
- (void) didReceiveAudioFrame:(IMStreamFrame *)frame{
    if(_presentView ){
        [_presentView didReceiveAudioFrame:frame];
    }
}

//呼叫方：点击开始视频按钮之后的回调
- (void) didHandleCallinClick:(NSDictionary *)aDict{
    LLRTCView *presentView = nil;
    NSString *talkType = aDict[@"talkType"];
    if([talkType isEqualToString:@"videoCall"]){
        presentView = [[LLRTCView alloc] initWithIsVideo:YES isCallee:NO];
    }else{
        presentView = [[LLRTCView alloc] initWithIsVideo:NO isCallee:NO];
    }
    
    NSString *recvierAgent = aDict[@"recvierAgent"];
    NSString *nickName = aDict[@"nickName"];
    NSString *text = @"";
    NSNumber *callTypeNumber = [NSNumber numberWithInt:[talkType isEqualToString:@"videoCall"] ? 3: 1 ];//3音频+视频 1仅音频
    LLMessageModel *model = [[LLChatManager sharedManager]
                             sendCallMessage:text
                             to:recvierAgent
                             messageType:kLLChatTypeChat
                             messageExt:aDict
                             completion:nil];
    [aDict setValue:model.messageId forKey:@"talkId"];
    [aDict setValue:model.from forKey:@"senderAgent"];
    
    [presentView addChatManagerDelegate:self delegateQueue:nil];
    presentView.nickName = nickName?nickName:@"未识别";
    presentView.connectText = @"00:00";
    presentView.netTipText = @"对方的网络状况不是很好";
    ImCallin *im = [[ImCallin alloc]init];
    im.senderAgent = aDict[@"senderAgent"];
    im.recvierAgent = aDict[@"recvierAgent"];
    im.callId = aDict[@"talkId"];
    im.callType = callTypeNumber;
    im.vaBeginTime = [NSDate date];
    presentView.callin = im;
    [presentView show];
    _presentView = presentView;
}

//呼叫方：点击了取消按钮
- (void) didHandleCancelClick:(NSDictionary *)aDict{
    NSString *recvierAgent = aDict[@"recvierAgent"];
    NSString *callId = aDict[@"talkId"];
    NSString *text = [NSString stringWithFormat:@"已取消 "];
    [[LLChatManager sharedManager]
     sendCancelMessage:text
     to:recvierAgent
     messageType:kLLChatTypeChat
     messageExt:aDict
     completion:^(LLMessageModel * _Nonnull model, LLSDKError * _Nonnull error){
     }];
    //重置设备参数
    [[ApproxySDK getInstance] resetDeviceWithIndex:[NSNumber numberWithInt:0] miIndex:[NSNumber numberWithInt:0]];
}

//被叫方：点击接受按钮之后的回调
- (void)didHandleAcceptClick:(NSDictionary *)aDict{
    NSString *senderAgent = aDict[@"senderAgent"];
    NSString *recvierAgent = aDict[@"recvierAgent"];
    NSNumber *callType = aDict[@"callType"];
    
    NSString *myName = [[LLUserProfile myUserProfile] nickName];
    NSString *text = [myName stringByAppendingString:@"通话时长:00:00 "];
    [[LLChatManager sharedManager]
                             sendAcceptMessage:text
                             to:recvierAgent
                             messageType:kLLChatTypeChat
                             messageExt:aDict
     completion:^(LLMessageModel * _Nonnull model, LLSDKError * _Nonnull error){
         
     }];
}

//被叫方：点击挂机之后的按钮回调
- (void)didHandleRejectClick:(NSDictionary *)aDict{
    NSString *talkId = aDict[@"talkId"];
    NSString *recvierAgent = aDict[@"recvierAgent"];
    NSString *isVideo = aDict[@"isVideo"];
    NSString *audioAccept = aDict[@"audioAccept"];
    
    NSString *text = [NSString stringWithFormat:@"已拒绝 "];
    [[LLChatManager sharedManager]
     sendRejectMessage:text
     to:recvierAgent
     messageType:kLLChatTypeChat
     messageExt:aDict
     completion:^(LLMessageModel * _Nonnull model, LLSDKError * _Nonnull error){
         
     }];
    //重置设备参数
    [[ApproxySDK getInstance] resetDeviceWithIndex:[NSNumber numberWithInt:0] miIndex:[NSNumber numberWithInt:0]];
}

//呼叫方或被叫方：点击通话完成
- (void)didHandleCompleteClick:(NSDictionary *)aDict{
    NSString *talkId = aDict[@"talkId"];
    NSString *senderAgent = aDict[@"senderAgent"];
    NSString *recvierAgent = aDict[@"recvierAgent"];
    NSString *isVideo = aDict[@"isVideo"];
    NSString *audioAccept = aDict[@"audioAccept"];
    NSString *talkTime = aDict[@"talkTime"];
    
    NSString *text = [NSString stringWithFormat:@"通话时长 %@ ",talkTime];
    [[LLChatManager sharedManager]
     sendCompleteMessage:text
     to:recvierAgent
     messageType:kLLChatTypeChat
     messageExt:aDict
     completion:^(LLMessageModel * _Nonnull model, LLSDKError * _Nonnull error){
         [LLUtils showTextHUD:@"通话结束..."];
     }];
    //重置设备参数
    [[ApproxySDK getInstance] resetDeviceWithIndex:[NSNumber numberWithInt:0] miIndex:[NSNumber numberWithInt:0]];
}


#pragma mark - 有新消息 接收新消息 -

- (void)didReceiveMessages:(NSArray *)aMessages {
    NSLog(@"收到%ld条新消息", (unsigned long)aMessages.count);
    
    //显示新消息通知
#if !TARGET_IPHONE_SIMULATOR
    NSTimeInterval timeInterval = [[NSDate date] timeIntervalSinceDate:lastPlaySoundDate];
    if (timeInterval > DEFAULT_PLAYSOUND_INTERVAL) {
        lastPlaySoundDate = [NSDate date];
       
        UIApplicationState state = [[UIApplication sharedApplication] applicationState];
        switch (state) {
            case UIApplicationStateActive:
            case UIApplicationStateInactive:
                if ([LLUserProfile myUserProfile].pushOptions.isAlertSoundEnabled) {
                    [LLUtils playNewMessageSound];
                }
                if ([LLUserProfile myUserProfile].pushOptions.isVibrateEnabled) {
                    [LLUtils playVibration];
                }
            
                break;

            case UIApplicationStateBackground:
                [self showNotificationWithMessage:[aMessages lastObject]];
                break;
            default:
                break;
        }
    }

#endif
    WEAK_SELF;
    dispatch_async(_messageQueue, ^() {
        LLConversationModel *curConversationModel = [LLConversationModelManager sharedManager].currentActiveConversationModel;
    
        NSMutableArray<LLMessageModel *> *newMessageModels = [NSMutableArray array];
        [aMessages enumerateObjectsUsingBlock:^(ApproxySDKMessage * _Nonnull message, NSUInteger idx, BOOL * _Nonnull stop) {
            if (message.chatType != ApxChatTypeChat)
                return;
            
            LLMessageModel *model = [LLMessageModel messageModelFromPool:message];
            if (curConversationModel && [message.conversationId isEqualToString:curConversationModel.conversationId]) {
                [curConversationModel.sdk_conversation markMessageAsReadWithId:message.messageId];
                [newMessageModels addObject:model];
                [self preprocessMessageModel:model priority:kLLMessageDownloadPriorityDefault];
            }else {
                [self preprocessMessageModel:model priority:kLLMessageDownloadPriorityLow];
            }

        }];
        
        if (newMessageModels.count > 0) {
            [curConversationModel.allMessageModels addObjectsFromArray:newMessageModels];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                curConversationModel.updateType = kLLMessageListUpdateTypeNewMessage;
                [weakSelf.messageListDelegate loadMoreMessagesDidFinishedWithConversationModel:curConversationModel];
            });
        }
        
        //更新会话列表
        NSArray<LLConversationModel *> *conversationList = [[LLConversationModelManager sharedManager] updateConversationListAfterReceiveNewMessages:aMessages];
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.conversationListDelegate conversationListDidChanged:conversationList];
        });
    
    });
    
}


- (void)loadMoreMessagesForConversationModel:(LLConversationModel *)conversationModel maxCount:(NSInteger)limit isDirectionUp:(BOOL)isDirectionUp {
    BOOL shouldAsyncLoadMessage = conversationModel.referenceMessageModel != nil;
//    || conversationModel.draft.length > 0;

    WEAK_SELF;
    void (^block)() = ^() {
        BOOL hasLoadedEarliestMessage = NO;
        NSArray<LLMessageModel *> *newMessageModels = [[LLMessageModelManager sharedManager] loadMoreMessagesForConversationModel:conversationModel limit:(int)limit isDirectionUp:isDirectionUp hasLoadedEarliestMessage:&hasLoadedEarliestMessage];
        
        NSString *fromId = conversationModel.referenceMessageModel.messageId;
        if (newMessageModels.count > 0) {
            [conversationModel.allMessageModels insertObjects:newMessageModels atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, newMessageModels.count)]];
            fromId = newMessageModels[0].messageId;
        }
        
        //消息已经全部在缓存中
        if (newMessageModels.count == limit || hasLoadedEarliestMessage) {
            conversationModel.updateType = hasLoadedEarliestMessage ? kLLMessageListUpdateTypeLoadMoreComplete : kLLMessageListUpdateTypeLoadMore;
            
            void (^loadCompleteBlock)() = ^() {
                [weakSelf.messageListDelegate loadMoreMessagesDidFinishedWithConversationModel:conversationModel];
            };
            
            if (shouldAsyncLoadMessage) {
                dispatch_async(dispatch_get_main_queue(), loadCompleteBlock);
            }else {
//                loadCompleteBlock();
            }
            
            return;
        }
        
        //从数据库中加载消息
        NSInteger num = limit - newMessageModels.count;
        NSArray *messageList = [conversationModel.sdk_conversation loadMoreMessagesFromId:fromId limit:(int)num direction:MessageSearchDirectionUp];
        
        NSLog(@"从数据库中获取到%ld条消息, fromId: %@", (unsigned long)messageList.count,fromId);
        LLMessageListUpdateType updateType = kLLMessageListUpdateTypeLoadMore;
        //从数据库中全部获取了历史消息
        if (messageList.count < num) {
            NSLog(@"已经加载了全部历史消息");
            //此处2行代码将会导致消息界面变形 具体什么原因未清楚 -- jiangwx 20191201 暂时的解决方案是注释此2行代码 改为在ChatViewControl.m中注释。
            updateType = kLLMessageListUpdateTypeLoadMoreComplete;
            [[LLMessageModelManager sharedManager] markEarliestMessageLoadedForConversation:conversationModel.conversationId];
        }
        
        if (messageList.count > 0){
            NSMutableArray<LLMessageModel *> *newMessageModels = [NSMutableArray arrayWithCapacity:messageList.count];
            [messageList enumerateObjectsUsingBlock:^(ApproxySDKMessage * _Nonnull message, NSUInteger idx, BOOL * _Nonnull stop) {
                BOOL shouldIgnore = NO;
                //FIXME:现在还有必要做这个判断吗？
//                switch (message.body.type) {
//                    case ApxMsgType_Img:{
//                        EMImageMessageBody *imageBody = (EMImageMessageBody *)message.body;
//                        if (imageBody.size.width == 0 || imageBody.size.height == 0){
//                            shouldIgnore = YES;
//                        }
//                        break;
//                    }
//
//                    default:
//                        break;
//                }
                
                if (!shouldIgnore) {
                    LLMessageModel *model = [[LLMessageModel alloc] initWithMessage:message];
                    [newMessageModels addObject:model];
                    
                    [weakSelf preprocessMessageModel:model priority:kLLMessageDownloadPriorityDefault];
                }
            }];
            
            [[LLMessageModelManager sharedManager] addMessageList:newMessageModels toConversation:conversationModel.conversationId isAppend:NO];
            
            [conversationModel.allMessageModels insertObjects:newMessageModels atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, newMessageModels.count)]];
        }
        
        conversationModel.updateType = updateType;

    };
    
    if (shouldAsyncLoadMessage) {
        dispatch_async(_messageQueue, ^() {
            block();
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf.messageListDelegate loadMoreMessagesDidFinishedWithConversationModel:conversationModel];
            });
        });
    }else {
        block();
    }

}


- (void)markAllMessagesAsRead:(LLConversationModel *)conversation {
    [conversation.sdk_conversation markAllMessagesAsRead];

    SAFE_SEND_MESSAGE(self.conversationListDelegate, unreadMessageNumberDidChanged) {
        [self.conversationListDelegate unreadMessageNumberDidChanged];
    }
}

- (LLConversationModel *)getConversationWithConversationChatter:
    (NSString *)conversationChatter conversationType:(LLConversationType)conversationType {
    ApproxySDKConversation *_conversation = [[ApproxySDK getInstance].chatManager getConversation:conversationChatter type:(ApxConversationType)conversationType createIfNotExist:YES];
    LLConversationModel *model = [LLConversationModel conversationModelFromPool:_conversation];
    
    return model;
}

#pragma mark - 消息状态改变

- (void)didMessageStatusChanged:(ApproxySDKMessage *)aMessage
                          error:(ApxErrorCode *)aError {
    NSLog(@"消息状态改变 %d", aMessage.status);
}

//缩略图下载成功后调用该方法，图片、视频附件下载完毕后不调用该方法
//语言消息下载完毕后同样调用该方法
//FIXME: 是否可以认为只要是SDK自动下载的都会回调该方法，用户主动下载的不回调该方法？？
- (void)didMessageAttachmentsStatusChanged:(ApproxySDKMessage *)aMessage
                                     error:(ApxErrorCode *)aError {
    NSLog(@"消息附件状态改变 ");
    if (aMessage.direction == ApxMessageDirectionSend)
        return;
    
    BOOL needPostNotification = NO;
    Im *im = aMessage.body.im;
    if(im.thumbnailDownloadStatus == ApxDownloadStatusSuccessed){
        needPostNotification = YES;
    }
    
    if (!needPostNotification)
        return;

    LLMessageModel *model = [[LLMessageModelManager sharedManager] messageModelForMessage:aMessage];
    if (!model) {
        NSLog(@"FIXME：发生未知错误");
        return;
    }
    if (!aError) {
        switch (model.messageBodyType) {
            case kLLMessageBodyTypeImage:
            case kLLMessageBodyTypeVideo: {
                [model updateMessage:aMessage updateReason:kLLMessageModelUpdateReasonThumbnailDownloadComplete];
                break;
            }
            case kLLMessageBodyTypeVoice:{
                [model updateMessage:aMessage updateReason:kLLMessageModelUpdateReasonAttachmentDownloadComplete];
                break;
            }
                
            default:
                break;
        }
  
    }
    
    LLSDKError *error = aError ? [LLSDKError errorWithErrorCode:aError] : nil;
    model.error = error;
    switch (model.messageBodyType) {
        case kLLMessageBodyTypeImage:
        case kLLMessageBodyTypeVideo: {
            [self postThumbnailDownloadCompleteNotification:model];
            break;
        }
        case kLLMessageBodyTypeVoice: {
            [self postMessageDownloadStatusChangedNotification:model];
            break;
        }
        default:
            break;
    }

}


#pragma mark - Download/Upload Notification

- (void)postMessageUploadStatusChangedNotification:(LLMessageModel *)model {
    [[NSNotificationCenter defaultCenter]
     postNotificationName:LLMessageUploadStatusChangedNotification
     object:self
     userInfo:@{LLChatManagerMessageModelKey:model}];
}

- (void)postMessageDownloadStatusChangedNotification:(LLMessageModel *)model {
    [[NSNotificationCenter defaultCenter]
     postNotificationName:LLMessageDownloadStatusChangedNotification
     object:self
     userInfo:@{LLChatManagerMessageModelKey:model}];
}

- (void)postThumbnailDownloadCompleteNotification:(LLMessageModel *)model {
    [[NSNotificationCenter defaultCenter]
     postNotificationName:LLMessageThumbnailDownloadCompleteNotification
     object:self
     userInfo:@{LLChatManagerMessageModelKey:model}];
}


#pragma mark - 获取缩略图

- (void)asyncDownloadMessageThumbnail:(LLMessageModel *)model
                           completion:(void (^)(LLMessageModel *messageModel, LLSDKError *error))completion {
    if (model.isFetchingThumbnail)
        return;
    
    Im *im = model.sdk_message.body.im;
    im.thumbnailWidth = [NSNumber numberWithFloat:model.thumbnailImageSize.width];
    im.thumbnailHeight = [NSNumber numberWithFloat:model.thumbnailImageSize.height];
    ApxDownloadStatus thumbnailDownloadStatus = im.thumbnailDownloadStatus;;
    if (thumbnailDownloadStatus == ApxDownloadStatusSuccessed ||
        thumbnailDownloadStatus == ApxDownloadStatusDownloading)
        return;

    [model internal_setIsFetchingThumbnail:YES];
    [[ApproxySDK getInstance].chatManager
     asyncDownloadMessageThumbnail:model.sdk_message
                          progress:nil
                        completion:^(ApproxySDKMessage *message, ApxErrorCode *aError) {
        LLSDKError *error = aError ? [LLSDKError errorWithErrorCode:aError] : nil;
        if (!aError) {
            [model updateMessage:message updateReason:kLLMessageModelUpdateReasonThumbnailDownloadComplete];
        }
        
        model.error = error;
        if (completion) {
            completion(model, error);
        }else
            [self postThumbnailDownloadCompleteNotification:model];
        [model internal_setIsFetchingThumbnail:NO];
    }];
    
}

#pragma mark - 异步下载Attachment -

- (void)asynDownloadMessageAttachments:(LLMessageModel *)model
                              progress:(void (^)(LLMessageModel *model, int progress))progress
                            completion:(void (^)(LLMessageModel *messageModel, LLSDKError *error))completion {
    if (model.isFetchingAttachment)
        return;
    
    Im *im = model.sdk_message.body.im;
//    if (![im isKindOfClass:[ImMedia class]]) {
//        return;
//    }
    
    if (im.downloadStatus == ApxDownloadStatusPending ||
      im.downloadStatus == ApxDownloadStatusFailed) {
        [model internal_setIsFetchingAttachment:YES];
        //FIXME:SDK不支持断点下载，所以此处设置为0
        model.fileDownloadProgress = 0;
        //开始下载前，清空原来错误消息
        model.error = nil;
        [model internal_setMessageDownloadStatus:kLLMessageDownloadStatusWaiting];
        
        [self postMessageDownloadStatusChangedNotification:model];
        switch (model.messageBodyType) {
            case kLLMessageBodyTypeVideo:
                [[LLMessageAttachmentDownloader videoDownloader] asynDownloadMessageAttachmentsWithDefaultPriority:model];
                break;
            case kLLMessageBodyTypeImage:
            case kLLMessageBodyTypeVoice:
            case kLLMessageBodyTypeFile:
            case kLLMessageBodyTypeLocation: {
                [[LLMessageAttachmentDownloader imageDownloader] asynDownloadMessageAttachmentsWithDefaultPriority:model];
                break;
            }
            default:
                break;
        }
    }
  
}

#pragma mark - 发送消息

- (void)sendMessage:(LLMessageModel *)messageModel needInsertToDB:(BOOL)needInsertToDB {
    if (needInsertToDB) {
        LLConversationModel *conversation = [[LLConversationModelManager sharedManager] conversationModelForConversationId:messageModel.conversationId];
      [conversation.sdk_conversation insertMessage:messageModel.sdk_message];
    }
 
    [messageModel internal_setMessageStatus:kLLMessageStatusWaiting];
    //FIXME: SDK不支持断点重传，所以这是重置为0
    messageModel.fileUploadProgress = 0;
    messageModel.error = nil;
    [self postMessageUploadStatusChangedNotification:messageModel];
    
    switch (messageModel.messageBodyType) {
        case kLLMessageBodyTypeImage:
            [[LLMessageUploader imageUploader] asynUploadMessage:messageModel];
            break;
        case kLLMessageBodyTypeVideo:
            [[LLMessageUploader videoUploader] asynUploadMessage:messageModel];
            break;
        default:
            [[LLMessageUploader defaultUploader] asynUploadMessage:messageModel];
            break;
    }
    
}

- (void)resendMessage:(LLMessageModel *)messageModel
             progress:(void (^)(LLMessageModel *model, int progress))progress
           completion:(void (^)(LLMessageModel *model, LLSDKError *error))completion {
    [self sendMessage:messageModel needInsertToDB:NO];
}


#pragma mark - 发送文字消息

- (LLMessageModel *)sendTextMessage:(NSString *)text
                            to:(NSString *)toUser
                   messageType:(LLChatType)messageType
                    messageExt:(NSDictionary *)messageExt
                    completion:(void (^)(LLMessageModel *model, LLSDKError *error))completion {
    
    NSString *senderAgent =[[ApproxySDK getInstance] getMySelfUid];
    ImText *im = [[ImText alloc]initWithSenderAgent:senderAgent recvierAgent:toUser];
    im.text = text;
    ApxMessageBody *body = [[ApxMessageBody alloc]initWithIm:im];
    ApproxySDKMessage *message = [[ApproxySDKMessage alloc]initWithConversationID:toUser from:senderAgent to:toUser body:body ext:messageExt];
    message.chatType = (ApxChatType)messageType;
    message.messageId = im.szMsgSrcID;
    
    LLMessageModel *model = [LLMessageModel messageModelFromPool:message];
    [self sendMessage:model needInsertToDB:YES];

    return model;
}

#pragma mark - 发送视频呼叫消息
- (LLMessageModel *)sendCallMessage:(NSString *)text
                                 to:(NSString *)toUser
                        messageType:(LLChatType)messageType
                         messageExt:(NSDictionary *)messageExt
                         completion:(void (^)(LLMessageModel *model, LLSDKError *error))completion {
    
    NSString *senderAgent =[[ApproxySDK getInstance] getMySelfUid];
    ImCallin *im = [[ImCallin alloc]initWithSenderAgent:senderAgent recvierAgent:toUser];
    im.text = text;
    NSNumber *callTypeNumber = [NSNumber numberWithInt:[messageExt[@"talkType"] isEqualToString:@"videoCall"] ? ApxCallVA_AudioVideo: ApxCallVA_OnlyAudio ];//3音频+视频 1仅音频
    im.callType = callTypeNumber;
    
    ApxMessageBody *body = [[ApxMessageBody alloc]initWithIm:im];
    ApproxySDKMessage *message = [[ApproxySDKMessage alloc]initWithConversationID:toUser from:senderAgent to:toUser body:body ext:messageExt];
    message.chatType = (ApxChatType)messageType;
    message.messageId = im.szMsgSrcID;
    
    LLMessageModel *model = [[LLMessageModel alloc] initWithMessage:message];
    [self sendMessage:model needInsertToDB:NO];//发送视频通话的时候不插入记录
    return model;
}

#pragma mark - 发送取消呼叫消息
- (LLMessageModel *)sendCancelMessage:(NSString *)text
                                   to:(NSString *)toUser
                          messageType:(LLChatType)messageType
                           messageExt:(NSDictionary *)messageExt
                           completion:(void (^)(LLMessageModel *model, LLSDKError *error))completion {
    
    NSString *senderAgent =[[ApproxySDK getInstance] getMySelfUid];
    ImCancel *im = [[ImCancel alloc]initWithSenderAgent:senderAgent recvierAgent:toUser];
    im.text = text;
    im.callId = messageExt[@"talkId"];
    ApxMessageBody *body = [[ApxMessageBody alloc]initWithIm:im];
    ApproxySDKMessage *message = [[ApproxySDKMessage alloc]initWithConversationID:toUser from:senderAgent to:toUser body:body ext:messageExt];
    message.chatType = (ApxChatType)messageType;
    message.messageId = im.szMsgSrcID;
    
    LLMessageModel *model = [LLMessageModel messageModelFromPool:message];
    [self sendMessage:model needInsertToDB:YES];
    
    return model;
}
#pragma mark - 发送视频接受消息
- (LLMessageModel *)sendAcceptMessage:(NSString *)text
                                   to:(NSString *)toUser
                          messageType:(LLChatType)messageType
                           messageExt:(NSDictionary *)messageExt
                           completion:(void (^)(LLMessageModel *model, LLSDKError *error))completion {
    
    NSString *senderAgent =[[ApproxySDK getInstance] getMySelfUid];
    ImAccept *im = [[ImAccept alloc]initWithSenderAgent:senderAgent recvierAgent:toUser];
    im.text = text;
    im.callId = messageExt[@"talkId"];
    NSNumber *callTypeNumber = [NSNumber numberWithInt:[messageExt[@"talkType"] isEqualToString:@"videoCall"] ? ApxCallVA_AudioVideo: ApxCallVA_OnlyAudio ];//3音频+视频 1仅音频
    im.callType = callTypeNumber;
    
    ApxMessageBody *body = [[ApxMessageBody alloc]initWithIm:im];
    ApproxySDKMessage *message = [[ApproxySDKMessage alloc]initWithConversationID:toUser from:senderAgent to:toUser body:body ext:messageExt];
    message.chatType = (ApxChatType)messageType;
    message.messageId = im.szMsgSrcID;
    
    LLMessageModel *model = [[LLMessageModel alloc] initWithMessage:message];
    [self sendMessage:model needInsertToDB:NO];
    
    return model;
}

#pragma mark - 发送视频拒绝消息
- (LLMessageModel *)sendRejectMessage:(NSString *)text
                                   to:(NSString *)toUser
                          messageType:(LLChatType)messageType
                           messageExt:(NSDictionary *)messageExt
                           completion:(void (^)(LLMessageModel *model, LLSDKError *error))completion {
    
    NSString *senderAgent =[[ApproxySDK getInstance] getMySelfUid];
    ImReject *im = [[ImReject alloc]initWithSenderAgent:senderAgent recvierAgent:toUser];
    im.text = text;
    ApxMessageBody *body = [[ApxMessageBody alloc]initWithIm:im];
    ApproxySDKMessage *message = [[ApproxySDKMessage alloc]initWithConversationID:toUser from:senderAgent to:toUser body:body ext:messageExt];
    message.chatType = (ApxChatType)messageType;
    message.messageId = im.szMsgSrcID;

    LLMessageModel *model0 = [[LLMessageModel alloc] initWithMessage:message];
    [self sendMessage:model0 needInsertToDB:NO];//先将数据发送出去 然后再保存
    
    im = [[ImReject alloc]initWithSenderAgent:toUser recvierAgent:senderAgent];
    im.text = text;
    body = [[ApxMessageBody alloc]initWithIm:im];
    message = [[ApproxySDKMessage alloc]initWithConversationID:toUser from:toUser to:senderAgent body:body ext:messageExt];
    message.chatType = (ApxChatType)messageType;
    message.messageId = im.szMsgSrcID;
    message.direction = ApxMessageDirectionReceive;
    
    LLMessageModel *model = [LLMessageModel messageModelFromPool:message];
    LLConversationModel *conversation = [[LLConversationModelManager sharedManager] conversationModelForConversationId:model.conversationId];
    [conversation.sdk_conversation insertMessage:model.sdk_message];
    
    return model;
}

#pragma mark - 发送视频通话完成消息
- (LLMessageModel *)sendCompleteMessage:(NSString *)text
                                   to:(NSString *)toUser
                          messageType:(LLChatType)messageType
                           messageExt:(NSDictionary *)messageExt
                           completion:(void (^)(LLMessageModel *model, LLSDKError *error))completion {
    
    NSString *senderAgent =[[ApproxySDK getInstance] getMySelfUid];
    ImComplete *im = [[ImComplete alloc]initWithSenderAgent:senderAgent recvierAgent:toUser];
    im.text = text;
    ApxMessageBody *body = [[ApxMessageBody alloc]initWithIm:im];
    ApproxySDKMessage *message = [[ApproxySDKMessage alloc]initWithConversationID:toUser from:senderAgent to:toUser body:body ext:messageExt];
    message.chatType = (ApxChatType)messageType;
    message.messageId = im.szMsgSrcID;
    
    LLMessageModel *model = [LLMessageModel messageModelFromPool:message];
    [self sendMessage:model needInsertToDB:YES];//通话完成的时候插入记录
    
    return model;
}


#pragma mark - 发送Gif消息

- (LLMessageModel *)sendGIFTextMessage:(NSString *)text
                                 to:(NSString *)toUser
                        messageType:(LLChatType)messageType
                         emotionModel:(LLEmotionModel *)emotionModel
                         completion:(void (^)(LLMessageModel *model, LLSDKError *error))completion {
    
    NSString *senderAgent =[[ApproxySDK getInstance] getMySelfUid];
    ImText *im = [[ImText alloc]initWithSenderAgent:senderAgent recvierAgent:toUser];
    im.text = text;
    ApxMessageBody *body = [[ApxMessageBody alloc]initWithIm:im];
    ApproxySDKMessage *message = [[ApproxySDKMessage alloc]initWithConversationID:toUser from:senderAgent to:toUser body:body ext:nil];
    message.chatType = (ApxChatType)messageType;
    message.messageId = im.szMsgSrcID;
    
    LLMessageModel *model = [LLMessageModel messageModelFromPool:message];
    [self sendMessage:model needInsertToDB:YES];
    
    return model;
}


#pragma mark - 发送图片消息

- (LLMessageModel *)sendImageMessageWithData:(NSData *)imageData
                                   imageSize:(CGSize)imageSize
                                          to:(NSString *)toUser
                                 messageType:(LLChatType)messageType
                                  messageExt:(NSDictionary *)messageExt
                                    progress:(void (^)(LLMessageModel *model, int progress))progress
                                  completion:(void (^)(LLMessageModel *model, LLSDKError *error))completion {
    
    NSString *senderAgent =[[ApproxySDK getInstance] getMySelfUid];
    ImImage *im = [[ImImage alloc]initWithSenderAgent:senderAgent recvierAgent:toUser];
    im.width = [NSNumber numberWithFloat:imageSize.width];
    im.height = [NSNumber numberWithFloat:imageSize.height];

    //保存文件到沙盒 生成沙盒可以访问的localPath
    FilePkg *pkg = [ApproxySDKUtil saveAsFile:imageData fileType:ApxMsgType_Img orgFileName:@"image.png" compress:YES];
    im.mediaID = pkg.localPkgID;
    im.mediaLen = pkg.fileLength;
    im.localMediaPath = pkg.relaFilePath;
    
    ApxMessageBody *body = [[ApxMessageBody alloc]initWithIm:im];
    
    ApproxySDKMessage *message = [[ApproxySDKMessage alloc]initWithConversationID:toUser from:senderAgent to:toUser body:body ext:messageExt];
    message.chatType = (ApxChatType)messageType;
    message.messageId = im.szMsgSrcID;
    
    LLMessageModel *model = [LLMessageModel messageModelFromPool:message];
    
    [self sendMessage:model needInsertToDB:YES];
    
    return model;
}



#pragma mark - 发送地址消息
//- (LLMessageModel *)sendLocationMessageWithLatitude:(double)latitude
//                                     longitude:(double)longitude
//                                       address:(NSString *)address
//                                            to:(NSString *)to
//                                   messageType:(LLChatType)messageType
//                                    messageExt:(NSDictionary *)messageExt
//                                    completion:(void (^)(LLMessageModel *model, LLSDKError *error))completion
//{
//    EMLocationMessageBody *body = [[EMLocationMessageBody alloc] initWithLatitude:latitude longitude:longitude address:address];
//    NSString *from = [[EMClient sharedClient] currentUsername];
//    EMMessage *message = [[EMMessage alloc] initWithConversationID:to from:from to:to body:body ext:messageExt];
//    message.chatType = (EMChatType)messageType;
//    
//    LLMessageModel *model = [[LLMessageModel alloc] initWithMessage:message];
//    
//    [[EMClient sharedClient].chatManager asyncSendMessage:message progress:nil completion:^(EMMessage *aMessage, EMError *aError) {
//            if (completion) {
//                [model updateMessage:aMessage];
//                completion(model, aError ? [LLSDKError errorWithEMError:aError] : nil);
//            }
//    }];
//    
//    return model;
//}


- (LLMessageModel *)sendLocationMessageWithLatitude:(double)latitude
                                          longitude:(double)longitude
                                          zoomLevel:(CGFloat)zoomLevel
                                               name:(NSString *)name
                                            address:(NSString *)address
                                           snapshot:(UIImage *)snapshot
                                                 to:(NSString *)to
                                        messageType:(LLChatType)messageType
                                         completion:(void (^)(LLMessageModel *model, LLSDKError *error))completion
{
//    NSData *data = UIImageJPEGRepresentation(snapshot, 1);
//    EMFileMessageBody *body = [[EMFileMessageBody alloc] initWithData:data displayName:nil];
//    NSString *from = [[EMClient sharedClient] currentUsername];
//    NSDictionary *messageExt = [self encodeLocationMessageExt:latitude longitude:longitude address:address name:name zoomLevel:zoomLevel defaultSnapshot:!snapshot];
//
//    EMMessage *message = [[EMMessage alloc] initWithConversationID:to from:from to:to body:body ext:messageExt];
//    message.chatType = (EMChatType)messageType;
//
//    LLMessageModel *model = [LLMessageModel messageModelFromPool:message];
//    [self sendMessage:model needInsertToDB:YES];
    
    NSData *data = UIImageJPEGRepresentation(snapshot, 1);
    NSString *senderAgent =[[ApproxySDK getInstance] getMySelfUid];
    ImLocation *im = [[ImLocation alloc]initWithSenderAgent:senderAgent recvierAgent:to];
    im.thumbnailWidth = [NSNumber numberWithFloat:snapshot.size.width];
    im.thumbnailHeight = [NSNumber numberWithFloat:snapshot.size.height];
    im.locX = [NSNumber numberWithDouble:latitude];
    im.locY = [NSNumber numberWithDouble:longitude];
    im.label = address;
    
    NSDictionary *messageExt = [self encodeLocationMessageExt:latitude longitude:longitude address:address name:name zoomLevel:zoomLevel defaultSnapshot:!snapshot];
    
    //保存文件到沙盒 生成沙盒可以访问的localPath
    FilePkg *pkg = [ApproxySDKUtil saveAsFile:data fileType:ApxMsgType_Img orgFileName:@"image.png" compress:YES];
    im.mediaID = pkg.localPkgID;
    im.mediaLen = pkg.fileLength;
    im.localMediaPath = pkg.relaFilePath;
    
    ApxMessageBody *body = [[ApxMessageBody alloc]initWithIm:im];
    
    ApproxySDKMessage *message = [[ApproxySDKMessage alloc]initWithConversationID:to from:senderAgent to:to body:body ext:messageExt];
    message.chatType = (ApxChatType)messageType;
    message.messageId = im.szMsgSrcID;
    
    LLMessageModel *model = [LLMessageModel messageModelFromPool:message];
    
    [self sendMessage:model needInsertToDB:YES];
    
    return model;
}

- (LLMessageModel *)createLocationMessageWithLatitude:(double)latitude
                                            longitude:(double)longitude
                                            zoomLevel:(CGFloat)zoomLevel
                                                 name:(NSString *)name
                                              address:(NSString *)address
                                             snapshot:(UIImage *)snapshot
                                                   to:(NSString *)to
                                          messageType:(LLChatType)messageType
{
    
    CGSize size;
    NSData *data;
    if (snapshot) {
        data = UIImageJPEGRepresentation(snapshot, 1);
        size = snapshot.size;
    }
    
//    EMFileMessageBody *body = [[EMFileMessageBody alloc] initWithData:data displayName:nil];
//    NSString *from = [[EMClient sharedClient] currentUsername];
//    NSDictionary *messageExt = [self encodeLocationMessageExt:latitude longitude:longitude address:address name:name zoomLevel:zoomLevel defaultSnapshot:NO];
//
//    EMMessage *message = [[EMMessage alloc] initWithConversationID:to from:from to:to body:body ext:messageExt];
//    message.chatType = (EMChatType)messageType;
//
//    LLMessageModel *model = [LLMessageModel messageModelFromPool:message];
    
    NSString *senderAgent =[[ApproxySDK getInstance] getMySelfUid];
    ImLocation *im = [[ImLocation alloc]initWithSenderAgent:senderAgent recvierAgent:to];
    im.thumbnailWidth = [NSNumber numberWithFloat:size.width];
    im.thumbnailHeight = [NSNumber numberWithFloat:size.height];
    im.locX = [NSNumber numberWithDouble:latitude];
    im.locY = [NSNumber numberWithDouble:longitude];
    im.label = address;
    im.zoomLevel = [NSNumber numberWithFloat:zoomLevel];
    
    NSDictionary *messageExt = [self encodeLocationMessageExt:latitude longitude:longitude address:address name:name zoomLevel:zoomLevel defaultSnapshot:!snapshot];
    ApxMessageBody *body = [[ApxMessageBody alloc]initWithIm:im];
    
    ApproxySDKMessage *message = [[ApproxySDKMessage alloc]initWithConversationID:to from:senderAgent to:to body:body ext:messageExt];
    message.chatType = (ApxChatType)messageType;
    message.messageId = im.szMsgSrcID;
    
    LLMessageModel *model = [LLMessageModel messageModelFromPool:message];
    return model;
}


- (void)updateAndSendLocationForMessageModel:(LLMessageModel *)messageModel
                                    withSnapshot:(UIImage *)snapshot {
    NSData *data = UIImageJPEGRepresentation(snapshot, 1);
    
    if (snapshot) {
        NSMutableDictionary *messageExt = [messageModel.sdk_message.ext mutableCopy];
        messageExt[@"defaultSnapshot"] = @(NO);
        messageModel.defaultSnapshot = NO;
        messageModel.sdk_message.ext = messageExt;
    }else {
        messageModel.defaultSnapshot = YES;
    }
    
    ImLocation *im = (ImLocation *)messageModel.sdk_message.body.im;
    FilePkg *pkg = [ApproxySDKUtil saveAsFile:data fileType:ApxMsgType_Loc orgFileName:@"snapshot.png" compress:YES];
    im.mediaID = pkg.localPkgID;
    im.mediaLen = pkg.fileLength;
    im.localMediaPath = pkg.relaFilePath;
   
    BOOL result = [[ApproxySDK getInstance].chatManager updateMessage:messageModel.sdk_message];

    NSLog(@"更新LocationMessage缩略图 %@", result? @"成功": @"失败");

    [self sendMessage:messageModel needInsertToDB:NO];
}


- (void)asynReGeocodeMessageModel:(LLMessageModel *)model
                       completion:(void (^)(LLMessageModel *messageModel, LLSDKError *error))completion {
    [[LLLocationManager sharedManager] reGeocodeFromCoordinate:model.coordinate2D
            completeCallback:^(AMapReGeocode *reGeoCode, CLLocationCoordinate2D coordinate2D) {
              if (!reGeoCode) {
                  if (completion) {
                      dispatch_async(dispatch_get_main_queue(), ^{
                          model.address = LOCATION_EMPTY_ADDRESS;
                          model.locationName = LOCATION_EMPTY_NAME;
                          model.error = [LLSDKError errorWithDescription:@"逆地理失败" code:LLSDKErrorGeneral];
                          [model setNeedsUpdateForReuse];
                          completion(model, model.error);
                      });
                  }
                  return;
              }
              
              NSString *address;
              NSString *name;
              [[LLLocationManager sharedManager] getLocationNameAndAddressFromReGeocode:reGeoCode name:&name address:&address];
              
              NSMutableDictionary *dict = [model.sdk_message.ext mutableCopy];
              dict[@"name"] = name;
              dict[@"address"] = address;
              model.sdk_message.ext = dict;
              BOOL result = [[ApproxySDK getInstance].chatManager updateMessage:model.sdk_message];
              NSLog(@"更新LocationMessage %@", result? @"成功": @"失败");
              
              [model updateMessage:model.sdk_message updateReason:kLLMessageModelUpdateReasonReGeocodeComplete];
              if (completion) {
                  dispatch_async(dispatch_get_main_queue(), ^{
                      model.error = nil;
                      [model setNeedsUpdateForReuse];
                      completion(model, model.error);
                  });
              }
          }];

}


#pragma mark - 发送语音消息

- (LLMessageModel *)sendVoiceMessageWithLocalPath:(NSString *)localPath
                                    duration:(NSInteger)duration
                                          to:(NSString *)to
                                 messageType:(LLChatType)messageType
                                  messageExt:(NSDictionary *)messageExt
                                  completion:(void (^)(LLMessageModel *model, LLSDKError *error))completion
{
    NSString *senderAgent =[[ApproxySDK getInstance] getMySelfUid];
    ImVoice *im = [[ImVoice alloc]initWithSenderAgent:senderAgent recvierAgent:to];
    im.taketime = [NSNumber numberWithInteger:duration];
    
    NSLog(@"语音文件：%@",localPath);
    //保存文件到沙盒 生成沙盒可以访问的localPath
    NSString *orgFileName = [localPath lastPathComponent];
    FilePkg *pkg = [ApproxySDKUtil saveAsFile:[NSData dataWithContentsOfFile:localPath] fileType:ApxMsgType_Audio orgFileName:orgFileName compress:YES];
    im.mediaID = pkg.localPkgID;
    im.mediaLen = pkg.fileLength;
    im.localMediaPath = pkg.relaFilePath;
    im.downloadStatus = kLLMessageDownloadStatusSuccessed;
    im.thumbnailDownloadStatus = kLLMessageDownloadStatusSuccessed;
    
    ApxMessageBody *body = [[ApxMessageBody alloc]initWithIm:im];
    
    ApproxySDKMessage *message = [[ApproxySDKMessage alloc]initWithConversationID:to from:senderAgent to:to body:body ext:messageExt];
    message.chatType = (ApxChatType)messageType;
    message.messageId = im.szMsgSrcID;
    LLMessageModel *model = [LLMessageModel messageModelFromPool:message];
    
    [self sendMessage:model needInsertToDB:YES];
    return model;
}


- (void)changeVoiceMessageModelPlayStatus:(LLMessageModel *)model {
    if (model.messageBodyType != kLLMessageBodyTypeVoice)
        return;
    model.isMediaPlaying = !model.isMediaPlaying;
    if (!model.isMediaPlayed) {
        model.isMediaPlayed = YES;
        ApproxySDKMessage *chatMessage = model.sdk_message;
        NSMutableDictionary *dict;
        if (chatMessage.ext)
            dict = [chatMessage.ext mutableCopy];
        else
            dict = [NSMutableDictionary dictionary];
        
        dict[@"isPlayed"] = @(YES);
        chatMessage.ext = dict;
        [[ApproxySDK getInstance].chatManager updateMessage:chatMessage];
        
    }
    
}

#pragma mark - 发送视频消息

- (LLMessageModel *)sendVideoMessageWithLocalPath:(NSString *)localPath
                                               to:(NSString *)to
                                      messageType:(LLChatType)messageType
                                       messageExt:(NSDictionary *)messageExt
                                         progress:(void (^)(LLMessageModel *model, int progress))progress
                                       completion:(void (^)(LLMessageModel *model, LLSDKError *error))completion
{
    
    NSLog(@"视频文件：%@",localPath);
    
    NSString *senderAgent =[[ApproxySDK getInstance] getMySelfUid];
    ImVideo *im = [[ImVideo alloc]initWithSenderAgent:senderAgent recvierAgent:to];
    CGSize thumbailSize = [LLUtils getVideoSize:localPath];
    im.thumbnailWidth = [NSNumber numberWithDouble:thumbailSize.width];
    im.thumbnailHeight = [NSNumber numberWithDouble:thumbailSize.height];
    im.taketime = [NSNumber numberWithDouble:round([LLUtils getVideoLength:localPath])];//获取视频时长
    
    NSString *orgFileName = [localPath lastPathComponent];
    //保存文件到沙盒 生成沙盒可以访问的localPath
    FilePkg *pkg = [ApproxySDKUtil saveAsFile:[NSData dataWithContentsOfFile:localPath] fileType:ApxMsgType_Video orgFileName:orgFileName compress:YES];
    im.mediaID = pkg.localPkgID;
    im.mediaLen = pkg.fileLength;
    im.localMediaPath = pkg.relaFilePath;
    
    ApxMessageBody *body = [[ApxMessageBody alloc]initWithIm:im];
    
    ApproxySDKMessage *message = [[ApproxySDKMessage alloc]initWithConversationID:to from:senderAgent to:to body:body ext:messageExt];
    message.chatType = (ApxChatType)messageType;
    message.messageId = im.szMsgSrcID;
    
    LLMessageModel *model = [LLMessageModel messageModelFromPool:message];
    
    [self sendMessage:model needInsertToDB:YES];
    return model;
}


- (void)updateMessageModelWithTimestamp:(LLMessageModel *)messageModel timestamp:(CFTimeInterval)timestamp {
    if (!messageModel)
        return;
    
    //INFO: 环信SDK时间戳单位是毫秒，所以此处乘以1000
    messageModel.sdk_message.timestamp = timestamp;
    messageModel.timestamp = timestamp;
    BOOL result = [[ApproxySDK getInstance].chatManager updateMessage:messageModel.sdk_message];
    NSLog(@"更新Message时间戳 %@", result? @"成功": @"失败");
    
}


#pragma mark - 删除消息 -

- (BOOL)deleteMessage:(LLMessageModel *)model fromConversation:(LLConversationModel *)conversationModel {
    BOOL result = [conversationModel.sdk_conversation deleteMessageWithId:model.messageId];
    if (result) {
        [[LLMessageCacheManager sharedManager] deleteMessageModel:model];
    }
    return result;
}

//INFO: 环信SDK没有提供批量删除消息的接口，所以需要一条一条删
- (NSMutableArray<LLMessageModel *> *)deleteMessages:(NSArray<LLMessageModel *> *)models fromConversation:(LLConversationModel *)conversationModel {
    NSMutableArray<LLMessageModel *> *deleteModels = [NSMutableArray array];
    for (LLMessageModel *model in models) {
        BOOL result = [conversationModel.sdk_conversation deleteMessageWithId:model.messageId];
        if (result) {
            [deleteModels addObject:model];
        }
    }
    
    if (deleteModels.count > 0) {
        [[LLMessageCacheManager sharedManager] deleteMessageModelsInArray:deleteModels];
    }
    
    return deleteModels;
}


#pragma mark - 消息通知 -

- (void)showNotificationWithMessage:(ApproxySDKMessage *)message
{
    LLPushOptions *options = [LLUserProfile myUserProfile].pushOptions;
    //发送本地推送
    UILocalNotification *notification = [[UILocalNotification alloc] init];
    notification.fireDate = [NSDate date]; //触发通知的时间

    if (options.displayStyle == kLLPushDisplayStyleMessageSummary) {
        ApxMessageBody *messageBody = message.body;
        NSString *messageStr = nil;
        switch (messageBody.type) {
            case ApxMsgType_Text:
            {
                if (!message.ext)
                    messageStr = messageBody.im.text;
                else {
                    messageStr = @"发来一个表情";
                }
            }
                break;
            case ApxMsgType_Img:
            {
                messageStr = @"发来一张图片";
            }
                break;
            case ApxMsgType_Loc:
            {
                messageStr = @"分享了一个地理位置";
            }
                break;
            case ApxMsgType_Audio:
            {
                messageStr = @"发来一段语音";
            }
                break;
            case ApxMsgType_Video:{
                messageStr = @"发来一段视频";
            }
                break;
            default:
                break;
        }
    
        if (messageBody.type == ApxMsgType_Text) {
            notification.alertBody = [NSString stringWithFormat:@"%@:%@", message.from, messageStr];
        }else {
            notification.alertBody = [NSString stringWithFormat:@"%@%@", message.from, messageStr];
        }
        
    }else {
        notification.alertBody = @"您有一条新消息";
    }
    
//去掉注释会显示[本地]开头, 方便在开发中区分是否为本地推送
    //notification.alertBody = [[NSString alloc] initWithFormat:@"[本地]%@", notification.alertBody];
    
    notification.timeZone = [NSTimeZone defaultTimeZone];
    
    if (options.isVibrateEnabled) {
        [LLUtils playVibration];
    }
    if (options.isAlertSoundEnabled) {
        notification.soundName = UILocalNotificationDefaultSoundName;
    }
    notification.alertTitle = message.from;
    
    //发送通知
    [[UIApplication sharedApplication] scheduleLocalNotification:notification];
}


#pragma mark - 消息查找 -

- (NSArray<NSArray<LLMessageSearchResultModel *> *> *)searchChatHistoryWithKeyword:(NSString *)keyword {
    NSArray<ApproxySDKConversation *> *allConversations = [[ApproxySDK getInstance].chatManager getAllConversations];
    NSMutableArray<NSArray *> *result = [NSMutableArray array];
    
    for (ApproxySDKConversation *conversation in allConversations) {
        NSArray<ApproxySDKMessage *> *messageList = [conversation loadMoreMessagesContain:keyword before:-1 limit:-1 from:nil direction:MessageSearchDirectionUp];

        if (messageList.count > 0) {
            NSMutableArray<LLMessageSearchResultModel *> *messageModels = [NSMutableArray arrayWithCapacity:messageList.count];
 
            [messageList enumerateObjectsUsingBlock:^(ApproxySDKMessage * _Nonnull message, NSUInteger idx, BOOL * _Nonnull stop) {
                LLMessageSearchResultModel *model = [[LLMessageSearchResultModel alloc] initWithMessage:message];
                [messageModels addObject:model];
            }];
            
            [result addObject:messageModels];
        }
    }
    
    return result;
}


#pragma mark - 其他



@end
