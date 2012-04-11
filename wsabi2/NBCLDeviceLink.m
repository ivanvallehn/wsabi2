//
//  NBCLSensorLink.m
//  Wsabi
//
//  Created by Matt Aronoff on 3/24/10.
//
/*
 This software was developed at the National Institute of Standards and Technology by employees of the Federal Government
 in the course of their official duties. Pursuant to title 17 Section 105 of the United States Code this software is not 
 subject to copyright protection and is in the public domain. Wsabi is an experimental system. NIST assumes no responsibility 
 whatsoever for its use by other parties, and makes no guarantees, expressed or implied, about its quality, reliability, or 
 any other characteristic. We would appreciate acknowledgement if the software is used.
 */

// Updated Feb 2012 for ARC support

#import "NBCLDeviceLink.h"


@implementation NBCLDeviceLink
@synthesize delegate;
@synthesize registered, hasLock, initialized, sequenceInProgress;
@synthesize connectedAndReady;
@synthesize shouldRetryDownloadIfPending;
@synthesize uri, currentSessionId, networkTimeout;

@synthesize mainNamespace, schemaInstanceNamespace, schemaNamespace;

@synthesize exponentialIntervalMax;
@synthesize currentWSBDResult, currentWSBDParameter;
@synthesize currentElementName, currentElementValue, currentElementAttributes;
@synthesize currentContainerArray, currentContainerDictionary, currentDictionaryKey, currentDictionaryValue;
@synthesize captureIds;
@synthesize downloadSequenceResults;
@synthesize acceptableContentTypes;

-(id) init
{
	if ((self = [super init])) {
		self.captureIds = [[NSMutableArray alloc] init];
		responseData = [NSMutableData data];
        
        cancelResponseData = [NSMutableData data];
        
        self.mainNamespace = @"xmlns=\"urn:oid:2.16.840.1.101.3.9.3.1\"";
        self.schemaInstanceNamespace = @"xmlns:i=\"http://www.w3.org/2001/XMLSchema-instance\"";
        self.schemaNamespace = @"xmlns:xs=\"http://www.w3.org/2001/XMLSchema\"";
        
        operationInProgress = -1; //nothing currently in progress.
		operationPendingCancellation = -1; //nothing currently in the process of being cancelled.
        
		//initialize and configure the network queue.
		networkQueue = [[ASINetworkQueue alloc] init];
		[networkQueue setMaxConcurrentOperationCount:1]; //perform operations sequentially.
		//make sure we remove all other requests if something in the chain fails.
		//This prevents, for example, capturing with the wrong parameters if configure fails.
		[networkQueue setShouldCancelAllRequestsOnFailure:YES];
		[networkQueue setDelegate:self]; //in case we want finish/fail selectors later.
		[networkQueue go];
		
		//get the list of acceptable MIME types from the user prefs.
		self.acceptableContentTypes = [[NSUserDefaults standardUserDefaults] objectForKey:@"acceptableContentTypes"];
        
        downloadRetryCount = [[NSMutableDictionary alloc] init];
        //This should retrieve the expected maximum processing time from commonInfo
        self.exponentialIntervalMax = 30; //seconds

        //set a default timeout for all network operations.
        self.networkTimeout = 30; //this is an NSTimeInterval, and is therefore in seconds.
        
        //start with all convenience variables set to NO
        self.registered = NO;
        self.hasLock = NO;
        self.initialized = NO;
        
        self.sequenceInProgress = kSensorSequenceNone;
	}
	return self;
}

+(NSString*) stringForOpType:(int)opType
{
    /*
     kOpTypeRegister = 0,
     kOpTypeUnregister,
     kOpTypeLock,
     kOpTypeUnlock,
     kOpTypeStealLock,
     kOpTypeGetCommonInfo,
     kOpTypeGetDetailedInfo,
     kOpTypeInitialize,
     kOpTypeGetConfiguration,
     kOpTypeConfigure,
     kOpTypeGetContentType,
     kOpTypeCapture,
     kOpTypeDownload,
     kOpTypeThriftyDownload,
     kOpTypeCancel,
     kOpTypeConnectSequence,
     kOpTypeCaptureSequence,
     kOpTypeDisconnectSequence,
     kOpTypeAll
     */
    switch (opType) {
        case kOpTypeRegister:
            return @"Register";
            break;
        case kOpTypeUnregister:
            return @"Unregister";
            break;
        case kOpTypeLock:
            return @"Lock";
            break;
        case kOpTypeUnlock:
            return @"Unlock";
            break;
        case kOpTypeStealLock:
            return @"Steal Lock";
            break;
        case kOpTypeGetCommonInfo:
            return @"Get Info";
            break;
        case kOpTypeGetDetailedInfo:
            return @"Get Detailed Info";
            break;
        case kOpTypeInitialize:
            return @"Initialize";
            break;
        case kOpTypeGetConfiguration:
            return @"Get Configuration";
            break;
        case kOpTypeConfigure:
            return @"Configure";
            break;
        case kOpTypeGetContentType:
            return @"Content Type";
            break;
        case kOpTypeCapture:
            return @"Capture";
            break;
        case kOpTypeDownload:
            return @"Download";
            break;
        case kOpTypeThriftyDownload:
            return @"Thrifty Download";
            break;
        case kOpTypeCancel:
            return @"Cancel";
            break;
        case kOpTypeConnectSequence:
            return @"Connect Sequence";
            break;
        case kOpTypeCaptureSequence:
            return @"Capture Sequence";
            break;
        case kOpTypeDisconnectSequence:
            return @"Disconnect Sequence";
            break;
        case kOpTypeAll:
            return @"All";
            break;

        default:
            return @"";
            break;
    }
}

#pragma mark - Property accessors
//-(void) setUri:(NSString *)newUri
//{
//    if (uri != newUri) {
//        [newUri retain];
//        [uri release];
//        uri = newUri;
//    }
//    
//    if (![uri hasPrefix:@"http://"]) {
//         //prepend this prefix if it doesn't exist.
//        uri = [[@"http://" stringByAppendingString:uri] retain];
//    }
//}
	

//TODO: Check for more HTTP error codes here.
-(BOOL) checkHTTPStatus:(ASIHTTPRequest*)request
{
	switch ([request responseStatusCode]) {
		case 404:
			[self sensorOperationFailed:request];
			return NO;
            operationInProgress = -1; //nothing's actually happening if the operation doesn't return valid data.
			break;
		default:
			return YES;
			break;
	}
	
}

#pragma mark - Convenience methods to combine multiple steps
-(BOOL) beginConnectSequenceWithSourceObjectID:(NSURL*)sourceObjectID
{
    if (self.sequenceInProgress) {
        //don't start another sequence if one is in progress
        return NO;
    }
  
    //kick off the connection sequence
    self.sequenceInProgress = kSensorSequenceConnect;
    [self beginRegisterClient:sourceObjectID];
    return YES;
        
}

-(BOOL) beginConfigureSequence:(NSString*)sessionId
           configurationParams:(NSMutableDictionary*)params
                 sourceObjectID:(NSURL*)sourceID
{
    if (self.sequenceInProgress) {
        //don't start another sequence if one is in progress
        return NO;
    }
    
    //kick off the capture sequence
    self.sequenceInProgress = kSensorSequenceConfigure;
    pendingConfiguration = params;
    [self beginLock:sessionId sourceObjectID:sourceID];
    
    return YES;

}

