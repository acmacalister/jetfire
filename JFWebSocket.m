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

//holds the responses in our read stack to properly process messages
@interface JFResponse : NSObject

@property(nonatomic, assign)BOOL isFin;
@property(nonatomic, assign)JFOpCode code;
@property(nonatomic, assign)NSInteger bytesLeft;
@property(nonatomic, assign)NSInteger frameCount;
@property(nonatomic, strong)NSMutableData *buffer;

@end

@interface JFWebSocket ()<NSStreamDelegate>

@property(nonatomic, strong)NSURL *url;
@property(nonatomic, strong)NSInputStream *inputStream;
@property(nonatomic, strong)NSOutputStream *outputStream;
@property(nonatomic, assign)BOOL isConnected;
@property(nonatomic, strong)NSOperationQueue *writeQueue;
@property(nonatomic, assign)BOOL isRunLoop;
@property(nonatomic, strong)NSMutableArray *readStack;
@property(nonatomic, strong)NSMutableArray *inputQueue;
@property(nonatomic, strong)NSData *fragBuffer;

//you all go away!!!
@property(nonatomic, assign)BOOL isBinary;
@property(nonatomic, strong)NSMutableData *bufferData;
@property(nonatomic, assign)NSInteger expectedLength;
@property(nonatomic, assign)JFOpCode currentCode;
@property(nonatomic, assign)NSInteger frameCount;
@property(nonatomic, assign)BOOL isFinReady;

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
        self.readStack = [NSMutableArray new];
        self.inputQueue = [NSMutableArray new];
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
    NSLog(@"disconnect stream: %@",[error localizedDescription]);
    [self.writeQueue waitUntilAllOperationsAreFinished];
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
    @autoreleasepool {
        //NSLog(@"start read");
        uint8_t buffer[BUFFER_MAX];
        NSInteger length = [self.inputStream read:buffer maxLength:BUFFER_MAX];
        //NSLog(@"read length: %d",length);
        if(length > 0) {
            if(!self.isConnected) {
                self.isConnected = [self processHTTP:buffer length:length];
                if(!self.isConnected) {
                    NSLog(@"tell delegate to disconnect or error or whatever.");
                }
            } else {
                //[self processRawMessage:buffer length:length];
                BOOL process = NO;
                if(self.inputQueue.count == 0) {
                    process = YES;
                }
                [self.inputQueue addObject:[NSData dataWithBytes:buffer length:length]];
                if(process) {
                    [self dequeueInput];
                }
            }
        }
    }
}
/////////////////////////////////////////////////////////////////////////////
-(void)dequeueInput
{
    //NSLog(@"queue count: %d",self.inputQueue.count);
    if(self.inputQueue.count > 0) {
        NSData *data = [self.inputQueue objectAtIndex:0];
        NSData *work = data;
        if(self.fragBuffer) {
            NSMutableData *combine = [NSMutableData dataWithData:self.fragBuffer];
            [combine appendData:data];
            work = combine;
            self.fragBuffer = nil;
            //NSLog(@"combined!");
        }
        //NSLog(@"data len: %d",work.length);
        //NSLog(@"check: [%s]",(char*)work.bytes);
        //totalSize += work.length;
        //NSLog(@"totalSize: %d",totalSize);
        [self processRawMessage:(uint8_t*)work.bytes length:work.length];
        [self.inputQueue removeObject:data];
        [self dequeueInput];
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
                [self processRawMessage:(buffer+totalSize) length:restSize];
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
-(void)processRawMessage:(uint8_t*)buffer length:(NSInteger)bufferLen
{
    //NSLog(@"process a message: %s",buffer);
    //NSLog(@"buffer len: %d",bufferLen);
    JFResponse *response = [self.readStack lastObject];
    if(response && bufferLen < 2) {
        NSLog(@"not long enough");
        self.fragBuffer = [NSData dataWithBytes:buffer length:bufferLen];
        return;
    }
    if(response.bytesLeft > 0) {
        //NSLog(@"response bytesLeft: %d",response.bytesLeft);
        NSInteger len = response.bytesLeft;
        NSInteger extra =  bufferLen - response.bytesLeft;
        if(response.bytesLeft > bufferLen) {
            len = bufferLen;
            extra = 0;
        }
        response.bytesLeft -= len;
        [response.buffer appendData:[NSData dataWithBytes:buffer length:len]];
        //NSLog(@"keep taking bytes: %d",response.bytesLeft);
        [self processResponse:response];
        //NSLog(@"extra: %d",extra);
        NSInteger offset = bufferLen - extra;
        if(extra > 0) {
            //NSLog(@"extra data");
            [self processExtra:(buffer+offset) length:extra];
        }
    } else {
        BOOL isFin = (JFFinMask & buffer[0]);
        //NSLog(@"isFin: %@",isFin ? @"YES": @"NO");
        uint8_t receivedOpcode = (JFOpCodeMask & buffer[0]);
        //NSLog(@"opcode: 0x%x",receivedOpcode);
        BOOL isMasked = (JFMaskMask & buffer[1]);
        uint8_t payloadLen = (JFPayloadLenMask & buffer[1]);
        NSInteger offset = 2; //how many bytes do we need to skip for the header
        if((isMasked  || (JFRSVMask & buffer[0])) && receivedOpcode != JFOpCodePong) {
            NSLog(@"masked and rsv data is not currently supported");
            [self writeError:JFCloseCodeProtocolError];
            return;
        }
        BOOL isControlFrame = (receivedOpcode == JFOpCodeConnectionClose || receivedOpcode == JFOpCodePing); //|| receivedOpcode == JFOpCodePong
        if(!isControlFrame && (receivedOpcode != JFOpCodeBinaryFrame && receivedOpcode != JFOpCodeContinueFrame && receivedOpcode != JFOpCodeTextFrame && receivedOpcode != JFOpCodePong)) {
            NSLog(@"unknown opcode: 0x%x",receivedOpcode);
            [self writeError:JFCloseCodeProtocolError];
            return;
        }
        if(isControlFrame && !isFin) {
            NSLog(@"control frames can't be fragmented");
            [self writeError:JFCloseCodeProtocolError];
            return;
        }
        if(receivedOpcode == JFOpCodeConnectionClose) {
            //the server disconnected us
            uint16_t code = JFCloseCodeNormal;
            if(payloadLen == 1) {
                code = JFCloseCodeProtocolError;
            }
            else if(payloadLen > 1) {
                code = CFSwapInt16BigToHost(*(uint16_t *)(buffer+offset) );
                if(code < 1000 || (code > 1003 && code < 1007) || (code > 1011 && code < 3000)) {
                    code = JFCloseCodeProtocolError;
                }
                offset += 2;
            }
            NSInteger len = payloadLen-2;
            if(len > 0) {
                NSData *data = [NSData dataWithBytes:(buffer+offset) length:len];
                NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if(!str) {
                    code = JFCloseCodeProtocolError;
                }
            }
            NSLog(@"closing with code: %d",code);
            [self writeError:code];
            return;
            //return code;
        }
        if(isControlFrame && payloadLen > 125) {
            [self writeError:JFCloseCodeProtocolError];
            return;
        }
        NSInteger dataLength = payloadLen;
        if(payloadLen == 127) {
            dataLength = CFSwapInt64BigToHost(*(uint64_t *)(buffer+offset));
            //NSLog(@"biggest dataLength: %d",dataLength);
            offset += sizeof(uint64_t);
        } else if(payloadLen == 126) {
            dataLength = CFSwapInt16BigToHost(*(uint16_t *)(buffer+offset) );
            //NSLog(@"bigger dataLength: %d",dataLength);
            offset += sizeof(uint16_t);
        }
        NSInteger len = dataLength;
        if(dataLength > bufferLen)
            len = bufferLen-offset;
        //NSLog(@"response.data.length: %d",response.buffer.length);
        //NSLog(@"payload len: %d",payloadLen);
        //NSLog(@"datalength: %d",dataLength);
        //NSLog(@"bufferLen: %d",bufferLen);
        //NSLog(@"len is: %d",len);
        NSData *data = nil;
        if(len < 0) {
            len = 0;
            data = [NSData data];
        } else {
            data = [NSData dataWithBytes:(buffer+offset) length:len];
        }
        if(receivedOpcode == JFOpCodePong) {
            NSInteger step = (offset+payloadLen);
            NSInteger extra = bufferLen-step;
            if(extra > 0) {
                NSLog(@"pong more");
                [self processRawMessage:(buffer+step) length:extra];
            }
            return;
        }
        JFResponse *response = [self.readStack lastObject];
        if(isControlFrame) {
            response = nil; //don't append pings
        }
        if(!isFin && receivedOpcode == JFOpCodeContinueFrame && !response) {
            NSLog(@"nothing to continue");
            [self writeError:JFCloseCodeProtocolError];
            return;
        }
        BOOL isNew = NO;
        if(!response) {
            if(receivedOpcode == JFOpCodeContinueFrame) {
                NSLog(@"first frame can't be a continue frame");
                [self writeError:JFCloseCodeProtocolError];
                return;
            }
            isNew = YES;
            response = [JFResponse new];
            response.code = receivedOpcode;
            response.bytesLeft = dataLength;
            response.buffer = [NSMutableData dataWithData:data];
        } else {
            if(receivedOpcode == JFOpCodeContinueFrame) {
                response.bytesLeft = dataLength;
            } else {
                NSLog(@"must be a continue frame");
                [self writeError:JFCloseCodeProtocolError];
                return;
            }
            [response.buffer appendData:data];
        }
        response.bytesLeft -= len;
        //NSLog(@"response bytesLeft: %d",response.bytesLeft);
//        if(response.bytesLeft <= 0) {
//            NSString *str = [[NSString alloc] initWithData:response.buffer encoding:NSUTF8StringEncoding];
//            NSLog(@"str: [%@]",str);
//            NSLog(@"buffer: [%s]",(char*)data.bytes);
//            NSLog(@"data length: %d",data.length);
//        }
        response.frameCount++;
        response.isFin = isFin;
        //NSLog(@"frame count: %d",response.frameCount);
        if(isNew) {
            [self.readStack addObject:response];
        }
        [self processResponse:response];
        
        NSInteger step = (offset+len);
        NSInteger extra = bufferLen-step;
        //NSLog(@"extra: %d",extra);
        if(extra > 0) {
            //NSLog(@"mar data");
            [self processExtra:(buffer+step) length:extra];
        }
    }
    
}
/////////////////////////////////////////////////////////////////////////////
-(void)processExtra:(uint8_t*)buffer length:(NSInteger)bufferLen
{
    if(bufferLen < 2) {
        //NSLog(@"frag it");
        self.fragBuffer = [NSData dataWithBytes:buffer length:bufferLen];
    } else {
        //NSLog(@"inspect: [%s]",buffer);
        //NSLog(@"mor data");
        [self processRawMessage:buffer length:bufferLen];
    }
}
/////////////////////////////////////////////////////////////////////////////
-(BOOL)processResponse:(JFResponse*)response
{
    if(response.isFin && response.bytesLeft <= 0) {
        NSData *data = response.buffer;
        if(response.code == JFOpCodePing) {
            //NSString *str = [[NSString alloc] initWithData:response.buffer encoding:NSUTF8StringEncoding];
            //NSLog(@"ping test: %@",str);
            [self dequeueWrite:response.buffer withCode:JFOpCodePong];
        } else if(response.code == JFOpCodeTextFrame) {
            NSString *str = [[NSString alloc] initWithData:response.buffer encoding:NSUTF8StringEncoding];
            if(!str) {
                [self writeError:JFCloseCodeEncoding];
                return NO;
            }
            if([self.delegate respondsToSelector:@selector(websocket:didReceiveMessage:)]) {
                dispatch_async(dispatch_get_main_queue(),^{
                    [self.delegate websocket:self didReceiveMessage:str];
                });
            }
        } else if([self.delegate respondsToSelector:@selector(websocket:didReceiveData:)]) {
            dispatch_async(dispatch_get_main_queue(),^{
                [self.delegate websocket:self didReceiveData:data];
            });
        }
        [self.readStack removeLastObject];
        return YES;
    }
    return NO;
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
    if(code == JFOpCodeTextFrame) {
        //NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        //NSLog(@"write this text: %@",str);
    }
    if(!self.writeQueue) {
        self.writeQueue = [[NSOperationQueue alloc] init];
        self.writeQueue.maxConcurrentOperationCount = 1;
    }
    //we have a queue so we can be thread safe.
    [self.writeQueue addOperationWithBlock:^{
        uint64_t offset = 2; //how many bytes do we need to skip for the header
        uint8_t *bytes = (uint8_t*)[data bytes];
        uint64_t dataLength = data.length;
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
        uint64_t total = 0;
        while (true) {
            if(!self.outputStream) {
                NSLog(@"output stream died!");
                break;
            }
            NSInteger len = [self.outputStream write:([frame bytes]+total) maxLength:offset-total];
            if(len < 0) {
                NSLog(@"Error writing");
                break;
            } else {
                total += len;
            }
            if(total >= offset) {
                NSLog(@"done writing!");
                break;
            }
        }
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

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
@implementation JFResponse

@end
/////////////////////////////////////////////////////////////////////////////
