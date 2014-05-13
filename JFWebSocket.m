/////////////////////////////////////////////////////////////////////////////
//
//  JFWebSocket.m
//  WebSocketTester
//
//  Created by Austin Cherry on 5/13/14.
//  Copyright (c) 2014 Vluxe. All rights reserved.
//
/////////////////////////////////////////////////////////////////////////////

#import <CommonCrypto/CommonDigest.h>
#import "JFWebSocket.h"

@interface JFWebSocket ()<NSStreamDelegate>

@property(nonatomic, strong)NSURL *url;
@property(nonatomic, strong)NSInputStream *inputStream;
@property(nonatomic, strong)NSOutputStream *outputStream;

@end

//Constant Header Values.
static const NSString *headerWSUpgradeName     = @"Upgrade";
static const NSString *headerWSUpgradeValue    = @"websocket";
static const NSString *headerWSConnectionName  = @"Connection";
static const NSString *headerWSConnectionValue = @"Upgrade";
static const NSString *headerWSProtocolName    = @"Sec-WebSocket-Protocol";
static const NSString *headerWSProtocolValue   = @"chat, superchat";
static const NSString *headerWSVersionName     = @"Sec-Websocket-Version";
static const NSString *headerWSVersionValue    = @"13";
static const NSString *headerWSKeyName         = @"Sec-WebSocket-Key";
static const NSString *headerOriginName        = @"Origin";

@implementation JFWebSocket

/////////////////////////////////////////////////////////////////////////////
- (instancetype)initWithURL:(NSURL *)url
{
    if(self = [super init]) {
        self.url = url;
    }
    
    return self;
}
/////////////////////////////////////////////////////////////////////////////
- (void)connect
{
    CFURLRef url = CFURLCreateWithString(kCFAllocatorDefault, (CFStringRef)self.url.absoluteString, NULL);
    CFStringRef requestMethod = CFSTR("GET");
    CFHTTPMessageRef urlRequest = CFHTTPMessageCreateRequest(kCFAllocatorDefault,
                                                             requestMethod,
                                                             url,
                                                             kCFHTTPVersion1_1);
    CFHTTPMessageSetHeaderFieldValue(urlRequest,
                                     (__bridge CFStringRef)headerWSUpgradeName,
                                     (__bridge CFStringRef)headerWSUpgradeValue);
    CFHTTPMessageSetHeaderFieldValue(urlRequest,
                                     (__bridge CFStringRef)headerWSConnectionName,
                                     (__bridge CFStringRef)headerWSConnectionValue);
    CFHTTPMessageSetHeaderFieldValue(urlRequest,
                                     (__bridge CFStringRef)headerWSProtocolName,
                                     (__bridge CFStringRef)headerWSProtocolValue);
    CFHTTPMessageSetHeaderFieldValue(urlRequest,
                                     (__bridge CFStringRef)headerWSVersionName,
                                     (__bridge CFStringRef)headerWSVersionValue);
    CFHTTPMessageSetHeaderFieldValue(urlRequest,
                                     (__bridge CFStringRef)headerWSKeyName,
                                     (__bridge CFStringRef)[self generateWebSocketKey]);
    CFHTTPMessageSetHeaderFieldValue(urlRequest,
                                     (__bridge CFStringRef)headerWSKeyName,
                                     (__bridge CFStringRef)[self generateWebSocketKey]);
    CFHTTPMessageSetHeaderFieldValue(urlRequest,
                                     (__bridge CFStringRef)headerOriginName,
                                     (__bridge CFStringRef)self.url.absoluteString);
    CFReadStreamRef readStream = CFReadStreamCreateForHTTPRequest(kCFAllocatorDefault, urlRequest);
    self.inputStream = (__bridge_transfer NSInputStream *)readStream;
    self.inputStream.delegate = self;
    //self.outputStream = [[NSOutputStream alloc] init];
    //self.outputStream.delegate = self;
    [self.inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    //[self.outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.inputStream open];
    while (true)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
    //[self.outputStream open];
    
}
/////////////////////////////////////////////////////////////////////////////
- (NSString *)generateWebSocketKey
{
    NSInteger seed = 20;
    NSMutableString *string = [NSMutableString stringWithCapacity:seed];
    for (int i = 0; i < seed; i++) {
        [string appendFormat:@"%C", (unichar)('a' + arc4random_uniform(25))];
    }
    
    unsigned char result[CC_SHA1_DIGEST_LENGTH];
    const char *cString = [string UTF8String];
    CC_SHA1(cString, (unsigned int)strlen(cString), result);
    NSData *hashData = [[NSData alloc] initWithBytes:result length: sizeof result];
    return [hashData base64EncodedStringWithOptions:0];
}
/////////////////////////////////////////////////////////////////////////////

#pragma mark - NSStreamDelegate

/////////////////////////////////////////////////////////////////////////////
- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{
    NSLog(@"stream is: %lu error: %@", [aStream streamStatus], [aStream streamError]);
    
    switch (eventCode) {
        case NSStreamEventNone:
            NSLog(@"no event!");
            break;
        case NSStreamEventOpenCompleted:
            NSLog(@"open event");
            break;
        case NSStreamEventHasBytesAvailable:
        {
            NSInputStream *iStream = (NSInputStream *)aStream;
            uint8_t buffer[2048];
            NSInteger length = [iStream read:buffer maxLength:2048];
            NSString *str = [[NSString alloc] initWithData:[NSData dataWithBytes:buffer length:length] encoding:NSUTF8StringEncoding];
            NSLog(@"bytes: %@", str);
            break;
        }
        case NSStreamEventHasSpaceAvailable:
            NSLog(@"space available");
            break;
        case NSStreamEventErrorOccurred:
            NSLog(@"error occurred");
            break;
        case NSStreamEventEndEncountered:
            NSLog(@"end event");
            break;
        default:
            break;
    }
}
/////////////////////////////////////////////////////////////////////////////
@end