-(BOOL) beginConnectConfigureSequenceWithConfigurationParams:(NSMutableDictionary*)params
                 sourceObjectID:(NSURL*)sourceID
{
    if (self.sequenceInProgress) {
        //don't start another sequence if one is in progress
        return NO;
    }
    
    //kick off the connection sequence
    self.sequenceInProgress = kSensorSequenceConnectConfigure;
    pendingConfiguration = params;
    [self beginRegisterClient:sourceID];
    return YES;

}

-(BOOL) beginCaptureDownloadSequence:(NSString *)sessionId 
                               withMaxSize:(float)maxSize
                             sourceObjectID:(NSURL*)sourceID
{
    if (self.sequenceInProgress) {
        //don't start another sequence if one is in progress
        return NO;
    }
    
    //kick off the capture sequence
    self.sequenceInProgress = kSensorSequenceCaptureDownload;
    downloadMaxSize = maxSize;
    
    //start by grabbing the lock
    [self beginLock:sessionId sourceObjectID:sourceID];
    
    return YES;
}

-(BOOL) beginConfigCaptureDownloadSequence:(NSString *)sessionId 
                 configurationParams:(NSMutableDictionary*)params
                 withMaxSize:(float)maxSize
               sourceObjectID:(NSURL*)sourceID
{
    if (self.sequenceInProgress) {
        //don't start another sequence if one is in progress
        return NO;
    }
    
    //kick off the capture sequence
    self.sequenceInProgress = kSensorSequenceConfigCaptureDownload;
    downloadMaxSize = maxSize;
    pendingConfiguration = params;
    
    //start by grabbing the lock
    [self beginLock:sessionId sourceObjectID:sourceID];
    
    return YES;
}

-(BOOL) beginFullSequenceWithConfigurationParams:(NSMutableDictionary *)params 
                                     withMaxSize:(float)maxSize 
                                   sourceObjectID:(NSURL*)sourceID
{
    if (self.sequenceInProgress) {
        //don't start another sequence if one is in progress
        return NO;
    }
    
    //kick off the capture sequence
    self.sequenceInProgress = kSensorSequenceFull;
    downloadMaxSize = maxSize;
    pendingConfiguration = params;
    
    //start by registering with the service
    [self beginRegisterClient:sourceID];
    
    return YES;

}

-(BOOL) beginDisconnectSequence:(NSString*)sessionId sourceObjectID:(NSURL*)sourceID
{
    if (self.sequenceInProgress) {
        //don't start another sequence if one is in progress
        return NO;
    }
    
    //kick off the disconnect sequence
    self.sequenceInProgress = kSensorSequenceDisconnect;
    [self beginUnlock:self.currentSessionId sourceObjectID:sourceID];
    return YES;
    
}

#pragma mark -
#pragma mark Methods to start various operations.

//Register
-(void) beginRegisterClient:(NSURL*)sourceObjectID
{
	ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/register",self.uri]]];
	NSLog(@"Calling beginRegisterClient with URL %@",request.url);
	request.requestMethod = @"POST";
	request.userInfo = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:kOpTypeRegister],@"opType",sourceObjectID,kDictKeySourceID,nil]; //we'll use this to identify this operation.
	request.delegate = self;
    request.timeOutSeconds = self.networkTimeout;
    request.shouldContinueWhenAppEntersBackground = YES;
    
	[request setDidFinishSelector:@selector(registerClientCompleted:)];
	[networkQueue addOperation:request];
    
    operationInProgress = kOpTypeRegister;
}

-(void) beginUnregisterClient:(NSString*)sessionId sourceObjectID:(NSURL*)sourceID
{	
	NSLog(@"Calling beginUnregisterClient");
	ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/register/%@",self.uri, sessionId]]];
	request.requestMethod = @"DELETE";
	request.userInfo = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:kOpTypeUnregister],@"opType",sourceID,kDictKeySourceID,nil]; //we'll use this to identify this operation.
	request.delegate = self;
    request.timeOutSeconds = self.networkTimeout;
    request.shouldContinueWhenAppEntersBackground = YES;

	[request setDidFinishSelector:@selector(unregisterClientCompleted:)];
	[networkQueue addOperation:request];
    operationInProgress = kOpTypeUnregister;

}


//Lock
-(void) beginLock:(NSString*)sessionId sourceObjectID:(NSURL*)sourceID
{
	NSLog(@"Calling beginLock");
	ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/lock/%@",self.uri, sessionId]]];
	request.requestMethod = @"POST";
	request.userInfo = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:kOpTypeLock],@"opType",sourceID,kDictKeySourceID,nil]; //we'll use this to identify this operation.
	request.delegate = self;
    request.timeOutSeconds = self.networkTimeout;
    request.shouldContinueWhenAppEntersBackground = YES;

	[request setDidFinishSelector:@selector(lockCompleted:)];
	[networkQueue addOperation:request];
    operationInProgress = kOpTypeLock;

}

-(void) beginStealLock:(NSString*)sessionId sourceObjectID:(NSURL*)sourceID
{
	NSLog(@"Calling beginStealLock");
	ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/lock/%@",self.uri, sessionId]]];
	request.requestMethod = @"PUT";
	request.userInfo = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:kOpTypeStealLock],@"opType",sourceID,kDictKeySourceID,nil]; //we'll use this to identify this operation.
	request.delegate = self;
    request.timeOutSeconds = self.networkTimeout;
    request.shouldContinueWhenAppEntersBackground = YES;

	[request setDidFinishSelector:@selector(stealLockCompleted:)];
	[networkQueue addOperation:request];
	operationInProgress = kOpTypeStealLock;
}

-(void) beginUnlock:(NSString*)sessionId sourceObjectID:(NSURL*)sourceID
{
	NSLog(@"Calling beginUnlock");
	ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/lock/%@",self.uri, sessionId]]];
	request.requestMethod = @"DELETE";
	request.userInfo = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:kOpTypeUnlock],@"opType",sourceID,kDictKeySourceID,nil]; //we'll use this to identify this operation.
	request.delegate = self;
    request.timeOutSeconds = self.networkTimeout;
    request.shouldContinueWhenAppEntersBackground = YES;

	[request setDidFinishSelector:@selector(unlockCompleted:)];
	[networkQueue addOperation:request];
    operationInProgress = kOpTypeUnlock;
}


//Info
-(void) beginGetCommonInfo:(NSURL*)sourceObjectID
{
	NSLog(@"Calling beginCommonInfo");
	ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/info",self.uri]]];
	request.requestMethod = @"GET";
	request.userInfo = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:kOpTypeGetCommonInfo],@"opType",sourceObjectID,kDictKeySourceID,nil]; //we'll use this to identify this operation.
	request.delegate = self;
    request.timeOutSeconds = self.networkTimeout;
    request.shouldContinueWhenAppEntersBackground = YES;

	[request setDidFinishSelector:@selector(getCommonInfoCompleted:)];
	[networkQueue addOperation:request];
	operationInProgress = kOpTypeGetCommonInfo;
}

-(void) beginGetDetailedInfo:(NSString*)sessionId sourceObjectID:(NSURL*)sourceID
{
	NSLog(@"Calling beginGetInfo");
	ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/info/%@",self.uri, sessionId]]];
	request.requestMethod = @"GET";
	request.userInfo = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:kOpTypeGetDetailedInfo],@"opType",sourceID,kDictKeySourceID,nil]; //we'll use this to identify this operation.
	request.delegate = self;
    request.timeOutSeconds = self.networkTimeout;
    request.shouldContinueWhenAppEntersBackground = YES;

	[request setDidFinishSelector:@selector(getInfoCompleted:)];
	[networkQueue addOperation:request];
	operationInProgress = kOpTypeGetDetailedInfo;
}

