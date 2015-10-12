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

/**
 Use certs from main app bundle
 
 :param usePublicKeys: is to specific if the publicKeys or certificates should be used for SSL pinning validation
 
 :returns: a representation security object to be used with
 */
- (instancetype)initWithCerts:(NSArray<JFRSSLCert*>*)certs publicKeys:(BOOL)publicKeys;

/**
 Designated init
 
 :param keys: is the certificates or public keys to use
 :param usePublicKeys: is to specific if the publicKeys or certificates should be used for SSL pinning validation
 
 :returns: a representation security object to be used with
 */
- (instancetype)initUsingPublicKeys:(BOOL)publicKeys;

/**
 Should the domain name be validated? Default is YES.
 */
@property(nonatomic)BOOL validatedDN;

/**
 Validate if the cert is legit or not.
 :param:  trust is the trust to validate
 :param: domain to validate along with the trust (can be nil)
 :return: YES or NO if valid.
 */
- (BOOL)isValid:(SecTrustRef)trust domain:(NSString*)domain;

@end
