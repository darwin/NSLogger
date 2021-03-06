/*
 *
 * Modified BSD license.
 *
 * Copyright (c) 2012-2013 Sung-Taek, Kim <stkim1@colorfulglue.com> All Rights
 * Reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * 3. Any redistribution is done solely for personal benefit and not for any
 *    commercial purpose or for monetary gain
 *
 * 4. No binary form of source code is submitted to App Store℠ of Apple Inc.
 *
 * 5. Neither the name of the Sung-Taek, Kim nor the names of its contributors
 *    may be used to endorse or promote products derived from  this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR  IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL COPYRIGHT HOLDER AND AND CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 *
 */


#import "LoggerTransportManager.h"
#import "LoggerCertManager.h"
#import "LoggerNativeTransport.h"
#import "SynthesizeSingleton.h"
#import <zlib.h>

static NSString * const kTransportNotificationKey = @"notiKey";
static NSString * const kTransportNotificationUserInfo = @"userInfo";

@interface LoggerTransportManager()
@property (nonatomic, retain) LoggerCertManager *certManager;
@property (nonatomic, retain) NSMutableArray	*transports;

- (void)createTransports;
- (void)destoryTransports;
- (void)startTransports;
- (void)stopTransports;
-(void)presentNotificationOnMainThread:(NSDictionary *)aNotiDict;
@end

@implementation LoggerTransportManager
{
	LoggerCertManager			*_certManager;
	LoggerPreferenceManager		*_prefManager;
	NSMutableArray				*_transports;
	LoggerDataManager			*_dataManager;
	
}
@synthesize prefManager = _prefManager;
@synthesize certManager = _certManager;
@synthesize transports = _transports;
@synthesize dataManager = _dataManager;

SYNTHESIZE_SINGLETON_FOR_CLASS_WITH_ACCESSOR(LoggerTransportManager,sharedTransportManager);

- (id)init
{
	self = [super init];
	if (self)
	{
		if(_certManager == nil)
		{
			NSError *error = nil;
			LoggerCertManager *aCertManager = [[LoggerCertManager alloc] init];
			_certManager = aCertManager;
			
			// we load server cert at this point to reduce any delay might happen later
			// in transport object.
			if(![aCertManager loadEncryptionCertificate:&error])
			{
				// @@@ TODO: do something when error is not nil;
				NSLog(@"Certification loading error. SSL connection will not be available.\n\n %@",error);
			}
		}
		
		if(_transports == nil)
		{
			_transports = [[NSMutableArray alloc] initWithCapacity:0];
		}
	}

    return self;
}

-(void)createTransports
{
	// unencrypted Bonjour service (for backwards compatibility)
	LoggerNativeTransport *t;

	// SSL Bonjour service
	t = [[LoggerNativeTransport alloc] init];
	t.transManager = self;
	t.prefManager = [self prefManager];
	t.certManager = self.certManager;
	t.publishBonjourService = YES;
	t.useBluetooth = YES;
	t.secure = YES;
	t.tag = 0;
	[self.transports addObject:t];
	[t release];
	
	// non-SSL bonjour Service
	t = [[LoggerNativeTransport alloc] init];
	t.transManager = self;
	t.prefManager = [self prefManager];
	t.certManager = self.certManager;
	t.publishBonjourService = YES;
	t.useBluetooth = YES;
	t.secure = NO;
	t.tag = 1;
	[self.transports addObject:t];
	[t release];

	// Direct TCP/IP service (SSL mandatory)
	t = [[LoggerNativeTransport alloc] init];
	t.transManager = self;
	t.prefManager = [self prefManager];
	t.certManager = self.certManager;
	t.listenerPort = [self.prefManager directTCPIPResponderPort];
	t.secure = YES;
	t.tag = 2;
	[self.transports addObject:t];
	[t release];
}

-(void)destoryTransports
{
	[self stopTransports];
	[self.transports removeAllObjects];
}

-(void)startTransports
{
	// Start and stop transports as needed
	for (LoggerNativeTransport *transport in self.transports)
	{
		if(!transport.active)
		{
			[transport restart];
		}
	}
}

-(void)stopTransports
{	
	// Start and stop transports as needed
	for (LoggerNativeTransport *transport in self.transports)
	{
		[transport shutdown];
	}
}

// -----------------------------------------------------------------------------
#pragma mark - AppDelegate Cycle Handle
// -----------------------------------------------------------------------------

-(void)appStarted
{
	[self createTransports];
}

-(void)appBecomeActive
{
	[self startTransports];
}

-(void)appResignActive
{
	[self stopTransports];
}

-(void)appWillTerminate
{
	[self destoryTransports];
}

// -----------------------------------------------------------------------------
#pragma mark - Handling Report from Transport
// -----------------------------------------------------------------------------
-(void)presentNotificationOnMainThread:(NSDictionary *)aNotiDict
{
	if([NSThread isMainThread])
	{
		[[NSNotificationCenter defaultCenter]
		 postNotificationName:[aNotiDict valueForKey:kTransportNotificationKey]
		 object:self
		 userInfo:[aNotiDict valueForKey:kTransportNotificationUserInfo]];
	}
	else
	{
		[self
		 performSelectorOnMainThread:_cmd
		 withObject:aNotiDict
		 waitUntilDone:NO];
	}
}

-(void)presentTransportStatus:(NSDictionary *)aStatusDict
					   forKey:(NSString *)aKey
{
	[self
	 presentNotificationOnMainThread:
		 @{kTransportNotificationKey:aKey
		 ,kTransportNotificationUserInfo:aStatusDict}];
}

- (void)presentTransportStatus:(NSDictionary *)aStatusDict
{
	[self
	 presentNotificationOnMainThread:
		@{kTransportNotificationKey: kShowTransportStatusNotification
		,kTransportNotificationUserInfo:aStatusDict}];
}

- (void)presentTransportError:(NSDictionary *)anErrorDict
{
	[self
	 presentNotificationOnMainThread:
	 @{kTransportNotificationKey: kShowTransportErrorNotification
	 ,kTransportNotificationUserInfo:anErrorDict}];
}

// -----------------------------------------------------------------------------
#pragma mark - Logger Transport Delegate
// -----------------------------------------------------------------------------
// transport report new connection to manager
- (void)transport:(LoggerTransport *)theTransport
didEstablishConnection:(LoggerConnection *)theConnection
clientInfo:(LoggerMessage *)theInfoMessage
{
	// report transport status first
	[self presentTransportStatus:[theTransport status]];

	[_dataManager
	 transport:theTransport
	 didEstablishConnection:theConnection
	 clientInfo:theInfoMessage];
}

// method that may not be called on main thread
- (void)transport:(LoggerTransport *)theTransport
	   connection:(LoggerConnection *)theConnection
didReceiveMessages:(NSArray *)theMessages
			range:(NSRange)rangeInMessagesList
{
	[_dataManager
	 transport:theTransport
	 connection:theConnection
	 didReceiveMessages:theMessages
	 range:rangeInMessagesList];
}

- (void)transport:(LoggerTransport *)theTransport
didDisconnectRemote:(LoggerConnection *)theConnection
	  lastMessage:(LoggerMessage *)theLastMessage
{
	// report transport status first
	[self presentTransportStatus:[theTransport status]];

	[_dataManager
	 transport:theTransport
	 didDisconnectRemote:theConnection
	 lastMessage:theLastMessage];
}

- (void)transport:(LoggerTransport *)theTransport
 removeConnection:(LoggerConnection *)theConnection
{
	[_dataManager transport:theTransport removeConnection:theConnection];
}

@end
