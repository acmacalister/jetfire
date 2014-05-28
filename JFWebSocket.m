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

//this get the correct bits out by masking the bytes of the buffer.
static const uint8_t JFFinMask             = 0x80;
static const uint8_t JFOpCodeMask          = 0x0F;
//static const uint8_t JFRSVMask             = 0x70;
static const uint8_t JFMaskMask            = 0x80;
static const uint8_t JFPayloadLenMask      = 0x7F;
static const size_t  JFMaxFrameSize        = 32;

//get the opCode from the packet
typedef NS_ENUM(NSUInteger, JFOpCode) {
    JFOpCodeContinueFrame = 0x0,
    JFOpCodeTextFrame = 0x1,
    JFOpCodeBinaryFrame = 0x2,
    //3-7 are reserved.
    JFOpCodeConnectionClose = 0x8,
    JFOpCodePing = 0x9,
    JFOpCodePong = 0xA,
    //B-F reserved.
};

typedef NS_ENUM(NSUInteger, JFErrorCode) {
    JFErrorCodeNormal  = 1000,
    JFErrorCodeProtocol = 1002
};

@interface JFWebSocket ()<NSStreamDelegate>

@property(nonatomic, strong)NSURL *url;
@property(nonatomic, strong)NSInputStream *inputStream;
@property(nonatomic, strong)NSOutputStream *outputStream;
@property(nonatomic, assign)BOOL isConnected;
@property(nonatomic, assign)BOOL isBinary;
@property(nonatomic, strong)NSMutableData *bufferData;
@property(nonatomic, strong)NSOperationQueue *writeQueue;
@property(nonatomic, assign)BOOL isRunLoop;
@property(nonatomic, assign)NSInteger expectedLength;
@property(nonatomic, assign)JFOpCode currentCode;

@end

//Constant Header Values.
static const NSString *headerWSUpgradeName     = @"Upgrade";
static const NSString *headerWSUpgradeValue    = @"websocket";
static const NSString *headerWSHostName        = @"Host";
static const NSString *headerWSConnectionName  = @"Connection";
static const NSString *headerWSConnectionValue = @"Upgrade";
static const NSString *headerWSProtocolName    = @"Sec-WebSocket-Protocol";
static const NSString *headerWSProtocolValue   = @"chat, superchat";
static const NSString *headerWSVersionName     = @"Sec-Websocket-Version";
static const NSString *headerWSVersionValue    = @"13";
static const NSString *headerWSKeyName         = @"Sec-WebSocket-Key";
static const NSString *headerOriginName        = @"Origin";
static const NSString *headerWSAcceptName      = @"Sec-WebSocket-Accept";

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
    //everything is on a background thread.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self createHTTPRequest];
    });
}
/////////////////////////////////////////////////////////////////////////////
- (void)disconnect
{
    [self writeError:JFErrorCodeNormal];
}
/////////////////////////////////////////////////////////////////////////////
-(void)writeString:(NSString*)string
{
    if(string) {
        [self dequeueWrite:[string dataUsingEncoding:NSUTF8StringEncoding]
                  withCode:JFOpCodeTextFrame];
    }
}
/////////////////////////////////////////////////////////////////////////////
-(void)writeData:(NSData*)data
{
    [self dequeueWrite:data withCode:JFOpCodeBinaryFrame];
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
    CFHTTPMessageSetHeaderFieldValue(urlRequest,
                                     (__bridge CFStringRef)headerWSHostName,
                                     (__bridge CFStringRef)[NSString stringWithFormat:@"%@:%@",self.url.host,self.url.port]);
    
    NSData *serializedRequest = (__bridge NSData *)(CFHTTPMessageCopySerializedMessage(urlRequest));
    [self initStreamsWithData:serializedRequest];
}
/////////////////////////////////////////////////////////////////////////////
//Random String of 16 lowercase chars, SHA1 and base64 encoded.
- (NSString *)generateWebSocketKey
{
    NSInteger seed = 16;
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
    self.isRunLoop = YES;
    while (self.isRunLoop)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
}
/////////////////////////////////////////////////////////////////////////////

#pragma mark - NSStreamDelegate

