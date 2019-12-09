//
//  LLChatCallView.m
//  chacha-iOS
//
//  Created by jiangwx on 2019/12/9.
//  Copyright © 2019年 GYJZH. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "LLChatCallView.h"

@interface LLChatCallView ()
- (IBAction)accept:(UIButton *)sender;
- (IBAction)reject:(UIButton *)sender;

@end

@implementation LLChatCallView

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect {
    // Drawing code
}
*/
- (IBAction)accept:(UIButton *)sender {
    NSLog(@"接受了呼叫的请求");
}

- (IBAction)reject:(UIButton *)sender {
    NSLog(@"拒绝了呼叫的请求");
}
@end
