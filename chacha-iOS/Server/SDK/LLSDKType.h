//
//  LLSDKType.h
//  LLWeChat
//
//  Created by GYJZH on 8/4/16.
//  Copyright © 2016 GYJZH. All rights reserved.
//

#ifndef LLSDKType_h
#define LLSDKType_h

#import "EMMessage.h"
#import "EMMessageBody.h"
#import "EMConversation.h"
#import "EMFileMessageBody.h"
#import "ApproxySDKOptions.h"

static NSString *LLConnectionStateDidChangedNotification = @"LLConnectionStateDidChangedNotification";

typedef NS_ENUM(NSInteger, LLConnectionState) {
    kLLConnectionStateConnected = 0,
    kLLConnectionStateDisconnected,
};

typedef NS_ENUM(NSInteger, LLMessageBodyType) {
    kLLMessageBodyTypeText = ApxMsgType_Text,
    kLLMessageBodyTypeImage = ApxMsgType_Img,
    kLLMessageBodyTypeVideo = ApxMsgType_Video,
    kLLMessageBodyTypeVoice = ApxMsgType_Audio,
    kLLMessageBodyTypeLocation = ApxMsgType_Loc,
    kLLMessageBodyTypeFile = ApxMsgType_File,
    kLLMessageBodyTypeDateTime,
    kLLMessageBodyTypeGif,
    kLLMessageBodyTypeRecording, //表示正在录音的Cell
    
};

typedef NS_ENUM(NSInteger, LLMessageDownloadStatus) {
    kLLMessageDownloadStatusDownloading = ApxDownloadStatusDownloading,
    kLLMessageDownloadStatusSuccessed = ApxDownloadStatusSuccessed,
    kLLMessageDownloadStatusFailed = ApxDownloadStatusFailed,
    kLLMessageDownloadStatusPending = ApxDownloadStatusPending,
    kLLMessageDownloadStatusWaiting = 10086,
    kLLMessageDownloadStatusNone = 10088
};

typedef NS_ENUM(NSInteger, LLMessageStatus) {
    kLLMessageStatusPending  = ApxMessageStatusPending,
    kLLMessageStatusDelivering = ApxMessageStatusDelivering,
    kLLMessageStatusSuccessed = ApxMessageStatusSuccessed,
    kLLMessageStatusFailed = ApxMessageStatusFailed,
    kLLMessageStatusWaiting = 10086,
    kLLMessageStatusNone = 10088
};

typedef NS_ENUM(NSInteger, LLChatType) {
    kLLChatTypeChat   = ApxChatTypeChat,   /*! \~chinese 单聊消息 \~english Chat */
    kLLChatTypeGroupChat = ApxChatTypeGroupChat,
    kLLChatTypeChatRoom = ApxChatTypeChatRoom
};

typedef NS_ENUM(NSInteger, LLConversationType) {
    kLLConversationTypeChat = ApxConversationTypeChat,
    kLLConversationTypeGroupChat = ApxConversationTypeGroupChat,
    kLLConversationTypeChatRoom = ApxConversationTypeChatRoom
};

typedef NS_ENUM(NSInteger, LLMessageDirection) {
    kLLMessageDirectionSend = ApxMessageDirectionSend,
    kLLMessageDirectionReceive = ApxMessageDirectionReceive
};

static inline LLChatType chatTypeForConversationType(LLConversationType conversationType) {
    switch (conversationType) {
        case kLLConversationTypeChat:
            return kLLChatTypeChat;
        case kLLConversationTypeChatRoom:
            return kLLChatTypeChatRoom;
        case kLLConversationTypeGroupChat:
            return kLLChatTypeGroupChat;
    }
}


#endif /* LLSDKType_h */