/////////////////////////////////////////////////////////////////////////////
- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{
    switch (eventCode) {
        case NSStreamEventNone:
            //NSLog(@"no event!");
            break;
        case NSStreamEventOpenCompleted:
            //NSLog(@"open event");
            break;
        case NSStreamEventHasBytesAvailable:
        {
            if(aStream == self.inputStream)
                [self processInputStream];
            break;
        }
        case NSStreamEventHasSpaceAvailable:
        {
            //NSLog(@"space available");
            break;
        }
        case NSStreamEventErrorOccurred:
        {
            NSLog(@"error occurred: %@ %@", aStream, [aStream streamError]);
            [self disconnectStream];
            break;
        }
        case NSStreamEventEndEncountered:
        {
            NSLog(@"end event");
            [self disconnectStream];
            break;
        }
        default:
            break;
    }
}
/////////////////////////////////////////////////////////////////////////////
-(void)disconnectStream
{
    NSLog(@"disconnect stream");
    [self.inputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.outputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.outputStream close];
    [self.inputStream close];
    self.outputStream = nil;
    self.inputStream = nil;
    self.isRunLoop = NO;
    self.isConnected = NO;

    if([self.delegate respondsToSelector:@selector(websocketDidDisconnect:)]) {
        dispatch_async(dispatch_get_main_queue(),^{
            [self.delegate websocketDidDisconnect:self];
        });
    }
}
/////////////////////////////////////////////////////////////////////////////

#pragma mark - Stream Processing Methods

