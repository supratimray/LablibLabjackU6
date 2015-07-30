//
//  LLITCMonitor.h
//  Lablib
//
//  Created by John Maunsell on Wed Jan 29 2003.
//  Copyright (c) 2003 . All rights reserved.

// Modified from LLITCMonitor.h by Supratim Ray 24/7/15

#import "LLLabjackU6.h"
#import "LLLabjackU6MonitorSettings.h"
#import <Lablib/LLMonitor.h>
//#import <Lablib/LLIODevice.h>

extern NSString	*doWarnDriftKey;
extern NSString	*driftLimitKey;

typedef struct {
	short 	ADMaxValues[kLLLabjackU6ADChannels];
	short 	ADMinValues[kLLLabjackU6ADChannels];
	double	cumulativeTimeMS;							// duration of sequence based on CPU clock
	long	samples;									// number of sample sets collected
    double	samplePeriodMS;								// period for one sample set
    long	instructions;								// number of sampling instructions completed
    double	instructionPeriodMS;						// period for one instruction
	long 	sequences;
	long	timestampCount[kLLLabjackU6DigitalBits];
} LabjackU6MonitorValues;

@interface  LLLabjackU6Monitor : NSObject <LLMonitor> {
@private
	BOOL                        alarmActive;
	LabjackU6MonitorValues      cumulative;
	NSString                    *descriptionString;				// First line in report
	NSString                    *IDString;						// Short string for menu entry
	LabjackU6MonitorValues      previous;
	double                      samplePeriodMS;
	double                      sequenceStartTimeMS;			// start of current sequence
	LLLabjackU6MonitorSettings	*settings;
}

- (void)doAlarm:(NSString *)message;
- (void)initValues:(LabjackU6MonitorValues *)pValues;
- (id)initWithID:(NSString *)ID description:(NSString *)description;
- (void)resetCounters;
- (void)sequenceValues:(LabjackU6MonitorValues)current;
- (BOOL)success;
- (NSString *)valueString:(LabjackU6MonitorValues *)pValues;
- (NSString *)uniqueKey:(NSString *)commonKey;

@end


