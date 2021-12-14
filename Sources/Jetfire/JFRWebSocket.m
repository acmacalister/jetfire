//////////////////////////////////////////////////////////////////////////////////////////////////
//
//  JFRWebSocket.m
//
//  Created by Austin and Dalton Cherry on on 5/13/14.
//  Copyright (c) 2014-2017 Austin Cherry.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//
//////////////////////////////////////////////////////////////////////////////////////////////////

#import "JFRWebSocket.h"

//get the opCode from the packet
typedef NS_ENUM(NSUInteger, JFROpCode) {
    JFROpCodeContinueFrame = 0x0,
    JFROpCodeTextFrame = 0x1,
    JFROpCodeBinaryFrame = 0x2,
    //3-7 are reserved.
    JFROpCodeConnectionClose = 0x8,
    JFROpCodePing = 0x9,
    JFROpCodePong = 0xA,
    //B-F reserved.
};

typedef NS_ENUM(NSUInteger, JFRCloseCode) {
    JFRCloseCodeNormal                 = 1000,
    JFRCloseCodeGoingAway              = 1001,
    JFRCloseCodeProtocolError          = 1002,
    JFRCloseCodeProtocolUnhandledType  = 1003,
    // 1004 reserved.
    JFRCloseCodeNoStatusReceived       = 1005,
    //1006 reserved.
    JFRCloseCodeEncoding               = 1007,
    JFRCloseCodePolicyViolated         = 1008,
    JFRCloseCodeMessageTooBig          = 1009
};

typedef NS_ENUM(NSUInteger, JFRInternalErrorCode) {
    // 0-999 WebSocket status codes not used
    JFROutputStreamWriteError  = 1
};

#define kJFRInternalHTTPStatusWebSocket 101

//holds the responses in our read stack to properly process messages
@interface JFRResponse : NSObject

@property(nonatomic, assign)BOOL isFin;
@property(nonatomic, assign)JFROpCode code;
@property(nonatomic, assign)NSInteger bytesLeft;
@property(nonatomic, assign)NSInteger frameCount;
@property(nonatomic, strong)NSMutableData *buffer;

@end

@interface JFRWebSocket ()<NSStreamDelegate>

@property(nonatomic, strong, nonnull)NSURL *url;
@property(nonatomic, strong, null_unspecified)NSInputStream *inputStream;
@property(nonatomic, strong, null_unspecified)NSOutputStream *outputStream;
@property(nonatomic, strong, null_unspecified)NSOperationQueue *writeQueue;
@property(nonatomic, assign)BOOL isRunLoop;
@property(nonatomic, strong, nonnull)NSMutableArray *readStack;
@property(nonatomic, strong, nonnull)NSMutableArray *inputQueue;
@property(nonatomic, strong, nullable)NSData *fragBuffer;
@property(nonatomic, strong, nullable)NSMutableDictionary *headers;
@property(nonatomic, strong, nullable)NSArray *optProtocols;
@property(nonatomic, assign)BOOL isCreated;
@property(nonatomic, assign)BOOL didDisconnect;
@property(nonatomic, assign)BOOL certValidated;

@end

//Constant Header Values.
NS_ASSUME_NONNULL_BEGIN
static NSString *const headerWSUpgradeName     = @"Upgrade";
static NSString *const headerWSUpgradeValue    = @"websocket";
static NSString *const headerWSHostName        = @"Host";
static NSString *const headerWSConnectionName  = @"Connection";
static NSString *const headerWSConnectionValue = @"Upgrade";
static NSString *const headerWSProtocolName    = @"Sec-WebSocket-Protocol";
static NSString *const headerWSVersionName     = @"Sec-Websocket-Version";
static NSString *const headerWSVersionValue    = @"13";
static NSString *const headerWSKeyName         = @"Sec-WebSocket-Key";
static NSString *const headerOriginName        = @"Origin";
static NSString *const headerWSAcceptName      = @"Sec-WebSocket-Accept";
NS_ASSUME_NONNULL_END

//Class Constants
static char CRLFBytes[] = {'\r', '\n', '\r', '\n'};
static int BUFFER_MAX = 4096;

// This get the correct bits out by masking the bytes of the buffer.
static const uint8_t JFRFinMask             = 0x80;
static const uint8_t JFROpCodeMask          = 0x0F;
static const uint8_t JFRRSVMask             = 0x70;
static const uint8_t JFRMaskMask            = 0x80;
static const uint8_t JFRPayloadLenMask      = 0x7F;
static const size_t  JFRMaxFrameSize        = 32;

