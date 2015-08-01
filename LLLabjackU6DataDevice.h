//
//  LLLabjackU6DataDevice.h
//  LablibLabjackU6
//
//  Created by Supratim Ray on 12/05/15.
//  Copyright (c) 2015 Supratim Ray. All rights reserved.

// For compatibility, the coding style is similar to LLITC18

#ifndef LablibLabjackU6_LLLabjackU6DataDevice_h
#define LablibLabjackU6_LLLabjackU6DataDevice_h

# import <Lablib/LLDataDevice.h>
# import "LLLabjackU6Monitor.h"
#import "u6.h"

#define kMaxInstructions 			12
#define kMinSampleBuffer			8192

#endif

@interface LLLabjackU6DataDevice : LLDataDevice {
    
    NSLock				*deviceLock;
    long				deviceNum;
    unsigned long		digitalOutputWord;
    BOOL				justStartedLabjackU6;
    HANDLE				labjack;
    double				LabjackSamplePeriodS;
    long				LabjackTicksPerInstruction;
    double				lastReadDataTimeS;
    LLLabjackU6Monitor	*monitor;
    double              monitorStartTimeS;
    double				nextSampleTimeS[kLLLabjackU6ADChannels];
    long				numInstructions;
    short				*samples;
    NSMutableData		*sampleData[kLLLabjackU6ADChannels];
    NSLock				*sampleLock;
    NSData				*sampleResults[kLLLabjackU6ADChannels];
    double				sampleTimeS;
    unsigned short		timestampActiveBits;
    NSMutableData		*timestampData[kLLLabjackU6DigitalBits];
    NSLock				*timestampLock;
    NSData				*timestampResults[kLLLabjackU6DigitalBits];
    double				timestampTickS[kLLLabjackU6DigitalBits];
    NSArray             *topLevelObjects;
    BOOL				USB18;
    LabjackU6MonitorValues	values;
    
    IBOutlet NSWindow 	*settingsWindow;
}

- (void)allocateSampleBuffer:(short **)ppBuffer size:(long)sizeInShorts;
- (void)closeLabjackU6;
- (int)getAvailable;
- (id)initWithDevice:(long)deviceNum;
- (HANDLE)labjack;
//- (void)loadInstructions;
- (id <LLMonitor>)monitor;
- (BOOL)openLabjackU6:(long)deviceNum;
- (void)readData;
@end
