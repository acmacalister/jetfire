/////////////////////////////////////////////////////////////////////////////
//
//  JFRSecurity.m
//
//  Created by Austin and Dalton Cherry on 9/3/15.
//  Copyright (c) 2015 Vluxe. All rights reserved.
//
/////////////////////////////////////////////////////////////////////////////

#import "JFRSecurity.h"

@interface JFRSSLCert ()

@property(nonatomic, strong)NSData *certData;
@property(nonatomic)SecKeyRef key;

@end

@implementation JFRSSLCert

/////////////////////////////////////////////////////////////////////////////
- (instancetype)initWithData:(NSData *)data {
    if(self = [super init]) {
        self.certData = data;
    }
    return self;
}
////////////////////////////////////////////////////////////////////////////
- (instancetype)initWithKey:(SecKeyRef)key {
    if(self = [super init]) {
        self.key = key;
    }
    return self;
}
////////////////////////////////////////////////////////////////////////////

@end

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////

@interface JFRSecurity ()

@property(nonatomic)BOOL isReady; //is the key processing done?
@property(nonatomic, strong)NSMutableArray *certificates;
@property(nonatomic, strong)NSMutableArray *pubKeys;
@property(nonatomic)BOOL usePublicKeys;

@end

@implementation JFRSecurity

- (instancetype)initUsingPublicKeys:(BOOL)publicKeys {
    if(self = [super init]) {
        
    }
    return self;
}

@end