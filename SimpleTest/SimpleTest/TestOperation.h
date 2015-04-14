//
//  TestOperation.h
//  SimpleTest
//
//  Created by Adam Kaplan on 4/14/15.
//  Copyright (c) 2015 Vluxe. All rights reserved.
//

#import <Foundation/Foundation.h>

@class TestCase, TestWebSocket;

@interface TestOperation : NSOperation

@property (nonatomic) TestWebSocket *socket;

@property (nonatomic) TestCase *testCase;

- (instancetype)initWithTestCase:(TestCase *)testCase command:(NSString *)command;

@end