@implementation JFRWebSocket

/////////////////////////////////////////////////////////////////////////////
//Default initializer
- (instancetype)initWithURL:(NSURL *)url protocols:(NSArray*)protocols
{
    if(self = [super init]) {
        self.certValidated = NO;
        self.voipEnabled = NO;
        self.selfSignedSSL = NO;
        self.queue = dispatch_get_main_queue();
        self.url = url;
        self.readStack = [NSMutableArray new];
        self.inputQueue = [NSMutableArray new];
        self.optProtocols = protocols;
    }
    
    return self;
}
/////////////////////////////////////////////////////////////////////////////
//Exposed method for connecting to URL provided in init method.
- (void)connect {
    if(self.isCreated) {
        return;
    }
    
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.queue, ^{
        weakSelf.didDisconnect = NO;
    });

    //everything is on a background thread.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        weakSelf.isCreated = YES;
        [weakSelf createHTTPRequest];
        weakSelf.isCreated = NO;
    });
}
/////////////////////////////////////////////////////////////////////////////
- (void)disconnect {
    [self writeError:JFRCloseCodeNormal];
}
/////////////////////////////////////////////////////////////////////////////
- (void)writeString:(NSString*)string {
    if(string) {
        [self dequeueWrite:[string dataUsingEncoding:NSUTF8StringEncoding]
                  withCode:JFROpCodeTextFrame];
    }
}
/////////////////////////////////////////////////////////////////////////////
- (void)writePing:(NSData*)data {
    [self dequeueWrite:data withCode:JFROpCodePing];
}
/////////////////////////////////////////////////////////////////////////////
- (void)writeData:(NSData*)data {
    [self dequeueWrite:data withCode:JFROpCodeBinaryFrame];
}
/////////////////////////////////////////////////////////////////////////////
- (void)addHeader:(NSString*)value forKey:(NSString*)key {
    if(!self.headers) {
        self.headers = [[NSMutableDictionary alloc] init];
    }
    [self.headers setObject:value forKey:key];
}
/////////////////////////////////////////////////////////////////////////////

#pragma mark - connect's internal supporting methods

/////////////////////////////////////////////////////////////////////////////

- (NSString *)origin;
{
    NSString *scheme = [_url.scheme lowercaseString];
    
    if ([scheme isEqualToString:@"wss"]) {
        scheme = @"https";
    } else if ([scheme isEqualToString:@"ws"]) {
        scheme = @"http";
    }
    
    if (_url.port) {
        return [NSString stringWithFormat:@"%@://%@:%@/", scheme, _url.host, _url.port];
    } else {
        return [NSString stringWithFormat:@"%@://%@/", scheme, _url.host];
    }
}