//Initialize
-(void) beginInitialize:(NSString*)sessionId sourceObjectID:(NSURL*)sourceID
{
	NSLog(@"Calling beginInitialize");
	ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/initialize/%@",self.uri, sessionId]]];
	request.requestMethod = @"POST";
	request.userInfo = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:kOpTypeInitialize],@"opType",sourceID,kDictKeySourceID,nil]; //we'll use this to identify this operation.
	request.delegate = self;
    request.timeOutSeconds = self.networkTimeout;
    request.shouldContinueWhenAppEntersBackground = YES;

	[request setDidFinishSelector:@selector(initializeCompleted:)];
	[networkQueue addOperation:request];
	operationInProgress = kOpTypeInitialize;
}

//Configure
-(void) beginGetConfiguration:(NSString*)sessionId sourceObjectID:(NSURL*)sourceID
{
	NSLog(@"Calling beginGetConfiguration");
	ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/configure/%@",self.uri, sessionId]]];
	request.requestMethod = @"GET";
	request.userInfo = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:kOpTypeConfigure],@"opType",sourceID,kDictKeySourceID,nil]; //we'll use this to identify this operation.
	request.delegate = self;
    request.timeOutSeconds = self.networkTimeout;
    request.shouldContinueWhenAppEntersBackground = YES;

	[request setDidFinishSelector:@selector(getConfigurationCompleted:)];
	[networkQueue addOperation:request];
	operationInProgress = kOpTypeGetConfiguration;
}

-(void) beginConfigure:(NSString*)sessionId withParameters:(NSDictionary*)params sourceObjectID:(NSURL*)sourceID
{
	NSLog(@"Calling beginConfigure");
	//build the body of the message from our stored parameters
	NSMutableString *messageBody = [NSMutableString stringWithFormat:@"<configuration %@ %@ %@>", self.schemaInstanceNamespace, self.schemaNamespace, self.mainNamespace];
	if (params) {
        for(NSString* key in params)
        {
            [messageBody appendFormat:@"<item><key>%@</key><value i:type=\"xs:string\">%@</value></item>", key, [params objectForKey:key]];
        }
    }
	[messageBody appendString:@"</configuration>"];

//    NSString *messageBody = @"<WsbdDictionary xmlns:i=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns=\"http://itl.nist.gov/wsbd/L1\"><item><key>submodality</key><value xmlns:d3p1=\"http://www.w3.org/2001/XMLSchema\" i:type=\"d3p1:string\">rightThumb</value></item></WsbdDictionary>";
  
	//build the request
	ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/configure/%@",self.uri, sessionId]]];
	request.requestMethod = @"POST";
	NSData *tempData = [messageBody dataUsingEncoding:NSUTF8StringEncoding];
	[request addRequestHeader:@"Content-Type" value:@"application/xml; charset=utf-8"];
	[request appendPostData:tempData];
	
    NSLog(@"Raw configure headers are\n%@",request.requestHeaders);
	NSLog(@"Raw configure request is \n%@",[[NSString alloc] initWithData:[request postBody] encoding:NSUTF8StringEncoding]);
	
    
	request.userInfo = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:kOpTypeConfigure],@"opType",sourceID,kDictKeySourceID,nil]; //we'll use this to identify this operation.
	request.delegate = self;
    request.timeOutSeconds = self.networkTimeout;
    request.shouldContinueWhenAppEntersBackground = YES;

	[request setDidFinishSelector:@selector(configureCompleted:)];
	[networkQueue addOperation:request];
	operationInProgress = kOpTypeConfigure;
}


//Capture
-(void) beginCapture:(NSString*)sessionId sourceObjectID:(NSURL*)sourceID
{

	NSLog(@"Calling beginCapture");
	ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/capture/%@",self.uri, sessionId]]];
	request.requestMethod = @"POST";
	request.userInfo = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:kOpTypeCapture],@"opType",sourceID,kDictKeySourceID,nil]; //we'll use this to identify this operation.
	request.delegate = self;
    request.timeOutSeconds = self.networkTimeout;
    request.shouldContinueWhenAppEntersBackground = YES;

	[request setDidFinishSelector:@selector(captureCompleted:)];
	[networkQueue addOperation:request];
	operationInProgress = kOpTypeCapture;
}

-(void) beginGetCaptureInfo:(NSString*)captureId sourceObjectID:(NSURL*)sourceID
{
	NSLog(@"Calling beginGetCaptureInfo");
	ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/capture/%@",self.uri, captureId]]];
	request.requestMethod = @"GET";
	[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:kOpTypeGetContentType],@"opType",sourceID,kDictKeySourceID,nil]; //we'll use this to identify this operation.
	request.delegate = self;
    request.timeOutSeconds = self.networkTimeout;
    request.shouldContinueWhenAppEntersBackground = YES;

	[request setDidFinishSelector:@selector(getCaptureInfoCompleted:)];
	[networkQueue addOperation:request];
    operationInProgress = kOpTypeGetContentType;
}



//Download
-(void) beginDownload:(NSString*)captureId sourceObjectID:(NSURL*)sourceID
{
	NSLog(@"Calling beginDownload");
	ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/download/%@",self.uri, captureId]]];
	request.requestMethod = @"GET";
	request.userInfo = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:kOpTypeDownload],@"opType",sourceID,kDictKeySourceID,captureId,@"captureId",nil]; //we'll use this to identify this operation.
	request.delegate = self;
    request.timeOutSeconds = self.networkTimeout;
    request.shouldContinueWhenAppEntersBackground = YES;

	[request setDidFinishSelector:@selector(downloadCompleted:)];
	[networkQueue addOperation:request];
	operationInProgress = kOpTypeDownload;
}

-(void) beginDownload:(NSString*)captureId withMaxSize:(float)maxSize sourceObjectID:(NSURL*)sourceID
{
	NSLog(@"Calling beginDownload:withMaxSize");
	ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/download/%@/%1.0f",self.uri, captureId, maxSize]]];
	request.requestMethod = @"GET";
	request.userInfo = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:kOpTypeThriftyDownload],@"opType",sourceID,kDictKeySourceID,captureId,@"captureId",nil]; //we'll use this to identify this operation.
	request.delegate = self;
    request.timeOutSeconds = self.networkTimeout;
    request.shouldContinueWhenAppEntersBackground = YES;

	[request setDidFinishSelector:@selector(downloadCompleted:)];
	[networkQueue addOperation:request];
	operationInProgress = kOpTypeThriftyDownload;
}

//Cancel
-(void) beginCancel:(NSString*)sessionId sourceObjectID:(NSURL*)sourceID
{
	NSLog(@"Calling beginCancel");
	ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/cancel/%@",self.uri, sessionId]]];
	request.requestMethod = @"POST";
	request.userInfo = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:kOpTypeCancel],@"opType",sourceID,kDictKeySourceID,nil]; //we'll use this to identify this operation.
	request.delegate = self;
    request.timeOutSeconds = self.networkTimeout;
    request.shouldContinueWhenAppEntersBackground = YES;

    [request setDidStartSelector:@selector(cancelRequestStarted:)];
    [request setDidReceiveDataSelector:@selector(cancelRequest:didReceiveData:)];
    [request setDidFailSelector:@selector(cancelRequestFailed:)];
	[request setDidFinishSelector:@selector(cancelCompleted:)];

	//Don't add this to the main network queue, as we don't want it stuck behind
    //the operation it's trying to cancel. Instead, start it this way,
    //which places it in a global NSOperationQueue that won't wait for the previous operation.
    [request startAsynchronous];
	operationPendingCancellation = operationInProgress; //store the operation we're cancelling.
    operationInProgress = kOpTypeCancel;
}

