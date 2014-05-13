/////////////////////////////////////////////////////////////////////////////
//
//  JFWebSocket.h
//  WebSocketTester
//
//  Created by Austin Cherry on 5/13/14.
//  Copyright (c) 2014 Vluxe. All rights reserved.
//
/////////////////////////////////////////////////////////////////////////////

#import <Foundation/Foundation.h>

@interface JFWebSocket : NSObject

- (instancetype)initWithURL:(NSURL *)url;
- (void)connect;

@end
