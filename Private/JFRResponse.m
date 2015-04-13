//
//  JFRResponse.m
//  SimpleTest
//
//  Created by Adam Kaplan on 4/13/15.
//  Copyright (c) 2015 Vluxe. All rights reserved.
//

#import "JFRResponse.h"

const uint8_t JFRResponseFinMask        = 0x80;
const uint8_t JFRResponseOpCodeMask     = 0x0F;
const uint8_t JFRResponseRSVMask        = 0x70;
const uint8_t JFRResponseMaskMask       = 0x80;
const uint8_t JFRResponsePayloadLenMask = 0x7F;

const size_t  JFRResponseMaxFrameSize   = 32;

@implementation JFRResponse

@end
