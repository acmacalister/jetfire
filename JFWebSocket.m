/////////////////////////////////////////////////////////////////////////////
//
//  JFWebSocket.m
//  WebSocketTester
//
//  Created by Austin Cherry on 5/13/14.
//  Copyright (c) 2014 Vluxe. All rights reserved.
//
/////////////////////////////////////////////////////////////////////////////

#import "JFWebSocket.h"

@interface JFWebSocket ()<NSStreamDelegate>

@property(nonatomic, strong)NSURL *url;
@property(nonatomic, strong)NSInputStream *inputStream;
@property(nonatomic, strong)NSOutputStream *outputStream;
@property(nonatomic, assign)BOOL isConnected;

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
static const NSString *headerWSAcceptName      = @"Sec-WebSocket-Accept";

//Websocket Packet Structure
typedef struct {
    BOOL fin;
    BOOL rsv1;
    BOOL rsv2;
    BOOL rsv3;
    uint8_t opcode;
    BOOL masked;
    uint64_t payload_length;
} WebSocketPacket;

//Class Constants
static char CRLFBytes[] = {'\r', '\n', '\r', '\n'};
static int BUFFER_MAX = 2048;

@implementation JFWebSocket

/////////////////////////////////////////////////////////////////////////////
//Default initializer
- (instancetype)initWithURL:(NSURL *)url
{
    if(self = [super init]) {
        self.url = url;
    }
    
    return self;
}
/////////////////////////////////////////////////////////////////////////////
//Exposed method for connecting to URL provided in init method.
- (void)connect
{
    [self createHTTPRequest];
}
/////////////////////////////////////////////////////////////////////////////

#pragma mark - connect's internal supporting methods

/////////////////////////////////////////////////////////////////////////////
//Uses CoreFoundation to build a HTTP request to send over TCP stream.
- (void)createHTTPRequest
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
    
    NSData *serializedRequest = (__bridge NSData *)(CFHTTPMessageCopySerializedMessage(urlRequest));
    [self initStreamsWithData:serializedRequest];
}
/////////////////////////////////////////////////////////////////////////////
//Random String of 20 lowercase chars, SHA1 and base64 encoded.
- (NSString *)generateWebSocketKey
{
    NSInteger seed = 20;
    NSMutableString *string = [NSMutableString stringWithCapacity:seed];
    for (int i = 0; i < seed; i++) {
        [string appendFormat:@"%C", (unichar)('a' + arc4random_uniform(25))];
    }
    return [[string dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
}
/////////////////////////////////////////////////////////////////////////////
//Sets up our reader/writer for the TCP stream.
- (void)initStreamsWithData:(NSData *)data
{
    CFReadStreamRef readStream = NULL;
    CFWriteStreamRef writeStream = NULL;
    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)self.url.host, [self.url.port intValue], &readStream, &writeStream);
    
    self.inputStream = (__bridge_transfer NSInputStream *)readStream;
    self.inputStream.delegate = self;
    self.outputStream = (__bridge_transfer NSOutputStream *)writeStream;
    self.outputStream.delegate = self;
    [self.inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.inputStream open];
    [self.outputStream open];
    [self.outputStream write:[data bytes] maxLength:[data length]];
    while (true)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
}
/////////////////////////////////////////////////////////////////////////////

#pragma mark - NSStreamDelegate

/////////////////////////////////////////////////////////////////////////////
- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{
    switch (eventCode) {
        case NSStreamEventNone:
            NSLog(@"no event!");
            break;
        case NSStreamEventOpenCompleted:
            NSLog(@"open event");
            break;
        case NSStreamEventHasBytesAvailable:
        {
            if(aStream == self.inputStream)
                [self processInputStream];
            break;
        }
        case NSStreamEventHasSpaceAvailable:
            NSLog(@"space available");
            break;
        case NSStreamEventErrorOccurred:
            NSLog(@"error occurred: %@", [aStream streamError]);
            break;
        case NSStreamEventEndEncountered:
            NSLog(@"end event");
            break;
        default:
            break;
    }
}
/////////////////////////////////////////////////////////////////////////////

#pragma mark - Stream Processing Methods

/////////////////////////////////////////////////////////////////////////////
- (void)processInputStream
{
    uint8_t buffer[BUFFER_MAX];
    NSInteger length = [self.inputStream read:buffer maxLength:BUFFER_MAX];
    if(!self.isConnected) {
        self.isConnected = [self processHTTP:buffer length:length];
        if(!self.isConnected) {
            NSLog(@"tell delegate to disconnect or error or whatever.");
        }
    } else {
        [self processWebSocketMessage:buffer length:length];
    }
}
/////////////////////////////////////////////////////////////////////////////
//Finds the HTTP Packet in the TCP stream, by looking for the CRLF.
- (BOOL)processHTTP:(uint8_t*)buffer length:(NSInteger)bufferLen
{
    int k = 0;
    NSInteger totalSize = 0;
    for(int i = 0; i < bufferLen; i++) {
        if(buffer[i] == CRLFBytes[k]) {
            k++;
            if(k == 3) {
                totalSize = i + 1;
                break;
            }
        } else {
            k = 0;
        }
    }
    if(totalSize > 0) {
        
        if([self validateResponse:buffer length:totalSize])
        {
            NSInteger  restSize = bufferLen-totalSize;
            if(restSize > 0) {
                [self processWebSocketMessage:(buffer+totalSize) length:restSize];
            }
            return YES;
        }
    }
    return NO;
}
/////////////////////////////////////////////////////////////////////////////
//Validate the HTTP is a 101, as per the RFC spec.
- (BOOL)validateResponse:(uint8_t *)buffer length:(NSInteger)bufferLen
{
    CFHTTPMessageRef response = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, NO);
    CFHTTPMessageAppendBytes(response, buffer, bufferLen);
    if(CFHTTPMessageGetResponseStatusCode(response) != 101)
        return NO;
    NSDictionary *headers = (__bridge NSDictionary *)(CFHTTPMessageCopyAllHeaderFields(response));
    NSString *acceptKey = headers[headerWSAcceptName];
    
    if(acceptKey.length > 0)
        return YES;
    return NO;
}
/////////////////////////////////////////////////////////////////////////////
//Process Websocket Message...
- (void)processWebSocketMessage:(uint8_t*)buffer length:(NSInteger)bufferLen
{
    WebSocketPacket *packet = (WebSocketPacket *)buffer;
    buffer[sizeof(packet)] = '\0';
    NSLog(@"we got a message: %s", buffer);
}
/////////////////////////////////////////////////////////////////////////////
@end
