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

@class JFWebSocket;

/**
 It is important to note that all the delegate methods are put back on the main thread.
 This means if you want to do some major process of the data, you need to create a background thread.
 */
@protocol JFWebSocketDelegate <NSObject>

@optional
/**
 The websocket connected to its host.
 @param socket is the current socket object.
 */
-(void)websocketDidConnect:(JFWebSocket*)socket;

/**
 The websocket was disconnected from its host.
 @param socket is the current socket object.
 @param error is return an error occured to trigger the disconnect.
 */
-(void)websocketDidDisconnect:(JFWebSocket*)socket error:(NSError*)error;

/**
 The websocket got a text based message.
 @param socket is the current socket object.
 @param string is the text based data that has been returned.
 */
-(void)websocket:(JFWebSocket*)socket didReceiveMessage:(NSString*)string;

/**
 The websocket got a binary based message.
 @param socket is the current socket object.
 @param data is the binary based data that has been returned.
 */
-(void)websocket:(JFWebSocket*)socket didReceiveData:(NSData*)data;

@end

@interface JFWebSocket : NSObject

@property(nonatomic,weak)id<JFWebSocketDelegate>delegate;

/**
 constructor to create a new websocket.
 @param: url is the host you want to connect to.
 @return a newly initalized websocket.
 */
- (instancetype)initWithURL:(NSURL *)url;

/**
 connect to the host.
 */
- (void)connect;

/**
 disconnect to the host. This sends the close Connection opcode to terminate cleanly.
 */
- (void)disconnect;

/**
 write binary based data to the socket.
 @param is the binary data to write.
 */
- (void)writeData:(NSData*)data;

/**
 write text based data to the socket.
 @param is the string to write.
 */
- (void)writeString:(NSString*)string;

@end
