//
//  TestOperation.m
//  SimpleTest
//
//  Created by Adam Kaplan on 4/14/15.
//  Copyright (c) 2015 Vluxe. All rights reserved.
//

#import "TestOperation.h"
#import "JFRWebSocket.h"
#import "TestWebSocket.h"
#import "TestCase.h"

static NSString *testAgent;

@interface TestOperation () <JFRWebSocketDelegate>
@property (nonatomic) BOOL isExecuting;
@property (nonatomic) BOOL isFinished;
@end

@implementation TestOperation

+ (void)initialize {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        testAgent = [NSBundle bundleForClass:[self class]].bundleIdentifier;
    });
}

- (instancetype)initWithTestCase:(TestCase *)testCase command:(NSString *)command {
    if (self = [super init]) {
        _testCase = testCase;
        NSString *params = [NSString stringWithFormat:@"?case=%lu&agent=%@&", testCase.number, testAgent];
        _socket = [TestWebSocket testSocketForCommand:command parameters:params];
        _socket.delegate = self;
    }
    return self;
}

- (BOOL)isConcurrent {
    return YES;
}

- (void)main {
    self.isExecuting = YES;
    self.testCase.status = TestCaseStatusRunning;
    [self.socket connect];
}

- (void)setExecuting:(BOOL)executing finished:(BOOL)finished {
    [self willChangeValueForKey:@"isExecuting"];
    [self willChangeValueForKey:@"isFinished"];
    
    self.isExecuting = executing;
    self.isFinished = finished;
    
    [self didChangeValueForKey:@"isFinished"];
    [self didChangeValueForKey:@"isExecuting"];
}

- (void)dealloc {
    self.socket.delegate = nil;
}

#pragma mark -

- (void)websocketDidConnect:(JFRWebSocket*)socket {
    NSLog(@"[connected]");
}

- (void)websocketDidDisconnect:(JFRWebSocket *)socket error:(NSError *)error {
    NSLog(@"[disconnected: %@]", [error localizedDescription]);
    self.socket.lastError = error;
    //@throw error;
    [self done];
}

- (void)websocket:(JFRWebSocket *)socket didReceiveMessage:(NSString *)string {
    self.socket.receivedText = string;
    [self.socket writeString:string];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(done) object:nil];
    [self performSelector:@selector(done) withObject:nil afterDelay:1.0];
}

- (void)websocket:(JFRWebSocket *)socket didReceiveData:(NSData *)data {
    self.socket.receivedData = data;
    [self.socket writeData:data];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(done) object:nil];
    [self performSelector:@selector(done) withObject:nil afterDelay:1.0];
}

- (void)websocketDidReceivePing:(JFRWebSocket *)socket {
    self.socket.receivedPing = YES;
    NSLog(@"* Ping!");
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(done) object:nil];
    [self performSelector:@selector(done) withObject:nil afterDelay:1.0]; // allow time for queued pong to be sent
}

- (void)done {
    [self setExecuting:NO finished:YES];
}


@end