//Uses CoreFoundation to build a HTTP request to send over TCP stream.
- (void)createHTTPRequest {
    CFURLRef url = CFURLCreateWithString(kCFAllocatorDefault, (CFStringRef)self.url.absoluteString, NULL);
    CFStringRef requestMethod = CFSTR("GET");
    CFHTTPMessageRef urlRequest = CFHTTPMessageCreateRequest(kCFAllocatorDefault,
                                                             requestMethod,
                                                             url,
                                                             kCFHTTPVersion1_1);
    CFRelease(url);
    
    NSNumber *port = _url.port;
    if (!port) {
        if([self.url.scheme isEqualToString:@"wss"] || [self.url.scheme isEqualToString:@"https"]){
            port = @(443);
        } else {
            port = @(80);
        }
    }
    NSString *protocols = nil;
    if([self.optProtocols count] > 0) {
        protocols = [self.optProtocols componentsJoinedByString:@","];
    }
    CFHTTPMessageSetHeaderFieldValue(urlRequest,
                                     (__bridge CFStringRef)headerWSHostName,
                                     (__bridge CFStringRef)[NSString stringWithFormat:@"%@:%@",self.url.host,port]);
    CFHTTPMessageSetHeaderFieldValue(urlRequest,
                                     (__bridge CFStringRef)headerWSVersionName,
                                     (__bridge CFStringRef)headerWSVersionValue);
    CFHTTPMessageSetHeaderFieldValue(urlRequest,
                                     (__bridge CFStringRef)headerWSKeyName,
                                     (__bridge CFStringRef)[self generateWebSocketKey]);
    CFHTTPMessageSetHeaderFieldValue(urlRequest,
                                     (__bridge CFStringRef)headerWSUpgradeName,
                                     (__bridge CFStringRef)headerWSUpgradeValue);
    CFHTTPMessageSetHeaderFieldValue(urlRequest,
                                     (__bridge CFStringRef)headerWSConnectionName,
                                     (__bridge CFStringRef)headerWSConnectionValue);
    if (protocols.length > 0) {
        CFHTTPMessageSetHeaderFieldValue(urlRequest,
                                         (__bridge CFStringRef)headerWSProtocolName,
                                         (__bridge CFStringRef)protocols);
    }
   
    CFHTTPMessageSetHeaderFieldValue(urlRequest,
                                     (__bridge CFStringRef)headerOriginName,
                                     (__bridge CFStringRef)[self origin]);
    
    for(NSString *key in self.headers) {
        CFHTTPMessageSetHeaderFieldValue(urlRequest,
                                         (__bridge CFStringRef)key,
                                         (__bridge CFStringRef)self.headers[key]);
    }
    
#if defined(DEBUG)
    NSLog(@"urlRequest = \"%@\"", urlRequest);
#endif
    NSData *serializedRequest = (__bridge_transfer NSData *)(CFHTTPMessageCopySerializedMessage(urlRequest));
    [self initStreamsWithData:serializedRequest port:port];
    CFRelease(urlRequest);
}
/////////////////////////////////////////////////////////////////////////////
//Random String of 16 lowercase chars, SHA1 and base64 encoded.
- (NSString*)generateWebSocketKey {
    NSInteger seed = 16;
    NSMutableString *string = [NSMutableString stringWithCapacity:seed];
    for (int i = 0; i < seed; i++) {
        [string appendFormat:@"%C", (unichar)('a' + arc4random_uniform(25))];
    }
    return [[string dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
}
/////////////////////////////////////////////////////////////////////////////
//Sets up our reader/writer for the TCP stream.
- (void)initStreamsWithData:(NSData*)data port:(NSNumber*)port {
    CFReadStreamRef readStream = NULL;
    CFWriteStreamRef writeStream = NULL;
    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)self.url.host, [port intValue], &readStream, &writeStream);
    
    self.inputStream = (__bridge_transfer NSInputStream *)readStream;
    self.inputStream.delegate = self;
    self.outputStream = (__bridge_transfer NSOutputStream *)writeStream;
    self.outputStream.delegate = self;
    if([self.url.scheme isEqualToString:@"wss"] || [self.url.scheme isEqualToString:@"https"]) {
        [self.inputStream setProperty:NSStreamSocketSecurityLevelNegotiatedSSL forKey:NSStreamSocketSecurityLevelKey];
        [self.outputStream setProperty:NSStreamSocketSecurityLevelNegotiatedSSL forKey:NSStreamSocketSecurityLevelKey];
    } else {
        self.certValidated = YES; //not a https session, so no need to check SSL pinning
    }
    if(self.voipEnabled) {
        [self.inputStream setProperty:NSStreamNetworkServiceTypeVoIP forKey:NSStreamNetworkServiceType];
        [self.outputStream setProperty:NSStreamNetworkServiceTypeVoIP forKey:NSStreamNetworkServiceType];
    }
    if(self.selfSignedSSL) {
        NSString *chain = (__bridge_transfer NSString *)kCFStreamSSLValidatesCertificateChain;
        NSString *peerName = (__bridge_transfer NSString *)kCFStreamSSLValidatesCertificateChain;
        NSString *key = (__bridge_transfer NSString *)kCFStreamPropertySSLSettings;
        NSDictionary *settings = @{chain: [[NSNumber alloc] initWithBool:NO],
                                   peerName: [NSNull null]};
        [self.inputStream setProperty:settings forKey:key];
        [self.outputStream setProperty:settings forKey:key];
    }
    self.isRunLoop = YES;
    [self.inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.inputStream open];
    [self.outputStream open];
    size_t dataLen = [data length];
    [self.outputStream write:[data bytes] maxLength:dataLen];
    while (self.isRunLoop) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
    }
}
/////////////////////////////////////////////////////////////////////////////

#pragma mark - NSStreamDelegate

