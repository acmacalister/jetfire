//////////////////////////////////////////////////////////////////////////////////////////////////
//
//  JFRSecurity.m
//
//  Created by Austin and Dalton Cherry on on 9/3/15.
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
- (void)dealloc {
    if(self.key) {
        CFRelease(self.key);
    }
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

/////////////////////////////////////////////////////////////////////////////
- (instancetype)initUsingPublicKeys:(BOOL)publicKeys {
    NSArray *paths = [[NSBundle mainBundle] pathsForResourcesOfType:@"cer" inDirectory:@"."];
    NSMutableArray<JFRSSLCert*> *collect = [NSMutableArray array];
    for(NSString *path in paths) {
        NSData *data = [NSData dataWithContentsOfFile:path];
        if(data) {
            [collect addObject:[[JFRSSLCert alloc] initWithData:data]];
        }
    }
    return [self initWithCerts:collect publicKeys:publicKeys];
}
/////////////////////////////////////////////////////////////////////////////
- (instancetype)initWithCerts:(NSArray<JFRSSLCert*>*)certs publicKeys:(BOOL)publicKeys {
    if(self = [super init]) {
        self.validatedDN = YES;
        self.usePublicKeys = publicKeys;
        if(self.usePublicKeys) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0), ^{
                NSMutableArray *collect = [NSMutableArray array];
                for(JFRSSLCert *cert in certs) {
                    if(cert.certData && !cert.key) {
                        cert.key = [self extractPublicKey:cert.certData];
                    }
                    if(cert.key) {
                        [collect addObject:CFBridgingRelease(cert.key)];
                    }
                }
                self.certificates = collect;
                self.isReady = YES;
            });
        } else {
            NSMutableArray<NSData*> *collect = [NSMutableArray array];
            for(JFRSSLCert *cert in certs) {
                if(cert.certData) {
                    [collect addObject:cert.certData];
                }
            }
            self.certificates = collect;
            self.isReady = YES;
        }
    }
    return self;
}
/////////////////////////////////////////////////////////////////////////////
- (BOOL)isValid:(SecTrustRef)trust domain:(NSString*)domain {
    int tries = 0;
    while (!self.isReady) {
        usleep(1000);
        tries++;
        if(tries > 5) {
            return NO; //doesn't appear it is going to ever be ready...
        }
    }
    BOOL status = NO;
    SecPolicyRef policy;
    if(self.validatedDN) {
        policy = SecPolicyCreateSSL(true, (__bridge CFStringRef)domain);
    } else {
        policy = SecPolicyCreateBasicX509();
    }
    SecTrustSetPolicies(trust,policy);
    if(self.usePublicKeys) {
        for(id serverKey in [self publicKeyChainForTrust:trust]) {
            for(id keyObj in self.pubKeys) {
                if([serverKey isEqual:keyObj]) {
                    status = YES;
                    break;
                }
            }
        }
    } else {
        NSArray *serverCerts = [self certificateChainForTrust:trust];
        NSMutableArray *collect = [NSMutableArray arrayWithCapacity:self.certificates.count];
        for(NSData *data in self.certificates) {
            [collect addObject:CFBridgingRelease(SecCertificateCreateWithData(nil,(__bridge CFDataRef)data))];
        }
        SecTrustSetAnchorCertificates(trust,(__bridge CFArrayRef)collect);
        SecTrustResultType result = 0;
        SecTrustEvaluate(trust,&result);
        if(result == kSecTrustResultUnspecified || result == kSecTrustResultProceed) {
            NSInteger trustedCount = 0;
            for(NSData *serverData in serverCerts) {
                for(NSData *certData in self.certificates) {
                    if([certData isEqualToData:serverData]) {
                        trustedCount++;
                        break;
                    }
                }
            }
            if(trustedCount == serverCerts.count) {
                status = YES;
            }
        }
    }
    
    CFRelease(policy);
    return status;
}
/////////////////////////////////////////////////////////////////////////////
- (SecKeyRef)extractPublicKey:(NSData*)data {
    SecCertificateRef possibleKey = SecCertificateCreateWithData(nil,(__bridge CFDataRef)data);
    SecPolicyRef policy = SecPolicyCreateBasicX509();
    SecKeyRef key = [self extractPublicKeyFromCert:possibleKey policy:policy];
    CFRelease(policy);
    CFRelease(possibleKey);
    return key;
}
/////////////////////////////////////////////////////////////////////////////
- (SecKeyRef)extractPublicKeyFromCert:(SecCertificateRef)cert policy:(SecPolicyRef)policy {
    
    SecTrustRef trust;
    SecTrustCreateWithCertificates(cert,policy,&trust);
    SecTrustResultType result = kSecTrustResultInvalid;
    SecTrustEvaluate(trust,&result);
    SecKeyRef key = SecTrustCopyPublicKey(trust);
    CFRelease(trust);
    return key;
}
/////////////////////////////////////////////////////////////////////////////
- (NSArray*)certificateChainForTrust:(SecTrustRef)trust {
    NSMutableArray *collect = [NSMutableArray array];
    for(int i = 0; i < SecTrustGetCertificateCount(trust); i++) {
        SecCertificateRef cert = SecTrustGetCertificateAtIndex(trust,i);
        if(cert) {
            [collect addObject:CFBridgingRelease(SecCertificateCopyData(cert))];
        }
    }
    return collect;
}
/////////////////////////////////////////////////////////////////////////////
- (NSArray*)publicKeyChainForTrust:(SecTrustRef)trust {
    NSMutableArray *collect = [NSMutableArray array];
    SecPolicyRef policy = SecPolicyCreateBasicX509();
    for(int i = 0; i < SecTrustGetCertificateCount(trust); i++) {
        SecCertificateRef cert = SecTrustGetCertificateAtIndex(trust,i);
        SecKeyRef key = [self extractPublicKeyFromCert:cert policy:policy];
        if(key) {
            [collect addObject:CFBridgingRelease(key)];
        }
    }
    CFRelease(policy);
    return collect;
}
/////////////////////////////////////////////////////////////////////////////

@end
