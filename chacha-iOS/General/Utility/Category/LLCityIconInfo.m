//
//  LLCityIconInfo.m
//  chacha-iOS
//
//  Created by jiangwx on 2020/1/9.
//  Copyright © 2020年 GYJZH. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "LLCityIconInfo.h"
@implementation LLCityIconInfo

- (instancetype)initWithText:(NSString *)text size:(NSInteger)size color:(UIColor *)color {
    if (self = [super init]) {
        self.text = text;
        self.size = size;
        self.color = color;
    }
    return self;
}
+ (instancetype)iconInfoWithText:(NSString *)text size:(NSInteger)size color:(UIColor *)color {
    return [[LLCityIconInfo alloc] initWithText:text size:size color:color];
}
@end