#pragma mark -
#pragma mark Async completion methods
//NOTE: These are largely repetitive at the moment, but may not be in the future.

//NOTE: This gets hit when the request fails, but also when the request contains an HTTP error code.
-(void) sensorOperationFailed:(ASIHTTPRequest*)request
{
	NSLog(@"Sensor operation failed with message %@", request.responseStatusMessage);
	[delegate sensorOperationDidFail:[[request.userInfo objectForKey:@"opType"] intValue] 
							fromLink:self 
                       sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]
						   withError:request.error];
    operationInProgress = -1;
}

//Register
-(void) registerClientCompleted:(ASIHTTPRequest*)request
{
	NSLog(@"Completed registration request");
	if (![self checkHTTPStatus:request])
		return;

	BOOL parseSuccess = [self parseResultData:responseData];
	if (parseSuccess) {
        [delegate sensorOperationCompleted:[[request.userInfo objectForKey:@"opType"] intValue] 
                                  fromLink:self
                                 sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]
                                withResult:self.currentWSBDResult];
    }
    else {
        [self sensorOperationFailed:request];
        if (self.sequenceInProgress) {
            self.sequenceInProgress = kSensorSequenceNone; //stop the sequence, as we've got a failure.
            [delegate sequenceDidFail:self.sequenceInProgress
                                   fromLink:self
                                 withResult:self.currentWSBDResult
                              sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]
             ];

        }
        return;
    }
 
    if (self.currentWSBDResult.status == StatusSuccess) {
        //set the registered convenience variable.
        self.registered = YES;
        //store the current session id.
        self.currentSessionId = self.currentWSBDResult.sessionId;
        //if this call is part of a sequence, call the next step.
        if (self.sequenceInProgress) {
            [self beginLock:self.currentSessionId sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]];
        }
    }
    else if (self.sequenceInProgress) {
        self.sequenceInProgress = kSensorSequenceNone; //stop the sequence, as we've got a failure.
        [delegate connectSequenceCompletedFromLink:self 
                                              withResult:self.currentWSBDResult
                                           sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]];
    }
    operationInProgress = -1;

}

-(void) unregisterClientCompleted:(ASIHTTPRequest*)request
{
	NSLog(@"Completed unregister request");
	if (![self checkHTTPStatus:request])
		return;

	BOOL parseSuccess = [self parseResultData:responseData];
	if (parseSuccess) {
        [delegate sensorOperationCompleted:[[request.userInfo objectForKey:@"opType"] intValue] 
                                  fromLink:self
                             sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]
                                withResult:self.currentWSBDResult];
    }
    else {
        [self sensorOperationFailed:request];
        if (self.sequenceInProgress) {
            self.sequenceInProgress = kSensorSequenceNone; //stop the sequence, as we've got a failure.
            [delegate sequenceDidFail:self.sequenceInProgress
                                   fromLink:self
                                 withResult:self.currentWSBDResult
                              sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]
             ];
        }
        return;

    }
    
    if (self.currentWSBDResult.status == StatusSuccess) {
        //set the registered convenience variable.
        self.registered = NO;

        //notify the delegate that we're no longer "connected and ready"
        [delegate sensorConnectionStatusChanged:NO 
                                       fromLink:self
                                  sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]
         ];

        //clear the current session id.
        self.currentSessionId = nil;
    }

    //if this call is part of a sequence, notify our delegate that the sequence is complete.
    if (self.sequenceInProgress) {
        self.sequenceInProgress = kSensorSequenceNone;
        [delegate disconnectSequenceCompletedFromLink:self 
                                                 withResult:self.currentWSBDResult 
                                              sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]];
        
    }
    operationInProgress = -1;


}

//Lock
-(void) lockCompleted:(ASIHTTPRequest*)request
{
	NSLog(@"Completed lock request");
	if (![self checkHTTPStatus:request])
		return;
	
    BOOL parseSuccess = [self parseResultData:responseData];
	if (parseSuccess) {
        [delegate sensorOperationCompleted:[[request.userInfo objectForKey:@"opType"] intValue] 
                                  fromLink:self
                             sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]
                                withResult:self.currentWSBDResult
         ];
    }
    else {
        [self sensorOperationFailed:request];
        if (self.sequenceInProgress) {
            self.sequenceInProgress = kSensorSequenceNone; //stop the sequence, as we've got a failure.
            [delegate sequenceDidFail:self.sequenceInProgress
                                   fromLink:self
                                 withResult:self.currentWSBDResult
                              sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]
             ];
        }

        return;
    }

    if (self.currentWSBDResult.status == StatusSuccess) {
        //set the lock convenience variable.
        self.hasLock = YES;
        //if this call is part of a sequence, call the next step.
        if (self.sequenceInProgress == kSensorSequenceConnect ||
            self.sequenceInProgress == kSensorSequenceFull) 
        {
            [self beginInitialize:self.currentSessionId sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]];
        }
        else if (self.sequenceInProgress == kSensorSequenceConfigure ||
                 self.sequenceInProgress == kSensorSequenceConfigCaptureDownload) {
            
            [self beginConfigure:self.currentSessionId withParameters:pendingConfiguration
                   sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]];
        }
        else if (self.sequenceInProgress == kSensorSequenceCaptureDownload)
        {
            [self beginCapture:self.currentSessionId sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]];
        }
    }
//    else if (self.sequenceInProgress && shouldTryStealLock)
//    {
//        //If the lock operation failed, but we've been told to try stealing the lock
//        //if necessary, try to steal the lock.
//        [self beginStealLock:self.currentSessionId sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]];
//    }
    else if (self.sequenceInProgress) {
        self.sequenceInProgress = kSensorSequenceNone; //stop the sequence, as we've got a failure.
        [delegate sequenceDidFail:self.sequenceInProgress
                               fromLink:self
                             withResult:self.currentWSBDResult
                          sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]
         ];
    }

    operationInProgress = -1;

}

-(void) stealLockCompleted:(ASIHTTPRequest*)request
{
	NSLog(@"Completed steal lock request");

	if (![self checkHTTPStatus:request])
		return;
	
    BOOL parseSuccess = [self parseResultData:responseData];
	if (parseSuccess) {
        [delegate sensorOperationCompleted:[[request.userInfo objectForKey:@"opType"] intValue] 
                                  fromLink:self 
                             sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]
                                withResult:self.currentWSBDResult];
    }
    else {
        [self sensorOperationFailed:request];
        if (self.sequenceInProgress) {
            self.sequenceInProgress = kSensorSequenceNone; //stop the sequence, as we've got a failure.
            [delegate sequenceDidFail:self.sequenceInProgress
                                   fromLink:self
                                 withResult:self.currentWSBDResult
                              sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]
             ];
        }
        
        return;

    }
    if (self.currentWSBDResult.status == StatusSuccess) {
        //set the lock convenience variable.
        self.hasLock = YES;
        //if this call is part of a sequence, call the next step.
        if (self.sequenceInProgress == kSensorSequenceConnect) {
            [self beginInitialize:self.currentSessionId sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]];
        }
        else if (self.sequenceInProgress == kSensorSequenceConfigure ||
                 self.sequenceInProgress == kSensorSequenceConfigCaptureDownload) {
            
            [self beginConfigure:self.currentSessionId withParameters:pendingConfiguration
                   sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]];
        }
        else if (self.sequenceInProgress == kSensorSequenceCaptureDownload)
        {
            [self beginCapture:self.currentSessionId sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]];
        }

    }
    else if (self.sequenceInProgress) {
        self.sequenceInProgress = kSensorSequenceNone; //stop the sequence, as we've got a failure.
        [delegate sequenceDidFail:self.sequenceInProgress
                               fromLink:self
                             withResult:self.currentWSBDResult
                          sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]
         ];
    }

    operationInProgress = -1;

}

