/////////////////////////////////////////////////////////////////////////////
//
//  JFRWebSocket.h
//
//  Created by Austin and Dalton Cherry on 5/13/14.
//  Copyright (c) 2014 Vluxe. All rights reserved.
//
/////////////////////////////////////////////////////////////////////////////

#import <Foundation/Foundation.h>

@class JFRWebSocket;

/**
 It is important to note that all the delegate methods are put back on the main thread.
 This means if you want to do some major process of the data, you need to create a background thread.
 */
@protocol JFRWebSocketDelegate <NSObject>

@optional
/**
 The websocket connected to its host.
 @param socket is the current socket object.
 */
-(void)websocketDidConnect:(JFRWebSocket*)socket;

/**
 The websocket was disconnected from its host.
 @param socket is the current socket object.
 @param error is return an error occured to trigger the disconnect.
 */
-(void)websocketDidDisconnect:(JFRWebSocket*)socket error:(NSError*)error;

/**
 The websocket got a text based message.
 @param socket is the current socket object.
 @param string is the text based data that has been returned.
 */
-(void)websocket:(JFRWebSocket*)socket didReceiveMessage:(NSString*)string;

/**
 The websocket got a binary based message.
 @param socket is the current socket object.
 @param data is the binary based data that has been returned.
 */
-(void)websocket:(JFRWebSocket*)socket didReceiveData:(NSData*)data;

@end

@interface JFRWebSocket : NSObject

@property(nonatomic,weak)id<JFRWebSocketDelegate>delegate;

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
 write ping to the socket.
 @param is the binary data to write (if desired).
 */
- (void)writePing:(NSData*)data;

/**
 Add a header to send along on the the HTTP connect.
 @param: value is the string to send
 @param: key is the HTTP key name to send
 */
- (void)addHeader:(NSString*)value forKey:(NSString*)key;

/**
 returns if the socket is conneted or not.
 */
@property(nonatomic, assign, readonly)BOOL isConnected;

/**
 Enable VOIP support on the socket, so it can be used in the background for VOIP calls.
 Default setting is No.
 */
@property(nonatomic, assign)BOOL voipEnabled;

/**
 Allows connection to self signed or untrusted WebSocket connection. Useful for development.
 Default setting is No.
 */
@property(nonatomic, assign)BOOL selfSignedSSL;

/**
 Set your own custom queue.
 Default setting is dispatch_get_main_queue.
 */
@property(nonatomic, strong)dispatch_queue_t queue;

/**
 Block property to use on connect.
 */
@property(nonatomic, strong)void (^onConnect)(void);

/**
 Block property to use on disconnect.
 */
@property(nonatomic, strong)void (^onDisconnect)(NSError*);

/**
 Block property to use on receiving data.
 */
@property(nonatomic, strong)void (^onData)(NSData*);

/**
 Block property to use on receiving text.
 */
@property(nonatomic, strong)void (^onText)(NSString*);

@end