/////////////////////////////////////////////////////////////////////////////
- (void)processInputStream
{
    uint8_t buffer[BUFFER_MAX];
    NSInteger length = [self.inputStream read:buffer maxLength:BUFFER_MAX];
    if(length > 0) {
        if(!self.isConnected) {
            self.isConnected = [self processHTTP:buffer length:length];
            if(!self.isConnected) {
                NSLog(@"tell delegate to disconnect or error or whatever.");
            }
        } else {
            [self processWebSocketMessage:buffer length:length];
        }
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
            if([self.delegate respondsToSelector:@selector(websocketDidConnect:)]) {
                dispatch_async(dispatch_get_main_queue(),^{
                    [self.delegate websocketDidConnect:self];
                });
            }
            totalSize += 1; //skip the last \n
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
-(void)writeError:(uint16_t)code
{
    uint16_t buffer[1];
    buffer[0] = CFSwapInt16BigToHost(code);
    [self dequeueWrite:[NSData dataWithBytes:buffer length:sizeof(uint16_t)] withCode:JFOpCodeConnectionClose];
}
/////////////////////////////////////////////////////////////////////////////
//Process Websocket Message...
- (void)processWebSocketMessage:(uint8_t*)buffer length:(NSInteger)bufferLen
{
    if(!self.bufferData)
        self.bufferData = [NSMutableData new];
    BOOL isFin = NO;
    if(self.expectedLength > 0){
        if(bufferLen > 0) {
            [self.bufferData appendBytes:buffer length:bufferLen];
        }
    } else {
        NSInteger offset = 0;
        isFin = (JFFinMask & buffer[0]);
        //BOOL isRsv = (JFRSVMask & buffer[0]);
        uint8_t receivedOpcode = (JFOpCodeMask & buffer[0]);
        NSLog(@"opcode: 0x%x",receivedOpcode);
        JFOpCode code = receivedOpcode;
        BOOL isMasked = (JFMaskMask & buffer[1]);
        uint8_t payloadLen = (JFPayloadLenMask & buffer[1]);
        if(isMasked) {
            NSLog(@"masked and rsv data is not currently supported");
            return;
        }
        if(code == JFOpCodePong) {
            //the server is still up.
            //Not sure if we should have a delegate or something.
            NSLog(@"pong so do nothing...");
            return;
        } else if(code == JFOpCodeConnectionClose) {
            //the server disconnected us
            [self disconnect];
            return;
        }
        NSInteger dataLength = bufferLen;
        offset = 2; //how many bytes do we need to skip for the header
        dataLength = payloadLen;
        BOOL isControl = (code == JFOpCodePing || code == JFOpCodePong || code == JFOpCodeConnectionClose);
        if(isControl && (dataLength > 125 || !isFin)) {
            [self writeError:JFErrorCodeProtocol];
            return;
        }
        if(payloadLen == 127) {
            dataLength = CFSwapInt64BigToHost(*(uint64_t *)(buffer+offset));
            //NSLog(@"biggest dataLength: %d",dataLength);
            offset += sizeof(uint64_t);
        } else if(payloadLen == 126) {
            dataLength = CFSwapInt16BigToHost(*(uint16_t *)(buffer+offset) );
            //NSLog(@"bigger dataLength: %d",dataLength);
            offset += sizeof(uint16_t);
        }
        if(receivedOpcode == JFOpCodeTextFrame) {
            self.isBinary = NO;
        } else {
            self.isBinary = YES;
        }
        if(dataLength > 0 && bufferLen-offset > 0) {
            [self.bufferData appendBytes:(buffer+offset) length:bufferLen-offset];
        }
        if(isFin) {
            self.currentCode = code;
            self.expectedLength = dataLength;
        }
    }
    if(self.bufferData.length >= self.expectedLength) {
        if(self.currentCode == JFOpCodePing) {
            NSData *responseData = [self.bufferData copy];
            NSLog(@"ping ring!");
            [self dequeueWrite:responseData withCode:JFOpCodePong];
        } else if(self.isBinary) {
            if([self.delegate respondsToSelector:@selector(websocket:didReceiveData:)]) {
                NSData *responseData = [self.bufferData copy];
                dispatch_async(dispatch_get_main_queue(),^{
                    [self.delegate websocket:self didReceiveData:responseData];
                });
            }
        } else {
            NSString *str = [[NSString alloc] initWithData:self.bufferData encoding:NSUTF8StringEncoding];
            if([self.delegate respondsToSelector:@selector(websocket:didReceiveMessage:)]) {
                dispatch_async(dispatch_get_main_queue(),^{
                    [self.delegate websocket:self didReceiveMessage:str];
                });
            }
        }
        self.expectedLength = 0;
        [self.bufferData setLength:0]; //clear the buffer
    }
}
/////////////////////////////////////////////////////////////////////////////
-(void)dequeueWrite:(NSData*)data withCode:(JFOpCode)code
{
    if(!self.writeQueue) {
        self.writeQueue = [[NSOperationQueue alloc] init];
        self.writeQueue.maxConcurrentOperationCount = 1;
    }
    //we have a queue so we can be thread safe.
    [self.writeQueue addOperationWithBlock:^{
        NSInteger offset = 2; //how many bytes do we need to skip for the header
        uint8_t *bytes = (uint8_t*)[data bytes];
        NSInteger dataLength = data.length;
        NSMutableData *frame = [[NSMutableData alloc] initWithLength:dataLength + JFMaxFrameSize];
        uint8_t *buffer = (uint8_t*)[frame mutableBytes];
        buffer[0] = JFFinMask | code;
        if(dataLength < 126) {
            buffer[1] |= dataLength;
        } else if(dataLength <= UINT16_MAX) {
            buffer[1] |= 126;
            *((uint16_t *)(buffer + offset)) = CFSwapInt16BigToHost((uint16_t)dataLength);
            offset += sizeof(uint16_t);
        } else {
            buffer[1] |= 127;
            *((uint64_t *)(buffer + offset)) = CFSwapInt64BigToHost((uint64_t)dataLength);
            offset += sizeof(uint64_t);
        }
        BOOL isMask = YES;
        if(isMask) {
            buffer[1] |= JFMaskMask;
            uint8_t *mask_key = (buffer + offset);
            SecRandomCopyBytes(kSecRandomDefault, sizeof(uint32_t), (uint8_t *)mask_key);
            offset += sizeof(uint32_t);

            for (size_t i = 0; i < dataLength; i++) {
                buffer[offset] = bytes[i] ^ mask_key[i % sizeof(uint32_t)];
                offset += 1;
            }
        } else {
            for(size_t i = 0; i < dataLength; i++) {
                buffer[offset] = bytes[i];
                offset += 1;
            }
        }
        [self.outputStream write:[frame bytes] maxLength:offset];
    }];
}
/////////////////////////////////////////////////////////////////////////////
@end