-(void) unlockCompleted:(ASIHTTPRequest*)request
{
	NSLog(@"Completed unlock request");
	if (![self checkHTTPStatus:request])
		return;
	
    BOOL parseSuccess = [self parseResultData:responseData];
	if (parseSuccess) {
        [delegate sensorOperationCompleted:[[request.userInfo objectForKey:@"opType"] intValue] 
                                  fromLink:self 
                                sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]
                                withResult:self.currentWSBDResult];
    }
    else {
        [self sensorOperationFailed:request];
        if (self.sequenceInProgress) {
            self.sequenceInProgress = kSensorSequenceNone; //stop the sequence, as we've got a failure.
            [delegate sequenceDidFail:self.sequenceInProgress
                                   fromLink:self
                                 withResult:self.currentWSBDResult
                              sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]
             ];
        }
        return;

    }

    if (self.currentWSBDResult.status == StatusSuccess) {
        //set the lock convenience variable.
        self.hasLock = NO;
   
        //notify the delegate that we're no longer "connected and ready"
        [delegate sensorConnectionStatusChanged:NO fromLink:self sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]];
         
        //if this call is part of a sequence, call the next step.
        if (self.sequenceInProgress == kSensorSequenceDisconnect) {
            [self beginUnregisterClient:self.currentSessionId sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]];
        }
        
        /** MOST SEQUENCES END HERE **/
        
        else if(self.sequenceInProgress == kSensorSequenceConnect)
        {
            //this is the end of the sequence.
            self.sequenceInProgress = kSensorSequenceNone;
            [delegate connectSequenceCompletedFromLink:self
                                            withResult:self.currentWSBDResult
                                         sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]];
        }
        else if(self.sequenceInProgress == kSensorSequenceConfigure)
        {
            //this is the end of the sequence.
            self.sequenceInProgress = kSensorSequenceNone;
            [delegate configureSequenceCompletedFromLink:self
                                            withResult:self.currentWSBDResult
                                         sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]];
        }
        else if(self.sequenceInProgress == kSensorSequenceConnectConfigure)
        {
            //this is the end of the sequence.
            self.sequenceInProgress = kSensorSequenceNone;
            [delegate connectConfigureSequenceCompletedFromLink:self
                                            withResult:self.currentWSBDResult
                                         sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]];
        }
 

    }

    else if (self.sequenceInProgress) {
        self.sequenceInProgress = kSensorSequenceNone; //stop the sequence, as we've got a failure.
        [delegate sequenceDidFail:self.sequenceInProgress
                               fromLink:self
                             withResult:self.currentWSBDResult
                          sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]
         ];
    }

    operationInProgress = -1;

}

//Info
-(void) getCommonInfoCompleted:(ASIHTTPRequest*)request
{
	NSLog(@"Completed common info request");

	if (![self checkHTTPStatus:request])
		return;
	BOOL parseSuccess = [self parseResultData:responseData];
	if (parseSuccess) {
        [delegate sensorOperationCompleted:[[request.userInfo objectForKey:@"opType"] intValue] 
                                  fromLink:self
                             sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]
                                withResult:self.currentWSBDResult];
    }
    else {
        [self sensorOperationFailed:request];
        
    }
    operationInProgress = -1;

}

-(void) getInfoCompleted:(ASIHTTPRequest*)request
{
	NSLog(@"Completed detailed info request");

	if (![self checkHTTPStatus:request])
		return;
    
	BOOL parseSuccess = [self parseResultData:responseData];
	if (parseSuccess) {
        [delegate sensorOperationCompleted:[[request.userInfo objectForKey:@"opType"] intValue] 
                                  fromLink:self 
                            sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]
                                withResult:self.currentWSBDResult];
    }
    else {
        [self sensorOperationFailed:request];
        
    }
    operationInProgress = -1;

}

//Initialize
-(void) initializeCompleted:(ASIHTTPRequest*)request
{
	NSLog(@"Completed initialization request");

	if (![self checkHTTPStatus:request])
		return;
    
	BOOL parseSuccess = [self parseResultData:responseData];
	if (parseSuccess) {
        [delegate sensorOperationCompleted:[[request.userInfo objectForKey:@"opType"] intValue] 
                                  fromLink:self 
                             sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]
                                withResult:self.currentWSBDResult];
    }
    else {
        [self sensorOperationFailed:request];
        if (self.sequenceInProgress) {
            self.sequenceInProgress = kSensorSequenceNone; //stop the sequence, as we've got a failure.
            [delegate sequenceDidFail:self.sequenceInProgress
                                   fromLink:self
                                 withResult:self.currentWSBDResult
                              sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]
             ];
        }
        self.initialized = NO;
        operationInProgress = -1;
        return;

    }
    
    if (self.currentWSBDResult.status == StatusSuccess) {
        //set the initialization convenience variable.
        self.initialized = YES;
        //notify the delegate that our status is now "connected and ready"
        [delegate sensorConnectionStatusChanged:YES fromLink:self sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]];
        
        if (self.sequenceInProgress == kSensorSequenceFull) {
            //If we're doing a full sequence of operations, continue to configuring the sensor.
            [self beginConfigure:self.currentSessionId withParameters:pendingConfiguration sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]];
        }
    }
    else if (self.sequenceInProgress) {
        self.sequenceInProgress = kSensorSequenceNone; //stop the sequence, as we've got a failure.
        [delegate sequenceDidFail:self.sequenceInProgress
                         fromLink:self
                       withResult:self.currentWSBDResult
                    sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]
         ];
    }

    //if this call is part of a sequence (and we're not running a full sequence), we need to release the lock now.
    if (self.sequenceInProgress && self.sequenceInProgress != kSensorSequenceFull) {
        
        [self beginUnlock:self.currentSessionId sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]];

    }
    operationInProgress = -1;

}

//Configure
-(void) getConfigurationCompleted:(ASIHTTPRequest *)request
{
	NSLog(@"Completed get config request");

	if (![self checkHTTPStatus:request])
		return;
    
	BOOL parseSuccess = [self parseResultData:responseData];
	if (parseSuccess) {
        [delegate sensorOperationCompleted:[[request.userInfo objectForKey:@"opType"] intValue] 
                                  fromLink:self 
                                sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]
                                withResult:self.currentWSBDResult];
    }
    else {
        [self sensorOperationFailed:request];
        
    }
    operationInProgress = -1;

}

