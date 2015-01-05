jetfire
=======

WebSocket [RFC 6455](http://tools.ietf.org/html/rfc6455) client library for iOS and OSX.

Jetfire conforms to all of the base [Autobahn test suite](http://autobahn.ws/testsuite/). The library is very simple and only a few hundred lines of code, but fully featured. It runs completely on a background thread, so processing will never block the main thread. 

jetfire also has a Swift counter part here: [starscream](https://github.com/daltoniam/starscream)

## Example ##

Open a connection to your websocket server. self.socket is a property, so it can stick around.

```objc
self.socket = [[JFRWebSocket alloc] initWithURL:[NSURL URLWithString:@"ws://localhost:8080"] protocols:@[@"chat",@"superchat"]];
self.socket.delegate = self;
[self.socket connect];
```

Now for the delegate methods.

```objc
/////////////////////////////////////////////////////////////////////////////
-(void)websocketDidConnect:(JFRWebSocket*)socket
{
    NSLog(@"websocket is connected");
}
/////////////////////////////////////////////////////////////////////////////
-(void)websocketDidDisconnect:(JFRWebSocket*)socket error:(NSError*)error
{
    NSLog(@"websocket is disconnected: %@",[error localizedDescription]);
}
/////////////////////////////////////////////////////////////////////////////
-(void)websocket:(JFRWebSocket*)socket didReceiveMessage:(NSString*)string
{
    NSLog(@"got some text: %@",string);
    dispatch_async(dispatch_get_main_queue(),^{
	//do some UI work
    });
}
/////////////////////////////////////////////////////////////////////////////
-(void)websocket:(JFRWebSocket*)socket didReceiveData:(NSData*)data
{
    NSLog(@"got some binary data: %d",data.length);
}
```

How to send a message.

```objc
-(void)sendMessage
{
	[self.socket writeString:@"hello server!"];
	//[self.socket writeData:[NSData data]]; you can also write binary data like so
}
```

Disconnect.

```objc
-(void)disconnect
{
	[self.socket disconnect];
}
```

### isConnected

Returns if the socket is connected or not.

```objc
if(self.socket.isConnected) {
  // do cool stuff.
}
```

### Custom Headers

You can also override the default websocket headers with your own custom ones like so:

```objc
[socket setHeader:@"Sec-WebSocket-Protocol" forKey:@"someother protocols"];
[socket setHeader:@"Sec-WebSocket-Version" forKey:@"14"];
[socket setHeader:@"My-Awesome-Header" forKey:@"Everything is Awesome!"];
```


## Install ##

The recommended approach for installing jetfire is via the CocoaPods package manager (like most libraries). 

## Requirements ##

jetfire requires at least iOS 5/OSX 10.7 or above.

## Dependencies ##
- Security.framework
- CFNetwork.framework

## License ##

jetfire is license under the Apache License.

## Contact ##

### Austin Cherry ###
* https://github.com/acmacalister
* http://twitter.com/acmacalister
* http://austincherry.me

### Dalton Cherry ###
* https://github.com/daltoniam
* http://twitter.com/daltoniam
* http://daltoniam.com
