/********* CDVAudioInputCapture.m Cordova Plugin Implementation *******/

#import <Cordova/CDV.h>
#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#include <limits.h>
#include <Accelerate/Accelerate.h>
#include <CoreFoundation/CFRunLoop.h>

@interface CDVAudioInputCapture : CDVPlugin {
}

@property (strong, nonatomic) AVAudioRecorder *audioRecorder;
@property (strong, nonatomic) NSURL* fileUrl;
@property (strong) NSString* callbackId;

- (void) initialize:(CDVInvokedUrlCommand*)command;
- (void) forceSpeaker:(CDVInvokedUrlCommand*)command;
- (void) deviceCurrentTime:(CDVInvokedUrlCommand*)command;
- (void) prepareToRecord:(CDVInvokedUrlCommand*)command;
- (void) record:(CDVInvokedUrlCommand*)command;
- (void) recordAtTime:(CDVInvokedUrlCommand*)command;
- (void) recordForDuration:(CDVInvokedUrlCommand*)command;
- (void) recordAtTimeForDuration:(CDVInvokedUrlCommand*)command;
- (void) pause:(CDVInvokedUrlCommand*)command;
- (void) stop:(CDVInvokedUrlCommand*)command;
- (void) deleteRecording:(CDVInvokedUrlCommand*)command;

@end

@implementation CDVAudioInputCapture

- (void)pluginInitialize
{
    // Empty
}

/**
 * Initialize the audio receiver
 */
- (void)initialize:(CDVInvokedUrlCommand*)command
{
    Float32 sampleRate = [[command.arguments objectAtIndex:0] intValue];
    UInt32 channels = [[command.arguments objectAtIndex:2] intValue];
    int audioSourceType = [[command.arguments objectAtIndex:4] intValue];
    NSString *fileUrl = [command.arguments objectAtIndex:5];
    self->_fileUrl = [NSURL URLWithString:fileUrl];
    if (self->_fileUrl.isFileURL) {
        NSLog(@"[INFO] iosaudiorecorder:temp file path: %@", [self->_fileUrl absoluteString]);
    }
    else {
        NSString *msg = [NSString stringWithFormat:@"Invalid file URL: %@", _fileUrl];
        [self sendError:msg callbackId:command.callbackId];
        return;
    }
    
    if (self.audioRecorder != nil) {
        self.audioRecorder = nil;
    }
    
    if (self->_fileUrl == nil || [self->_fileUrl isKindOfClass:[NSNull class]]) {
        [self sendError:@"missing fileUrl" callbackId:command.callbackId];
        return;
    }
    
    [self.commandDelegate runInBackground:^{
        AVAudioSession* avSession = [AVAudioSession sharedInstance];
        NSError *error = nil;
        if (![avSession setCategory:AVAudioSessionCategoryPlayAndRecord
                        withOptions:AVAudioSessionCategoryOptionMixWithOthers | AVAudioSessionCategoryOptionDefaultToSpeaker
                              error:&error]) {
            NSLog(@"[INFO] setCategory: error: %@", [error localizedDescription]);
            NSString *msg = [NSString stringWithFormat:@"AVAudioRecorder error: %@", [error localizedDescription]];
            [self sendError:msg callbackId:command.callbackId];
            return;
        }
        
        if(audioSourceType == 7)
            [avSession setMode:AVAudioSessionModeVoiceChat error:nil];
        else if(audioSourceType == 5)
            [avSession setMode:AVAudioSessionModeVideoRecording error:nil];
        else if(audioSourceType == 9)
            [avSession setMode:AVAudioSessionModeMeasurement error:nil];
        else
            [avSession setMode:AVAudioSessionModeDefault error:nil];
        
        NSDictionary *recordingSettings = @{AVFormatIDKey : @(kAudioFormatLinearPCM),
                                            AVNumberOfChannelsKey : @(channels),
                                            AVSampleRateKey : @(sampleRate),
                                            AVLinearPCMBitDepthKey : @(16),
                                            AVLinearPCMIsBigEndianKey : @NO,
                                            //AVLinearPCMIsNonInterleaved : @YES,
                                            AVLinearPCMIsFloatKey : @NO,
                                            AVEncoderAudioQualityKey : @(AVAudioQualityMax)
        };
        self.audioRecorder = [[AVAudioRecorder alloc] initWithURL:self->_fileUrl settings:recordingSettings error:&error];
        if (error) {
            NSLog(@"[INFO] iosaudiorecorder: error: %@", [error localizedDescription]);
            NSString *msg = [NSString stringWithFormat:@"AVAudioRecorder error: %@", [error localizedDescription]];
            [self sendError:msg callbackId:command.callbackId];
            return;
        }
        
        [self sendFilePath:command.callbackId];
    }];
}