-(void) configureCompleted:(ASIHTTPRequest*)request
{
	NSLog(@"Completed set config request");

	if (![self checkHTTPStatus:request])
		return;

    BOOL parseSuccess = [self parseResultData:responseData];
	if (parseSuccess) {
        [delegate sensorOperationCompleted:[[request.userInfo objectForKey:@"opType"] intValue] 
                                  fromLink:self 
                             sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]
                                withResult:self.currentWSBDResult];
    }
    else {
        [self sensorOperationFailed:request];
        if (self.sequenceInProgress) {
            self.sequenceInProgress = kSensorSequenceNone; //stop the sequence, as we've got a failure.
            [delegate sequenceDidFail:self.sequenceInProgress
                                   fromLink:self
                                 withResult:self.currentWSBDResult
                              sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]
             ];
        }
        operationInProgress = -1;
        return;

    }

    if (self.currentWSBDResult.status == StatusSuccess) {
        //if this call is part of a sequence, call the next step.
        if (self.sequenceInProgress == kSensorSequenceConfigCaptureDownload ||
            self.sequenceInProgress == kSensorSequenceFull
            ) 
        {
            //begin capture
            [self beginCapture:self.currentSessionId sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]];
        }
        else if (self.sequenceInProgress == kSensorSequenceConfigure ||
                 self.sequenceInProgress == kSensorSequenceConnectConfigure)
        {
            //First, return the lock
            [self beginUnlock:self.currentSessionId sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]];

            //In this case, this is the last step, so unset the sequence variable and
            //notify our delegate.
            self.sequenceInProgress = kSensorSequenceNone;
            [delegate configureSequenceCompletedFromLink:self
                                              withResult:self.currentWSBDResult
                                           sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]];
        }
        
    }
    else if (self.sequenceInProgress) {
        self.sequenceInProgress = kSensorSequenceNone; //stop the sequence, as we've got a failure.
        [delegate sequenceDidFail:self.sequenceInProgress
                               fromLink:self
                             withResult:self.currentWSBDResult
                          sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]
         ];
    }
    operationInProgress = -1;

}

//Capture
-(void) captureCompleted:(ASIHTTPRequest*)request
{
	NSLog(@"Completed capture request");

	if (![self checkHTTPStatus:request])
		return;

    BOOL parseSuccess = [self parseResultData:responseData];
	if (parseSuccess) {
        [delegate sensorOperationCompleted:[[request.userInfo objectForKey:@"opType"] intValue] 
                                  fromLink:self 
                             sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]
                                withResult:self.currentWSBDResult];
    }
    else {
        [self sensorOperationFailed:request];
        if (self.sequenceInProgress) {
            self.sequenceInProgress = kSensorSequenceNone; //stop the sequence, as we've got a failure.
            [delegate sequenceDidFail:self.sequenceInProgress
                                   fromLink:self
                                 withResult:self.currentWSBDResult
                              sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]
             ];
        }
        operationInProgress = -1;
        return;

    }

    if (self.currentWSBDResult.status == StatusSuccess) {
        //if this call is part of a sequence, call the next step.
        if (self.sequenceInProgress) {
            //First, return the lock
            [self beginUnlock:self.currentSessionId sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]];
            //reset any existing download sequence variables.
            if (self.downloadSequenceResults) {
                [self.downloadSequenceResults removeAllObjects];
                self.downloadSequenceResults = nil;
            }

            //download each result.
            numCaptureIdsAwaitingDownload = [self.currentWSBDResult.captureIds count]; //since we're doing this asynchronously, we'll use this to know when we're done.
            for (NSString *capId in self.currentWSBDResult.captureIds) {
                [self beginDownload:capId withMaxSize:downloadMaxSize sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]];
            }
        }
    }
    else if (self.sequenceInProgress) {
        self.sequenceInProgress = kSensorSequenceNone; //stop the sequence, as we've got a failure.
        [delegate sequenceDidFail:self.sequenceInProgress
                               fromLink:self
                             withResult:self.currentWSBDResult
                          sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]
         ];
    }
    
    operationInProgress = -1;

}

-(void) getCaptureInfoCompleted:(ASIHTTPRequest*)request
{
	NSLog(@"Completed get capture info request");

	if (![self checkHTTPStatus:request])
		return;
    
	BOOL parseSuccess = [self parseResultData:responseData];
	if (parseSuccess) {
        [delegate sensorOperationCompleted:[[request.userInfo objectForKey:@"opType"] intValue] 
                                  fromLink:self 
                             sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]
                                withResult:self.currentWSBDResult];
    }
    else {
        [self sensorOperationFailed:request];
        
    }
    operationInProgress = -1;

}


//Download
//this works for both beginDownload calls
-(void) downloadCompleted:(ASIHTTPRequest*)request
{
	NSLog(@"Completed download request");

	if (![self checkHTTPStatus:request])
		return;

    BOOL parseSuccess = [self parseResultData:responseData];
	if (parseSuccess) {
        [delegate sensorOperationCompleted:[[request.userInfo objectForKey:@"opType"] intValue] 
                                  fromLink:self
                                sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]
                                withResult:self.currentWSBDResult];
    }
    else {
        [self sensorOperationFailed:request];
        //don't stop any sequence in progress here, as other download results may succeed.
        numCaptureIdsAwaitingDownload--;
        return;
    }

    float exponentialMultiplier = 0.5;
    NSString *currentId = [request.userInfo objectForKey:@"captureId"];
    if (!self.downloadSequenceResults) {
        self.downloadSequenceResults = [[NSMutableArray alloc] init];
    }

    if (self.currentWSBDResult.status == StatusSuccess) {
        //add the current download result to the list.
        [self.downloadSequenceResults addObject:self.currentWSBDResult];
        numCaptureIdsAwaitingDownload--;
        if (numCaptureIdsAwaitingDownload <= 0) {           
            if(self.sequenceInProgress == kSensorSequenceCaptureDownload ||
               self.sequenceInProgress == kSensorSequenceConfigCaptureDownload)
            {
                [delegate configCaptureDownloadSequenceCompletedFromLink:self withResults:self.downloadSequenceResults sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]];
            }
            else if (self.sequenceInProgress == kSensorSequenceFull)
            {
                [delegate fullSequenceCompletedFromLink:self withResults:self.downloadSequenceResults sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]];
            }
            self.sequenceInProgress = kSensorSequenceNone;
             numCaptureIdsAwaitingDownload = 0;
        }
        //remove any retry counter attached to this request.
        if (currentId) {
            [downloadRetryCount removeObjectForKey:currentId];
        }
    }
    
    //Otherwise, if we're configured to retry automatically, do it.
    else if (self.currentWSBDResult.status == StatusPreparingDownload && self.shouldRetryDownloadIfPending)
    {
        //do an exponential back-off
        int currentCaptureRetryCount = [[downloadRetryCount objectForKey:currentId] intValue];
        //figure out the current retry interval
        NSTimeInterval currentCaptureInterval = (2^currentCaptureRetryCount - 1) * exponentialMultiplier;
        
        while (currentCaptureInterval < self.exponentialIntervalMax) {
            
            [NSThread sleepForTimeInterval:currentCaptureInterval]; //NOTE: we may need to run these *Completed methods on their own threads to avoid blocking the queue...?
            //put a new attempt at this download in the queue.
            [self beginDownload:currentId withMaxSize:downloadMaxSize sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]];
            
            //increase the retry count
            [downloadRetryCount setObject:[NSNumber numberWithInt:(currentCaptureRetryCount + 1)] forKey:currentId];
        }
    
    }
    
     operationInProgress = -1;

}