/////////////////////////////////////////////////////////////////////////////
- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode {
    if(self.security && !self.certValidated && (eventCode == NSStreamEventHasBytesAvailable || eventCode == NSStreamEventHasSpaceAvailable)) {
        SecTrustRef trust = (__bridge SecTrustRef)([aStream propertyForKey:(__bridge_transfer NSString *)kCFStreamPropertySSLPeerTrust]);
        NSString *domain = [aStream propertyForKey:(__bridge_transfer NSString *)kCFStreamSSLPeerName];
        if([self.security isValid:trust domain:domain]) {
            self.certValidated = YES;
        } else {
            [self disconnectStream:[self errorWithDetail:@"Invalid SSL certificate" code:1]];
            return;
        }
    }
    switch (eventCode) {
        case NSStreamEventNone:
            break;
            
        case NSStreamEventOpenCompleted:
            break;
            
        case NSStreamEventHasBytesAvailable:
            if(aStream == self.inputStream) {
                [self processInputStream];
            }
            break;
            
        case NSStreamEventHasSpaceAvailable:
            break;
            
        case NSStreamEventErrorOccurred:
            [self disconnectStream:[aStream streamError]];
            break;
            
        case NSStreamEventEndEncountered:
            [self disconnectStream:nil];
            break;
            
        default:
            break;
    }
}
/////////////////////////////////////////////////////////////////////////////
- (void)disconnectStream:(NSError*)error {
    [self.writeQueue waitUntilAllOperationsAreFinished];
    [self.inputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.outputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.outputStream close];
    [self.inputStream close];
    self.outputStream = nil;
    self.inputStream = nil;
    self.isRunLoop = NO;
    _isConnected = NO;
    self.certValidated = NO;
    [self doDisconnect:error];
}
/////////////////////////////////////////////////////////////////////////////

#pragma mark - Stream Processing Methods

