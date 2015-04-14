//
//  TestWebSocket.m
//  SimpleTest
//
//  Created by Adam Kaplan on 4/13/15.
//  Copyright (c) 2015 Vluxe. All rights reserved.
//

#import "TestWebSocket.h"

@implementation TestWebSocket

+ (instancetype)testSocketForCommand:(NSString *)command {
    return [self testSocketForCommand:command parameters:nil];
}

+ (instancetype)testSocketForCommand:(NSString *)command parameters:(NSString *)params {
    NSURL *baseUrl = [[NSURL URLWithString:@"ws://localhost:9001"] URLByAppendingPathComponent:command];
    
    if (params) {
        baseUrl = [NSURL URLWithString:[[baseUrl absoluteString] stringByAppendingString:params]];
    }
    
    TestWebSocket *socket = [[self alloc] initWithURL:baseUrl protocols:@[]];
    return socket;
}

@end