//Cancel
-(void) cancelCompleted:(ASIHTTPRequest*)request
{
	NSLog(@"Completed cancel request");

	if (![self checkHTTPStatus:request])
		return;

    BOOL parseSuccess = [self parseResultData:cancelResponseData];
	if (parseSuccess) {
        //The *cancel* operation succeeded, so fire the delegate for that operation's completion.
        [delegate sensorOperationCompleted:[[request.userInfo objectForKey:@"opType"] intValue] 
                                  fromLink:self 
                                sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]
                                withResult:self.currentWSBDResult];
        
        //cancel any sequence that was in progress.
        if (self.sequenceInProgress) {
            self.sequenceInProgress = kSensorSequenceNone; //stop the sequence, as we've got a failure.
            [delegate sequenceDidFail:self.sequenceInProgress
                             fromLink:self
                           withResult:self.currentWSBDResult
                        sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]
             ];
        }

        
        //Fire sensorOperationWasCancelled* in the delegate, and pass the opType
        //of the *cancelled* operation. 
        if (operationPendingCancellation >= 0) {
            [delegate sensorOperationWasCancelledByClient:operationPendingCancellation fromLink:self sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]];
        }

    }
    else {
        [self sensorOperationFailed:request];
        
        if (self.sequenceInProgress) {
            self.sequenceInProgress = kSensorSequenceNone; //stop the sequence, as we've got a failure.
            [delegate sequenceDidFail:self.sequenceInProgress
                             fromLink:self
                           withResult:self.currentWSBDResult
                        sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]
             ];
        }

    }
    operationInProgress = -1;
    operationPendingCancellation = -1; //we've finished our attempt to cancel the specified operation.
}

#pragma mark -
#pragma mark Client-managed NETWORK OPERATION cancellation stuff.
//NOTE: This is NOT the WS-BD Cancel code. This is a failsafe to allow you to essentially
//kill everything in the network queue and start over.

//This will generally be called to kill long-running operations that don't hit the sensor;
//for example, download operations that are taking too long because of the chosen size or
//network constraints.
-(void) cancelAllOperations
{
	NSLog(@"Cancelling all queued operations.");
	[networkQueue cancelAllOperations];
	[delegate sensorOperationWasCancelledByClient:kOpTypeAll fromLink:self sourceObjectID:nil];
}

//This will generally be called after retrieving the matching request from the
//ASINetworkQueue (say, to match an existing download operation).
-(void) cancelOperation:(ASIHTTPRequest*)request
{
	NSLog(@"Cancelling operation %@",request);
	[request cancel];
	[delegate sensorOperationWasCancelledByClient:[[request.userInfo objectForKey:@"opType"] intValue] fromLink:self sourceObjectID:[request.userInfo objectForKey:kDictKeySourceID]];
}

