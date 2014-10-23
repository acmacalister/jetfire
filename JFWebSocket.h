/////////////////////////////////////////////////////////////////////////////
//
//  JFWebSocket.h
//
//  Created by Austin and Dalton Cherry on 5/13/14.
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


/**
 There was an error when writing (sending data to the server).
 @param socket is the current socket object.
 @param error is an error that occured when writing.
 */
-(void)websocketDidWriteError:(JFWebSocket*)socket error:(NSError*)error;

@end

@interface JFWebSocket : NSObject

@property(nonatomic,weak)id<JFWebSocketDelegate>delegate;

/**
 constructor to create a new websocket.
 @param: url is the host you want to connect to.
 @param: protocols are the websocket protocols you want to use (e.g. chat,superchat).
 @return a newly initalized websocket.
 */
- (instancetype)initWithURL:(NSURL *)url protocols:(NSArray*)protocols;

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

/**
 returns if the socket is conneted or not.
 */
@property(nonatomic, assign, readonly)BOOL isConnected;

/**
 Add a header to send along on the the HTTP connect.
 @param: value is the string to send
 @param: key is the HTTP key name to send
 */
- (void)addHeader:(NSString*)value forKey:(NSString*)key;

/**
 Enable VOIP support on the socket, so it can be used in the background for VOIP calls.
 Default settings is NO.
 */
@property(nonatomic, assign)BOOL voipEnabled;

@end
