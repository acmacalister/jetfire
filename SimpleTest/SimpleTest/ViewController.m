//
//  ViewController.m
//  SimpleTest
//
//  Created by Austin Cherry on 2/24/15.
//  Copyright (c) 2015 Vluxe. All rights reserved.
//

#import "ViewController.h"
#import "JFRWebSocket.h"

@interface ViewController ()<JFRWebSocketDelegate>

@property(nonatomic, strong)JFRWebSocket *socket;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.socket = [[JFRWebSocket alloc] initWithURL:[NSURL URLWithString:@"ws://localhost:8080"] protocols:@[@"chat",@"superchat"]];
    self.socket.delegate = self;
    [self.socket connect];
}

// pragma mark: WebSocket Delegate methods.

-(void)websocketDidConnect:(JFRWebSocket*)socket {
    NSLog(@"websocket is connected");
}

-(void)websocketDidDisconnect:(JFRWebSocket*)socket error:(NSError*)error {
    NSLog(@"websocket is disconnected: %@", [error localizedDescription]);
        [self.socket connect];
}

-(void)websocket:(JFRWebSocket*)socket didReceiveMessage:(NSString*)string {
    NSLog(@"Received text: %@", string);
}

-(void)websocket:(JFRWebSocket*)socket didReceiveData:(NSData*)data {
    NSLog(@"Received data: %@", data);
}

// pragma mark: target actions.

- (IBAction)writeText:(UIBarButtonItem *)sender {
    [self.socket writeString:@"hello there!"];
}

- (IBAction)disconnect:(UIBarButtonItem *)sender {
    [self.socket disconnect];
}

@end