#pragma mark -
#pragma mark ASIHTTP delegate methods
-(BOOL) parseResultData:(NSMutableData*)parseableData
{
	//NSLog(@"Parsing result data after completed connection");
	
	//stop the network activity indicator
	[[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
	
	//make sure we got XML rather than an XHTML-formatted error back
	NSString *checkReturnData = [[NSString alloc] initWithData:parseableData encoding:NSUTF8StringEncoding];
    
	if ([checkReturnData rangeOfString:@"<!DOCTYPE HTML" options:(NSCaseInsensitiveSearch)].location != NSNotFound ||
        [checkReturnData rangeOfString:@"<HTML" options:(NSCaseInsensitiveSearch)].location != NSNotFound
        ) {
		//then the call is returning some HTML, which pretty much means something's wrong.
		//For now, just log that error and return.
		NSLog(@"Got an unexpected (but non-connection-error-y) result: %@",checkReturnData);
		return NO;
	}
	
	//TESTING ONLY: Do a raw data dump.
	//NSLog(@"Raw data is:\n%@",[[[NSString alloc] initWithData:parseableData encoding:NSUTF8StringEncoding] autorelease] );
	
	//Parse the returned XML and place it in the parseResult object
	NSXMLParser *parser = [[NSXMLParser alloc] initWithData:parseableData];
	if (parser == nil) {
		return YES; //nothing to do.
	}
	[parser setDelegate:self];
	[parser setShouldProcessNamespaces:NO];
	[parser setShouldResolveExternalEntities:NO]; //just get the data.
	
	[parser parse];
    
    //TESTING ONLY: Print the status and message.
    NSLog(@"Resulting status is %@",[WSBDResult stringForStatusValue:self.currentWSBDResult.status]);
    NSLog(@"Resulting message is %@",self.currentWSBDResult.message);
        
    return YES;
}

- (void)requestStarted:(ASIHTTPRequest *)request
{
	//NSLog(@"Network request started by queue.");
	[responseData setLength:0];
}

- (void)request:(ASIHTTPRequest *)request didReceiveData:(NSData *)data
{
	[responseData appendData:data];
}

-(void) requestFailed:(ASIHTTPRequest*)request
{
	NSLog(@"Network request failed with message: %@",request.error);

	//stop the network activity indicator
	[[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
	
	//notify whatever method was specified to receive notification that the connection is done.
	[self sensorOperationFailed:request];
    
    //if we were in a sequence, stop it.
    self.sequenceInProgress = kSensorSequenceNone;
	
}
 
//these are set manually for the cancel request.
- (void)cancelRequestStarted:(ASIHTTPRequest *)request
{
    //NSLog(@"Network request started by queue.");
    [cancelResponseData setLength:0];
}
 
-(void) cancelRequest:(ASIHTTPRequest *)request didReceiveData:(NSData *)data
{
    [cancelResponseData appendData:data];
}
 
-(void) cancelRequestFailed:(ASIHTTPRequest*)request
{
    NSLog(@"Cancel request failed with message: %@",request.error);
    
    //stop the network activity indicator
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
    
    //notify whatever method was specified to receive notification that the connection is done.
    [self sensorOperationFailed:request];
    
}


#pragma mark -
#pragma mark NSXMLParser delegate methods
#pragma mark NSXMLParserDelegate methods -- based on http://www.iphonedevsdk.com/forum/iphone-sdk-development/2841-resolved-how-call-soap-service-3.html
- (void)parserDidStartDocument:(NSXMLParser *)parser
{
	self.currentWSBDResult = nil;
	self.currentContainerArray = nil;
	self.currentContainerDictionary = nil;
	self.currentDictionaryKey = nil;
	self.currentDictionaryValue = nil;

	self.currentElementName=@"";
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
	self.currentElementValue=@""; //clear this so that we can fill it with data from this element.
	self.currentElementName = elementName;
    self.currentElementAttributes = attributeDict;
	
	if ([elementName localizedCaseInsensitiveCompare:@"result"] == NSOrderedSame)
	{
		self.currentWSBDResult = [[WSBDResult alloc] init];
	}
	else if ([elementName localizedCaseInsensitiveCompare:@"metadata"] == NSOrderedSame) {
		self.currentWSBDResult.downloadMetadata = [[NSMutableDictionary alloc] init];
		self.currentContainerDictionary = self.currentWSBDResult.downloadMetadata;
	}
	else if ([elementName localizedCaseInsensitiveCompare:@"configuration"] == NSOrderedSame) {
		self.currentWSBDResult.config = [[NSMutableDictionary alloc] init];
		self.currentContainerDictionary = self.currentWSBDResult.config;
	}
	else if ([elementName localizedCaseInsensitiveCompare:@"captureIds"] == NSOrderedSame) {
		self.currentWSBDResult.captureIds = [[NSMutableArray alloc] init];
		self.currentContainerArray = self.currentWSBDResult.captureIds;
	}
	
	//set up a new dictionary item, and flush any existing related placeholders
	else if ([elementName localizedCaseInsensitiveCompare:@"item"] == NSOrderedSame) {
		self.currentDictionaryKey = nil;
		self.currentDictionaryValue = nil;
        self.currentWSBDParameter = nil;
	}
    
	else if ([elementName localizedCaseInsensitiveCompare:@"value"] == NSOrderedSame)
	{
        //If we're inside a metadata element, this is a WSBDParameter
        if (self.currentContainerDictionary == self.currentWSBDResult.downloadMetadata) {
            self.currentWSBDParameter = [[WSBDParameter alloc] init];
        }
    }	
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
	self.currentElementValue=string;
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{     
	
	if ([elementName localizedCaseInsensitiveCompare:@"result"] == NSOrderedSame)
	{
		//we're done. Nothing to do here.
	}
	
	else if ([elementName localizedCaseInsensitiveCompare:@"sensorData"] == NSOrderedSame) {
		//decode and store the results
		[Base64Coder initialize];
		self.currentWSBDResult.downloadData = [Base64Coder decode:self.currentElementValue];

	}
	//Dictionary elements
	else if ([elementName localizedCaseInsensitiveCompare:@"key"] == NSOrderedSame)
	{
		self.currentDictionaryKey = self.currentElementValue;
	}
	else if ([elementName localizedCaseInsensitiveCompare:@"value"] == NSOrderedSame)
	{
  		self.currentDictionaryValue = self.currentElementValue;

        //We also need to clear the current WSBDParameter value here.
        self.currentWSBDParameter = nil;
	}
	else if ([elementName localizedCaseInsensitiveCompare:@"item"] == NSOrderedSame)
	{
		[self.currentContainerDictionary setObject:self.currentDictionaryValue forKey:self.currentDictionaryKey];
	}
	
	//array elements
	else if ([elementName localizedCaseInsensitiveCompare:@"element"] == NSOrderedSame)
	{
		[self.currentContainerArray addObject:self.currentElementValue];
	}
	
	else if ([elementName localizedCaseInsensitiveCompare:@"status"] == NSOrderedSame)
	{
		//create a StatusValue based on the string value of this element.
		//NOTE: Pretty clumsy.  Fix?
		StatusValue tempValue = -1;
		if ([self.currentElementValue localizedCaseInsensitiveCompare:@"Success"] == NSOrderedSame) {
			tempValue = StatusSuccess;
		}
		else if ([self.currentElementValue localizedCaseInsensitiveCompare:@"Failure"] == NSOrderedSame) {
			tempValue = StatusFailure;
		}
		else if ([self.currentElementValue localizedCaseInsensitiveCompare:@"InvalidId"] == NSOrderedSame) {
			tempValue = StatusInvalidId;
		}
		else if ([self.currentElementValue localizedCaseInsensitiveCompare:@"Cancelled"] == NSOrderedSame) {
			tempValue = StatusCancelled;
		}
		else if ([self.currentElementValue localizedCaseInsensitiveCompare:@"CancelledWithSensorFailure"] == NSOrderedSame) {
			tempValue = StatusCancelledWithSensorFailure;
		}
		else if ([self.currentElementValue localizedCaseInsensitiveCompare:@"SensorFailure"] == NSOrderedSame) {
			tempValue = StatusSensorFailure;
		}
		else if ([self.currentElementValue localizedCaseInsensitiveCompare:@"LockNotHeld"] == NSOrderedSame) {
			tempValue = StatusLockNotHeld;
		}
		else if ([self.currentElementValue localizedCaseInsensitiveCompare:@"LockHeldByAnother"] == NSOrderedSame) {
			tempValue = StatusLockHeldByAnother;
		}
		else if ([self.currentElementValue localizedCaseInsensitiveCompare:@"SensorNeedsInitialization"] == NSOrderedSame) {
			tempValue = StatusSensorNeedsInitialization;
		}
		else if ([self.currentElementValue localizedCaseInsensitiveCompare:@"SensorNeedsConfiguration"] == NSOrderedSame) {
			tempValue = StatusSensorNeedsConfiguration;
		}
		else if ([self.currentElementValue localizedCaseInsensitiveCompare:@"SensorBusy"] == NSOrderedSame) {
			tempValue = StatusSensorBusy;
		}
		else if ([self.currentElementValue localizedCaseInsensitiveCompare:@"SensorTimeout"] == NSOrderedSame) {
			tempValue = StatusSensorTimeout;
		}
		else if ([self.currentElementValue localizedCaseInsensitiveCompare:@"Unsupported"] == NSOrderedSame) {
			tempValue = StatusUnsupported;
		}
		else if ([self.currentElementValue localizedCaseInsensitiveCompare:@"BadValue"] == NSOrderedSame) {
			tempValue = StatusBadValue;
		}
		else if ([self.currentElementValue localizedCaseInsensitiveCompare:@"NoSuchParameter"] == NSOrderedSame) {
			tempValue = StatusNoSuchParameter;
		}
		else if ([self.currentElementValue localizedCaseInsensitiveCompare:@"PreparingDownload"] == NSOrderedSame) {
			tempValue = StatusPreparingDownload;
		}
		self.currentWSBDResult.status = tempValue;
	}
	else if ([elementName localizedCaseInsensitiveCompare:@"sessionId"] == NSOrderedSame)
	{
		self.currentWSBDResult.sessionId = self.currentElementValue;
	}
	else if ([elementName localizedCaseInsensitiveCompare:@"message"] == NSOrderedSame)
	{
		self.currentWSBDResult.message = self.currentElementValue;
	}
	else if ([elementName localizedCaseInsensitiveCompare:@"contentType"] == NSOrderedSame)
	{
		self.currentWSBDResult.contentType = self.currentElementValue;
	}
    
    /****Parameter values****/
    else if (self.currentWSBDParameter && [elementName localizedCaseInsensitiveCompare:@"name"] == NSOrderedSame)
    {
        self.currentWSBDParameter.name = self.currentElementValue;
    }
    else if (self.currentWSBDParameter && [elementName localizedCaseInsensitiveCompare:@"type"] == NSOrderedSame)
    {
        self.currentWSBDParameter.type = self.currentElementValue;
    }
    else if (self.currentWSBDParameter && [elementName localizedCaseInsensitiveCompare:@"readOnly"] == NSOrderedSame)
    {
        self.currentWSBDParameter.readOnly = ([self.currentElementValue localizedCaseInsensitiveCompare:@"true"] == NSOrderedSame);
    }

    else if (self.currentWSBDParameter && [elementName localizedCaseInsensitiveCompare:@"defaultValue"] == NSOrderedSame)
    {
        NSString *typeString = nil;
        for (NSString *key in self.currentElementAttributes.allKeys) {
            if ([key localizedCaseInsensitiveCompare:@"type"] == NSOrderedSame) {
                typeString = [self.currentElementAttributes objectForKey:key];
            }
        }
        
        //Get the converted object and store it.
        self.currentWSBDParameter.defaultValue = [NBCLXMLMap objcObjectForXML:currentElementValue ofType:typeString];
                
    }

    else if (self.currentWSBDParameter && [elementName localizedCaseInsensitiveCompare:@"allowedValue"] == NSOrderedSame)
    {
        NSString *typeString = nil;
        for (NSString *key in self.currentElementAttributes.allKeys) {
            if ([key localizedCaseInsensitiveCompare:@"type"] == NSOrderedSame) {
                typeString = [self.currentElementAttributes objectForKey:key];
            }
        }
        
        //if necessary, create the array we're about to add to.
        if (!self.currentWSBDParameter.allowedValues) {
            self.currentWSBDParameter.allowedValues = [[NSMutableArray alloc] init];
        }
        //Get the converted object and store it.
        [self.currentWSBDParameter.allowedValues addObject:[NBCLXMLMap objcObjectForXML:currentElementValue ofType:typeString]];

    }

	self.currentElementName=@"";
    self.currentElementAttributes = nil;
}

@end
