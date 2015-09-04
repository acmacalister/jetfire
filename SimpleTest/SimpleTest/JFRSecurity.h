/////////////////////////////////////////////////////////////////////////////
//
//  JFRSecurity.h
//
//  Created by Austin and Dalton Cherry on 9/3/15.
//  Copyright (c) 2015 Vluxe. All rights reserved.
//
/////////////////////////////////////////////////////////////////////////////

#import <Foundation/Foundation.h>
#import <Security/Security.h>

@interface JFRSSLCert : NSObject

/**
 Designated init for certificates
 
 :param: data is the binary data of the certificate
 
 :returns: a representation security object to be used with
 */
- (instancetype)initWithData:(NSData *)data;


/**
 Designated init for public keys
 
 :param: key is the public key to be used
 
 :returns: a representation security object to be used with
 */
- (instancetype)initWithKey:(SecKeyRef)key;

@end

@interface JFRSecurity : NSObject

@property(nonatomic)BOOL validatedDN; //should the domain name be validated?

@end