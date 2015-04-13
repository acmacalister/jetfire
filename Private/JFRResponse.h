//
//  JFRResponse.h
//  SimpleTest
//
//  Created by Adam Kaplan on 4/13/15.
//  Copyright (c) 2015 Vluxe. All rights reserved.
//

#import <Foundation/Foundation.h>

/** this get the correct bits out by masking the bytes of the buffer. */
extern const uint8_t JFRResponseFinMask;
extern const uint8_t JFRResponseOpCodeMask;
extern const uint8_t JFRResponseRSVMask;
extern const uint8_t JFRResponseMaskMask;
extern const uint8_t JFRResponsePayloadLenMask;

extern const size_t  JFRResponseMaxFrameSize;

/** opcode from websocket frame spec. See RFC-6455 https://tools.ietf.org/html/rfc6455#page-28 */
typedef NS_ENUM(NSUInteger, JFRResponseOpCode) {
    JFROpCodeContinueFrame      = 0x0,
    JFROpCodeTextFrame          = 0x1,
    JFROpCodeBinaryFrame        = 0x2,
    // 3-7 are reserved.
    JFROpCodeConnectionClose    = 0x8,
    JFROpCodePing               = 0x9,
    JFROpCodePong               = 0xA,
    // B-F are reserved.
};

/** close code from websocket frame spec. See RFC-6455 https://tools.ietf.org/html/rfc6455#page-64 */
typedef NS_ENUM(NSUInteger, JFRResponseCloseCode) {
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

/** Private class to hold the responses in our read stack to properly process messages */
@interface JFRResponse : NSObject

@property(nonatomic) BOOL isFinished;
@property(nonatomic) JFRResponseOpCode opCode;
@property(nonatomic) NSInteger bytesRemaining;
@property(nonatomic) NSInteger frameCount;
@property(nonatomic) NSMutableData *buffer;

@end