/////////////////////////////////////////////////////////////////////////////
- (void)processInputStream {
    @autoreleasepool {
        uint8_t buffer[BUFFER_MAX];
        NSInteger length = [self.inputStream read:buffer maxLength:BUFFER_MAX];
        if(length > 0) {
            if(!self.isConnected) {
                CFIndex responseStatusCode;
                BOOL status = [self processHTTP:buffer length:length responseStatusCode:&responseStatusCode];
#if defined(DEBUG)
                if (length < BUFFER_MAX) {
                    buffer[length] = 0x00;
                } else {
                    buffer[BUFFER_MAX - 1] = 0x00;
                }
                NSLog(@"response (%ld) = \"%s\"", responseStatusCode, buffer);
#endif
                if(status == NO) {
                    [self doDisconnect:[self errorWithDetail:@"Invalid HTTP upgrade" code:1 userInfo:@{@"HTTPResponseStatusCode" : @(responseStatusCode)}]];
                }
            } else {
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
- (void)dequeueInput {
    if(self.inputQueue.count > 0) {
        NSData *data = [self.inputQueue objectAtIndex:0];
        NSData *work = data;
        if(self.fragBuffer) {
            NSMutableData *combine = [NSMutableData dataWithData:self.fragBuffer];
            [combine appendData:data];
            work = combine;
            self.fragBuffer = nil;
        }
        [self processRawMessage:(uint8_t*)work.bytes length:work.length];
        [self.inputQueue removeObject:data];
        [self dequeueInput];
    }
}
/////////////////////////////////////////////////////////////////////////////
//Finds the HTTP Packet in the TCP stream, by looking for the CRLF.
- (BOOL)processHTTP:(uint8_t*)buffer length:(NSInteger)bufferLen responseStatusCode:(CFIndex*)responseStatusCode {
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
        BOOL status = [self validateResponse:buffer length:totalSize responseStatusCode:responseStatusCode];
        if (status == YES) {
            _isConnected = YES;
            __weak typeof(self) weakSelf = self;
            dispatch_async(self.queue,^{
                if([self.delegate respondsToSelector:@selector(websocketDidConnect:)]) {
                    [weakSelf.delegate websocketDidConnect:self];
                }
                if(weakSelf.onConnect) {
                    weakSelf.onConnect();
                }
            });
            totalSize += 1; //skip the last \n
            NSInteger  restSize = bufferLen-totalSize;
            if(restSize > 0) {
                [self processRawMessage:(buffer+totalSize) length:restSize];
            }
        }
        return status;
    }
    return NO;
}
/////////////////////////////////////////////////////////////////////////////
//Validate the HTTP is a 101, as per the RFC spec.
- (BOOL)validateResponse:(uint8_t *)buffer length:(NSInteger)bufferLen responseStatusCode:(CFIndex*)responseStatusCode {
    CFHTTPMessageRef response = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, NO);
    CFHTTPMessageAppendBytes(response, buffer, bufferLen);
    *responseStatusCode = CFHTTPMessageGetResponseStatusCode(response);
    BOOL status = ((*responseStatusCode) == kJFRInternalHTTPStatusWebSocket)?(YES):(NO);
    if(status == NO) {
        CFRelease(response);
        return NO;
    }
    NSDictionary *headers = (__bridge_transfer NSDictionary *)(CFHTTPMessageCopyAllHeaderFields(response));
    NSString *acceptKey = headers[headerWSAcceptName];
    CFRelease(response);
    if(acceptKey.length > 0) {
        return YES;
    }
    return NO;
}
/////////////////////////////////////////////////////////////////////////////
-(void)processRawMessage:(uint8_t*)buffer length:(NSInteger)bufferLen {
    JFRResponse *response = [self.readStack lastObject];
    if(response && bufferLen < 2) {
        self.fragBuffer = [NSData dataWithBytes:buffer length:bufferLen];
        return;
    }
    if(response.bytesLeft > 0) {
        NSInteger len = response.bytesLeft;
        NSInteger extra =  bufferLen - response.bytesLeft;
        if(response.bytesLeft > bufferLen) {
            len = bufferLen;
            extra = 0;
        }
        response.bytesLeft -= len;
        [response.buffer appendData:[NSData dataWithBytes:buffer length:len]];
        [self processResponse:response];
        NSInteger offset = bufferLen - extra;
        if(extra > 0) {
            [self processExtra:(buffer+offset) length:extra];
        }
        return;
    } else {
        if(bufferLen < 2) { // we need at least 2 bytes for the header
            self.fragBuffer = [NSData dataWithBytes:buffer length:bufferLen];
            return;
        }
        BOOL isFin = (JFRFinMask & buffer[0]);
        uint8_t receivedOpcode = (JFROpCodeMask & buffer[0]);
        BOOL isMasked = (JFRMaskMask & buffer[1]);
        uint8_t payloadLen = (JFRPayloadLenMask & buffer[1]);
        NSInteger offset = 2; //how many bytes do we need to skip for the header
        if((isMasked  || (JFRRSVMask & buffer[0])) && receivedOpcode != JFROpCodePong) {
            [self doDisconnect:[self errorWithDetail:@"masked and rsv data is not currently supported" code:JFRCloseCodeProtocolError]];
            [self writeError:JFRCloseCodeProtocolError];
            return;
        }
        BOOL isControlFrame = (receivedOpcode == JFROpCodeConnectionClose || receivedOpcode == JFROpCodePing);
        if(!isControlFrame && (receivedOpcode != JFROpCodeBinaryFrame && receivedOpcode != JFROpCodeContinueFrame && receivedOpcode != JFROpCodeTextFrame && receivedOpcode != JFROpCodePong)) {
            [self doDisconnect:[self errorWithDetail:[NSString stringWithFormat:@"unknown opcode: 0x%x",receivedOpcode] code:JFRCloseCodeProtocolError]];
            [self writeError:JFRCloseCodeProtocolError];
            return;
        }
        if(isControlFrame && !isFin) {
            [self doDisconnect:[self errorWithDetail:@"control frames can't be fragmented" code:JFRCloseCodeProtocolError]];
            [self writeError:JFRCloseCodeProtocolError];
            return;
        }
        if(receivedOpcode == JFROpCodeConnectionClose) {
            //the server disconnected us
            uint16_t code = JFRCloseCodeNormal;
            if(payloadLen == 1) {
                code = JFRCloseCodeProtocolError;
            }
            else if(payloadLen > 1) {
                code = CFSwapInt16BigToHost(*(uint16_t *)(buffer+offset) );
                if(code < 1000 || (code > 1003 && code < 1007) || (code > 1011 && code < 3000)) {
                    code = JFRCloseCodeProtocolError;
                }
                offset += 2;
            }
            
            if(payloadLen > 2) {
                NSInteger len = payloadLen-2;
                if(len > 0) {
                    NSData *data = [NSData dataWithBytes:(buffer+offset) length:len];
                    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    if(!str) {
                        code = JFRCloseCodeProtocolError;
                    }
                }
            }
            [self writeError:code];
            [self doDisconnect:[self errorWithDetail:@"continue frame before a binary or text frame" code:code]];
            return;
        }
        if(isControlFrame && payloadLen > 125) {
            [self writeError:JFRCloseCodeProtocolError];
            return;
        }
        NSInteger dataLength = payloadLen;
        if(payloadLen == 127) {
            dataLength = (NSInteger)CFSwapInt64BigToHost(*(uint64_t *)(buffer+offset));
            offset += sizeof(uint64_t);
        } else if(payloadLen == 126) {
            dataLength = CFSwapInt16BigToHost(*(uint16_t *)(buffer+offset) );
            offset += sizeof(uint16_t);
        }
        if(bufferLen < offset) { // we cannot process this yet, nead more header data
            self.fragBuffer = [NSData dataWithBytes:buffer length:bufferLen];
            return;
        }
        NSInteger len = dataLength;
        if(dataLength > (bufferLen-offset) || (bufferLen - offset) < dataLength) {
            len = bufferLen-offset;
        }
        NSData *data = nil;
        if(len < 0) {
            len = 0;
            data = [NSData data];
        } else {
            data = [NSData dataWithBytes:(buffer+offset) length:len];
        }
        if(receivedOpcode == JFROpCodePong) {
            NSInteger step = (offset+len);
            NSInteger extra = bufferLen-step;
            if(extra > 0) {
                [self processRawMessage:(buffer+step) length:extra];
            }
            return;
        }
        JFRResponse *response = [self.readStack lastObject];
        if(isControlFrame) {
            response = nil; //don't append pings
        }
        if(!isFin && receivedOpcode == JFROpCodeContinueFrame && !response) {
            [self doDisconnect:[self errorWithDetail:@"continue frame before a binary or text frame" code:JFRCloseCodeProtocolError]];
            [self writeError:JFRCloseCodeProtocolError];
            return;
        }
        BOOL isNew = NO;
        if(!response) {
            if(receivedOpcode == JFROpCodeContinueFrame) {
                [self doDisconnect:[self errorWithDetail:@"first frame can't be a continue frame" code:JFRCloseCodeProtocolError]];
                [self writeError:JFRCloseCodeProtocolError];
                return;
            }
            isNew = YES;
            response = [JFRResponse new];
            response.code = receivedOpcode;
            response.bytesLeft = dataLength;
            response.buffer = [NSMutableData dataWithData:data];
        } else {
            if(receivedOpcode == JFROpCodeContinueFrame) {
                response.bytesLeft = dataLength;
            } else {
                [self doDisconnect:[self errorWithDetail:@"second and beyond of fragment message must be a continue frame" code:JFRCloseCodeProtocolError]];
                [self writeError:JFRCloseCodeProtocolError];
                return;
            }
            [response.buffer appendData:data];
        }
        response.bytesLeft -= len;
        response.frameCount++;
        response.isFin = isFin;
        if(isNew) {
            [self.readStack addObject:response];
        }
        [self processResponse:response];
        
        NSInteger step = (offset+len);
        NSInteger extra = bufferLen-step;
        if(extra > 0) {
            [self processExtra:(buffer+step) length:extra];
        }
    }
    
}
/////////////////////////////////////////////////////////////////////////////
- (void)processExtra:(uint8_t*)buffer length:(NSInteger)bufferLen {
    if(bufferLen < 2) {
        self.fragBuffer = [NSData dataWithBytes:buffer length:bufferLen];
    } else {
        [self processRawMessage:buffer length:bufferLen];
    }
}
/////////////////////////////////////////////////////////////////////////////
- (BOOL)processResponse:(JFRResponse*)response {
    if(response.isFin && response.bytesLeft <= 0) {
        NSData *data = response.buffer;
        if(response.code == JFROpCodePing) {
            [self dequeueWrite:response.buffer withCode:JFROpCodePong];
        } else if(response.code == JFROpCodeTextFrame) {
            NSString *str = [[NSString alloc] initWithData:response.buffer encoding:NSUTF8StringEncoding];
            if(!str) {
                [self writeError:JFRCloseCodeEncoding];
                return NO;
            }
            __weak typeof(self) weakSelf = self;
            dispatch_async(self.queue,^{
                if([weakSelf.delegate respondsToSelector:@selector(websocket:didReceiveMessage:)]) {
                    [weakSelf.delegate websocket:weakSelf didReceiveMessage:str];
                }
                if(weakSelf.onText) {
                    weakSelf.onText(str);
                }
            });
        } else if(response.code == JFROpCodeBinaryFrame) {
            __weak typeof(self) weakSelf = self;
            dispatch_async(self.queue,^{
                if([weakSelf.delegate respondsToSelector:@selector(websocket:didReceiveData:)]) {
                    [weakSelf.delegate websocket:weakSelf didReceiveData:data];
                }
                if(weakSelf.onData) {
                    weakSelf.onData(data);
                }
            });
        }
        [self.readStack removeLastObject];
        return YES;
    }
    return NO;
}
/////////////////////////////////////////////////////////////////////////////
-(void)dequeueWrite:(NSData*)data withCode:(JFROpCode)code {
    if(!self.isConnected) {
        return;
    }
    if(!self.writeQueue) {
        self.writeQueue = [[NSOperationQueue alloc] init];
        self.writeQueue.maxConcurrentOperationCount = 1;
    }
    
    __weak typeof(self) weakSelf = self;
    [self.writeQueue addOperationWithBlock:^{
        if(!weakSelf || !weakSelf.isConnected) {
            return;
        }
        typeof(weakSelf) strongSelf = weakSelf;
        uint64_t offset = 2; //how many bytes do we need to skip for the header
        uint8_t *bytes = (uint8_t*)[data bytes];
        uint64_t dataLength = data.length;
        NSMutableData *frame = [[NSMutableData alloc] initWithLength:(NSInteger)(dataLength + JFRMaxFrameSize)];
        uint8_t *buffer = (uint8_t*)[frame mutableBytes];
        buffer[0] = JFRFinMask | code;
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
            buffer[1] |= JFRMaskMask;
            uint8_t *mask_key = (buffer + offset);
            (void)SecRandomCopyBytes(kSecRandomDefault, sizeof(uint32_t), (uint8_t *)mask_key);
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
            if(!strongSelf.isConnected || !strongSelf.outputStream) {
                break;
            }
            NSInteger len = [strongSelf.outputStream write:([frame bytes]+total) maxLength:(NSInteger)(offset-total)];
            if(len < 0 || len == NSNotFound) {
                NSError *error = strongSelf.outputStream.streamError;
                if(!error) {
                    error = [strongSelf errorWithDetail:@"output stream error during write" code:JFROutputStreamWriteError];
                }
                [strongSelf doDisconnect:error];
                break;
            } else {
                total += len;
            }
            if(total >= offset) {
                break;
            }
        }
    }];
}
/////////////////////////////////////////////////////////////////////////////
- (void)doDisconnect:(NSError*)error {
    if(!self.didDisconnect) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(self.queue, ^{
            weakSelf.didDisconnect = YES;
            [weakSelf disconnect];
            if([weakSelf.delegate respondsToSelector:@selector(websocketDidDisconnect:error:)]) {
                [weakSelf.delegate websocketDidDisconnect:weakSelf error:error];
            }
            if(weakSelf.onDisconnect) {
                weakSelf.onDisconnect(error);
            }
        });
    }
}
/////////////////////////////////////////////////////////////////////////////
- (NSError*)errorWithDetail:(NSString*)detail code:(NSInteger)code
{
    return [self errorWithDetail:detail code:code userInfo:nil];
}
- (NSError*)errorWithDetail:(NSString*)detail code:(NSInteger)code userInfo:(NSDictionary *)userInfo
{
    NSMutableDictionary* details = [NSMutableDictionary dictionary];
    details[detail] = NSLocalizedDescriptionKey;
    if (userInfo) {
        [details addEntriesFromDictionary:userInfo];
    }
    return [[NSError alloc] initWithDomain:@"JFRWebSocket" code:code userInfo:details];
}
/////////////////////////////////////////////////////////////////////////////
- (void)writeError:(uint16_t)code {
    uint16_t buffer[1];
    buffer[0] = CFSwapInt16BigToHost(code);
    [self dequeueWrite:[NSData dataWithBytes:buffer length:sizeof(uint16_t)] withCode:JFROpCodeConnectionClose];
}
/////////////////////////////////////////////////////////////////////////////
- (void)dealloc {
    if(self.isConnected) {
        [self disconnect];
    }
}
/////////////////////////////////////////////////////////////////////////////
@end

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
@implementation JFRResponse

@end
/////////////////////////////////////////////////////////////////////////////
