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
static const uint8_t JFRSVMask             = 0x70;
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

typedef NS_ENUM(NSUInteger, JFCloseCode) {
    JFCloseCodeNormal                 = 1000,
    JFCloseCodeGoingAway              = 1001,
    JFCloseCodeProtocolError          = 1002,
    JFCloseCodeProtocolUnhandledType  = 1003,
    // 1004 reserved.
    JFCloseCodeNoStatusReceived       = 1005,
    //1006 reserved.
    JFCloseCodeEncoding               = 1007,
    JFCloseCodePolicyViolated         = 1008,
    JFCloseCodeMessageTooBig          = 1009
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
@property(nonatomic, assign)NSInteger frameCount;
@property(nonatomic, assign)BOOL isFinReady;
@property(nonatomic, strong)NSMutableData *fragBuffer;

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
    [self writeError:JFCloseCodeNormal];
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
            [self disconnectStream:[aStream streamError]];
            break;
        }
        case NSStreamEventEndEncountered:
        {
            //NSLog(@"end event");
            [self disconnectStream:nil];
            break;
        }
        default:
            break;
    }
}
/////////////////////////////////////////////////////////////////////////////
-(void)disconnectStream:(NSError*)error
{
    //NSLog(@"disconnect stream");
    [self.inputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.outputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.outputStream close];
    [self.inputStream close];
    self.outputStream = nil;
    self.inputStream = nil;
    self.isRunLoop = NO;
    self.isConnected = NO;

    if([self.delegate respondsToSelector:@selector(websocketDidDisconnect:error:)]) {
        dispatch_async(dispatch_get_main_queue(),^{
            [self.delegate websocketDidDisconnect:self error:error];
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
-(uint16_t)parseWebSocketMessage:(uint8_t*)buffer length:(NSInteger)bufferLen
{
    //NSData *testData = [NSData dataWithBytes:buffer length:bufferLen];
    //NSLog(@"data: %s",(char*)testData.bytes);
    if(!self.bufferData) {
        self.bufferData = [NSMutableData new];
        self.fragBuffer = [NSMutableData new];
    }
    BOOL isFin = NO;
    if(self.expectedLength > 0){
        if(bufferLen > 0) {
            [self.bufferData appendBytes:buffer length:bufferLen];
        }
    } else {
        NSInteger offset = 0;
        isFin = (JFFinMask & buffer[0]);
        NSLog(@"isFin: %@",isFin ? @"YES": @"NO");
        //BOOL isRsv = (JFRSVMask & buffer[0]);
        uint8_t receivedOpcode = (JFOpCodeMask & buffer[0]);
        //NSLog(@"opcode: 0x%x",receivedOpcode);
        BOOL isMasked = (JFMaskMask & buffer[1]);
        uint8_t payloadLen = (JFPayloadLenMask & buffer[1]);
        if(isMasked || (JFRSVMask & buffer[0])) {
            NSLog(@"masked and rsv data is not currently supported");
            [self writeError:JFCloseCodeProtocolError];
            return -1;
        }
        if(isFin && !self.isFinReady) {
            self.isFinReady = YES;
        }
        if(receivedOpcode == JFOpCodePong) {
            //the server is still up.
            NSLog(@"pong so do nothing...");
            NSInteger len = bufferLen-2-payloadLen;
            if(len > 0 && payloadLen > 0) {
                [self processWebSocketMessage:(buffer+2+payloadLen) length:len];
                //need to check response payload here as well.
            }
            return -1;
        } else if(receivedOpcode != JFOpCodeContinueFrame && receivedOpcode != JFOpCodePing && receivedOpcode != JFOpCodeTextFrame &&
                  receivedOpcode != JFOpCodeBinaryFrame && receivedOpcode != JFOpCodeConnectionClose) {
            NSLog(@"unknown opcode: 0x%x",receivedOpcode);
            [self writeError:JFCloseCodeProtocolError];
            return -1;
        }
        
        NSInteger dataLength = bufferLen;
        offset = 2; //how many bytes do we need to skip for the header
        dataLength = payloadLen;
        BOOL isControl = (receivedOpcode == JFOpCodePing || receivedOpcode == JFOpCodePong || receivedOpcode == JFOpCodeConnectionClose);
        if(isControl && (dataLength > 125 || !isFin)) {
            [self writeError:JFCloseCodeProtocolError];
            return -1;
        }
        if (!isControl && receivedOpcode != 0 && self.frameCount > 0) {
            NSLog(@"error is control");
            [self writeError:JFCloseCodeProtocolError];
            return -1;
        }
        
        if (receivedOpcode == 0 && self.frameCount == 0) {
            buffer[bufferLen] = '\0';
            NSLog(@"error on opcode!!");
            [self writeError:JFCloseCodeProtocolError];
            return -1;
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
        else if(receivedOpcode == JFOpCodeConnectionClose) {
            //the server disconnected us
            uint16_t code = JFCloseCodeNormal;
            if(bufferLen-offset > 0) {
                code = CFSwapInt16BigToHost(*(uint16_t *)(buffer+offset) );
                if(code < 1000 || (code > 1003 && code < 1007) || (code > 1011 && code < 3000)) {
                    code = JFCloseCodeProtocolError;
                }
            }
            //check response payload here...
            NSLog(@"closing with code: %d",code);
            //[self writeError:code];
            return code;
        }
        
        if(receivedOpcode == 0) {
            //does nothing
        }
        else if(receivedOpcode == JFOpCodeTextFrame) {
            self.isBinary = NO;
        } else if(receivedOpcode == JFOpCodeBinaryFrame) {
            self.isBinary = YES;
        }
        if(dataLength > 0 && bufferLen-offset > 0) {
            [self.bufferData appendBytes:(buffer+offset) length:bufferLen-offset];
        }
        if(isFin || (dataLength < bufferLen) || receivedOpcode != 0) {
            self.currentCode = receivedOpcode;
            self.expectedLength = dataLength;
        }
    }
    self.frameCount++;
    return 0;
}
/////////////////////////////////////////////////////////////////////////////
//Process Websocket Message...
- (void)processWebSocketMessage:(uint8_t*)buffer length:(NSInteger)bufferLen
{
    uint16_t closeCode = [self parseWebSocketMessage:buffer length:bufferLen];
    if(closeCode < 0) {
        return;
    }
    if(self.bufferData.length >= self.expectedLength) {
        NSData *subData = self.bufferData;
        if(self.expectedLength > 0) {
            subData = [self.bufferData subdataWithRange:NSMakeRange(0, self.expectedLength)];
        }
        BOOL doClose = YES;
        if(!self.isFinReady) {
            NSLog(@"append data: %s",[subData bytes]);
            [self.fragBuffer appendData:subData];
        } else {
            self.isFinReady = NO;
            if(self.currentCode == JFOpCodePing) {
                NSLog(@"pong: %s",[subData bytes]);
                [self dequeueWrite:[subData copy] withCode:JFOpCodePong];
            } else {
                [self.fragBuffer appendData:subData];
                subData = self.fragBuffer;
                NSLog(@"finshed data: %s",[subData bytes]);
                if(self.isBinary) {
                    if([self.delegate respondsToSelector:@selector(websocket:didReceiveData:)]) {
                        doClose = NO;
                        subData = [subData copy];
                        dispatch_async(dispatch_get_main_queue(),^{
                            [self.delegate websocket:self didReceiveData:subData];
                            if([self processCloseCode:closeCode]) {
                                return;
                            }
                        });
                    }
                } else {
                    NSString *str = [[NSString alloc] initWithData:subData encoding:NSUTF8StringEncoding];
                    NSLog(@"str: %@",str);
                    if(!str) {
                        [self writeError:JFCloseCodeEncoding];
                        return;
                    }
                    if([self.delegate respondsToSelector:@selector(websocket:didReceiveMessage:)]) {
                        doClose = NO;
                        dispatch_async(dispatch_get_main_queue(),^{
                            [self.delegate websocket:self didReceiveMessage:str];
                            if([self processCloseCode:closeCode]) {
                                return;
                            }
                        });
                    }
                }
                [self.fragBuffer setLength:0];
                self.frameCount = 0;
            }
        }
        if(doClose && [self processCloseCode:closeCode]) {
            return;
        }
        NSData *nextData = nil;
        if(self.expectedLength < self.bufferData.length) {
            nextData = [self.bufferData subdataWithRange:NSMakeRange(self.expectedLength,self.bufferData.length-self.expectedLength)];
        }
        
        self.expectedLength = 0;
        [self.bufferData setLength:0]; //clear the buffer
        if(nextData) {
            [self processWebSocketMessage:(uint8_t*)[nextData bytes] length:[nextData length]];
        }
    }
    
}
/////////////////////////////////////////////////////////////////////////////
-(BOOL)processCloseCode:(uint16_t)code
{
    if(code > 0) {
        [self writeError:code];
        return YES;
    }
    return NO;
}
/////////////////////////////////////////////////////////////////////////////
-(void)dequeueWrite:(NSData*)data withCode:(JFOpCode)code
{
    NSLog(@"write a code: %d",code);
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
-(void)dealloc
{
    if(self.isConnected)
        [self disconnect];
}
/////////////////////////////////////////////////////////////////////////////
@end
