//
//  LLLabjackU6DataDevice.h
//  LablibLabjackU6
//
//  Created by Supratim Ray on 12/05/15.
//  Copyright (c) 2015 Supratim Ray. All rights reserved.

// For compatibility, the coding style is similar to LLITC18

#ifndef LablibLabjackU6_LLLabjackU6DataDevice_h
#define LablibLabjackU6_LLLabjackU6DataDevice_h

# import <Lablib/Lablib.h>
# import "LLLabjackU6.h"

#define kMaxInstructions 			12
#define kMinSampleBuffer			8192

#endif

@interface LLLabjackU6DataDevice : LLDataDevice {
    
    NSLock				*deviceLock;
    long				deviceNum;
    unsigned long		digitalOutputWord;
    BOOL				justStartedLabjackU6;
    Ptr					labjack;
    double				LabjackSamplePeriodS;
    long				LabjackTicksPerInstruction;
    double				lastReadDataTimeS;
//    LLITCMonitor		*monitor;
//    double			monitorStartTimeS;
    double				nextSampleTimeS[kLLLabjackU6ADChannels];
    long				numInstructions;
    short				*samples;
    NSMutableData		*sampleData[kLLLabjackU6ADChannels];
    NSLock				*sampleLock;
    NSData				*sampleResults[kLLLabjackU6ADChannels];
    double				sampleTimeS;
    NSArray             *topLevelObjects;
    BOOL				USB18;
//    ITCMonitorValues	values;
    
}

- (void)allocateSampleBuffer:(short **)ppBuffer size:(long)sizeInShorts;
- (void)closeLabjackU6;
- (int)getAvailable;
- (id)initWithDevice:(long)deviceNum;
- (Ptr)itc;
- (void)loadInstructions;
- (id <LLMonitor>)monitor;
- (BOOL)openLabjackU6:(long)deviceNum;
- (void)readData;

@end