- (void)checkMicrophonePermission:(CDVInvokedUrlCommand*)command
{
    BOOL hasPermission = FALSE;
    if ([[AVAudioSession sharedInstance] recordPermission] == AVAudioSessionRecordPermissionGranted) {
        hasPermission = TRUE;
    }
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:hasPermission];
    [result setKeepCallbackAsBool:NO];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (void)getMicrophonePermission:(CDVInvokedUrlCommand*)command
{
    [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
        NSLog(@"permission : %d", granted);
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:granted];
        [result setKeepCallbackAsBool:NO];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    }];
}

- (void) forceSpeaker:(CDVInvokedUrlCommand*)command
{
    if (self.audioRecorder == nil) {
        [self sendError:@"audioRecorder is nil, make sure you call initialize()" callbackId:command.callbackId];
        return;
    }
    [self.commandDelegate runInBackground:^{
        AVAudioSession *audioSession = [AVAudioSession sharedInstance];
        [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
        [audioSession overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];
        [self sendOK:command.callbackId];
    }];
}

- (void) deviceCurrentTime:(CDVInvokedUrlCommand*)command
{
    if (self.audioRecorder == nil) {
        [self sendError:@"audioRecorder is nil, make sure you call initialize()" callbackId:command.callbackId];
        return;
    }
    double time = [self.audioRecorder deviceCurrentTime];
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:time];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (void) prepareToRecord:(CDVInvokedUrlCommand*)command
{
    if (self.audioRecorder == nil) {
        [self sendError:@"audioRecorder is nil, make sure you call initialize()" callbackId:command.callbackId];
        return;
    }
    [self.commandDelegate runInBackground:^{
        [self.audioRecorder prepareToRecord];
        [self sendFilePath:command.callbackId];
    }];
}

- (void) record:(CDVInvokedUrlCommand*)command
{
    if (self.audioRecorder == nil) {
        [self sendError:@"audioRecorder is nil, make sure you call initialize()" callbackId:command.callbackId];
        return;
    }
    [self.commandDelegate runInBackground:^{
        [self.audioRecorder record];
        [self sendFilePath:command.callbackId];
    }];
}

- (void) recordAtTime:(CDVInvokedUrlCommand*)command
{
    if (self.audioRecorder == nil) {
        [self sendError:@"audioRecorder is nil, make sure you call initialize()" callbackId:command.callbackId];
        return;
    }
    double time = [[command.arguments objectAtIndex:0] doubleValue];
    [self.commandDelegate runInBackground:^{
        [self.audioRecorder recordAtTime:time];
        [self sendFilePath:command.callbackId];
    }];
}

- (void) recordForDuration:(CDVInvokedUrlCommand*)command
{
    if (self.audioRecorder == nil) {
        [self sendError:@"audioRecorder is nil, make sure you call initialize()" callbackId:command.callbackId];
        return;
    }
    double duration = [[command.arguments objectAtIndex:0] doubleValue];
    [self.commandDelegate runInBackground:^{
        [self.audioRecorder recordForDuration:duration];
        [self sendFilePath:command.callbackId];
    }];
}

- (void) recordAtTimeForDuration:(CDVInvokedUrlCommand*)command
{
    if (self.audioRecorder == nil) {
        [self sendError:@"audioRecorder is nil, make sure you call initialize()" callbackId:command.callbackId];
        return;
    }
    double time = [[command.arguments objectAtIndex:0] doubleValue];
    double duration = [[command.arguments objectAtIndex:1] doubleValue];
    [self.commandDelegate runInBackground:^{
        [self.audioRecorder recordAtTime:time forDuration:duration];
        [self sendFilePath:command.callbackId];
    }];
}

- (void) pause:(CDVInvokedUrlCommand*)command
{
    if (self.audioRecorder == nil) {
        [self sendError:@"audioRecorder is nil, make sure you call initialize()" callbackId:command.callbackId];
        return;
    }
    [self.commandDelegate runInBackground:^{
        [self.audioRecorder pause];
        [self sendOK:command.callbackId];
    }];
}

- (void) stop:(CDVInvokedUrlCommand*)command
{
    if (self.audioRecorder == nil) {
        [self sendError:@"audioRecorder is nil, make sure you call initialize()" callbackId:command.callbackId];
        return;
    }
    [self.commandDelegate runInBackground:^{
        [self.audioRecorder stop];
        [self sendFilePath:command.callbackId];
    }];
}

- (void) deleteRecording:(CDVInvokedUrlCommand*)command
{
    if (self.audioRecorder == nil) {
        [self sendError:@"audioRecorder is nil, make sure you call initialize()" callbackId:command.callbackId];
        return;
    }
    [self.commandDelegate runInBackground:^{
        [self.audioRecorder deleteRecording];
        [self sendOK:command.callbackId];
    }];
}

/*
- (void) stop:(CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{
        [self.audioRecorder stop];
        
        if (self.callbackId) {
            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:0.0f];
            [result setKeepCallbackAsBool:YES];
            [self.commandDelegate sendPluginResult:result callbackId:self.callbackId];
        }
        
        if (command != nil) {
            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:_fileUrl];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        }
        
        if (_fileUrl == nil) {
            self.callbackId = nil;
        }
    }];
}
*/

/*
 - (void)didEncounterError:(NSString*)msg
 {
 [self.commandDelegate runInBackground:^{
 @try {
 if (self.callbackId) {
 NSDictionary* errorData = [NSDictionary dictionaryWithObject:[NSString stringWithString:msg] forKey:@"error"];
 CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:errorData];
 [result setKeepCallbackAsBool:YES];
 [self.commandDelegate sendPluginResult:result callbackId:self.callbackId];
 }
 }
 @catch (NSException *exception) {
 if (self.callbackId) {
 CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
 messageAsString:@"Exception in didEncounterError"];
 [result setKeepCallbackAsBool:YES];
 [self.commandDelegate sendPluginResult:result callbackId:self.callbackId];
 }
 }
 }];
 }
 
 - (void)didFinish:(NSString*)url
 {
 [self.commandDelegate runInBackground:^{
 @try {
 if (self.callbackId) {
 NSDictionary* messageData = [NSDictionary dictionaryWithObject:[NSString stringWithString:url] forKey:@"file"];
 CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:messageData];
 [result setKeepCallbackAsBool:NO];
 [self.commandDelegate sendPluginResult:result callbackId:self.callbackId];
 self.callbackId = nil;
 }
 }
 @catch (NSException *exception) {
 if (self.callbackId) {
 CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
 messageAsString:@"Exception in didEncounterError"];
 [result setKeepCallbackAsBool:YES];
 [self.commandDelegate sendPluginResult:result callbackId:self.callbackId];
 }
 }
 }];
 }
 */

- (void)dealloc
{
    if (self.audioRecorder) {
        self.audioRecorder = nil;
    }
    [self stop:nil];
}

- (void)onReset
{
    [self stop:nil];
}

- (void) sendOK: (NSString*)callbackId
{
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:YES];
    [self.commandDelegate sendPluginResult:result callbackId:callbackId];
}

- (void) sendError:(NSString*)msg callbackId:(NSString*)callbackId
{
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:msg];
    [self.commandDelegate sendPluginResult:result callbackId:callbackId];
}

- (void) sendFilePath:(NSString*)callbackId
{
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:[_fileUrl absoluteString]];
    [self.commandDelegate sendPluginResult:result callbackId:callbackId];
}
@end
