//
//  TestWebSocket.h
//  SimpleTest
//
//  Created by Adam Kaplan on 4/13/15.
//  Copyright (c) 2015 Vluxe. All rights reserved.
//

#import "JFRWebSocket.h"

@interface TestWebSocket : JFRWebSocket

@property NSString *receivedText;
@property NSData *receivedData;
@property NSError *lastError;
@property BOOL receivedPing;

+ (instancetype)testSocketForCommand:(NSString *)command;

+ (instancetype)testSocketForCommand:(NSString *)command parameters:(NSString *)params;

@end
