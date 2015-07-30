//
//  LLITCMonitor.m
//  Lablib
//
//  Created by John Maunsell on Wed Jan 29 2003.
//  Copyright (c) 2003. All rights reserved.
//

#import "LLLabjackU6Monitor.h"
#import <Lablib/LLSystemUtil.h>

NSString *doWarnDriftKey = @"LL LabjackU6 Do Warn Drift";
NSString *driftLimitKey = @"LL LabjackU6 Drift Limit";

@implementation LLLabjackU6Monitor

- (void)checkWarnings;
{
    double LabjackU6MS, CPUMS, driftParts;
    
    if (![self success]) {
        LabjackU6MS = previous.instructions * previous.instructionPeriodMS;
        CPUMS = previous.cumulativeTimeMS;
        driftParts = ((LabjackU6MS + CPUMS) / 2)/(CPUMS - LabjackU6MS);
		NSLog(@"Warning: LabjackU6 clock drift is %@1 tick per %.0f relative to computer.",
					driftParts >= 0 ? @"+" : @"-", fabs(driftParts));
		NSLog(@"previous.sequences: %ld", previous.sequences);
		NSLog(@"previous.instructions: %ld", previous.instructions);
		NSLog(@"previous.instructionPeriodMS: %f", previous.instructionPeriodMS);
		NSLog(@"previous.cumulativeTimeMS: %f", previous.cumulativeTimeMS);
        [self doAlarm:[NSString stringWithFormat:@"Warning: LabjackU6 clock drift is %@1 tick per %.0f relative to computer.",
				driftParts >= 0 ? @"+" : @"-", fabs(driftParts)]];
	}
}

- (void)configure {

	[settings showWindow:self];
}

- (void)dealloc {

	[descriptionString release];
	[IDString release];
	[settings release];
	[super dealloc];
}

- (void)doAlarm:(NSString *)message;
{
	long choice;
    NSAlert *theAlert = [[NSAlert alloc] init];
    
	alarmActive = YES;
    [theAlert setMessageText:[NSString stringWithFormat:@"LLLabjackU6Monitor (%@)", [self IDString]]];
    [theAlert addButtonWithTitle:@"OK"];
    [theAlert addButtonWithTitle:@"Disarm Alarm"];
    [theAlert addButtonWithTitle:@"Change Settings"];
    [theAlert setInformativeText:message];
	choice = [theAlert runModal];
	switch (choice) {
        case NSAlertSecondButtonReturn:						// disarm alarms
            [[NSUserDefaults standardUserDefaults] setBool:NO forKey:[self uniqueKey:doWarnDriftKey]];
            break;
        case NSAlertThirdButtonReturn:
            [self configure];								// configure alarms
            break;
        case NSAlertFirstButtonReturn:						// OK button, do nothing
        default:
            break;
	}
	alarmActive = NO;
    [theAlert release];
}

- (NSString *)IDString {

	return IDString;
}

- (id)initWithID:(NSString *)ID description:(NSString *)description {

    NSMutableDictionary *defaultSettings;

    if ((self = [super init]) != Nil) {

// ID must be set up before doing the default settings

		[ID retain];
		IDString = ID;
		[description retain];
		descriptionString = description;

// Set up all the default settings

		defaultSettings = [[NSMutableDictionary alloc] init];
		[defaultSettings setObject:[NSNumber numberWithBool:YES] forKey:[self uniqueKey:doWarnDriftKey]];
		[defaultSettings setObject:[NSNumber numberWithInt:100] forKey:[self uniqueKey:driftLimitKey]];
		[[NSUserDefaults standardUserDefaults] registerDefaults:defaultSettings];
		[defaultSettings release];

// Default settings should be done before initializing values

		settings = [[LLLabjackU6MonitorSettings alloc] initWithID:IDString monitor:self];
		[self initValues:&cumulative];
	}
    return self;
}

- (void)initValues:(LabjackU6MonitorValues *)pValues {

	long index;
	
	pValues->samples = pValues->instructions = pValues->sequences = 0;
    pValues->cumulativeTimeMS = 0.0;
	for (index = 0; index < kLLLabjackU6DigitalBits; index++) {
		pValues->timestampCount[index] = 0;
	}
	for (index = 0; index < kLLLabjackU6ADChannels; index++) {
		pValues->ADMaxValues[index] = SHRT_MIN;
		pValues->ADMinValues[index] = SHRT_MAX;
	}
}

- (BOOL)isConfigurable {

	return YES;
}

- (NSAttributedString *)report {

	NSMutableString *textString;
    NSDictionary *attr;

	textString = [[[NSMutableString alloc] initWithString:descriptionString] autorelease];

	if (cumulative.sequences == 0) {
		[textString appendString:@"\n\n(No data sequences have been compiled)"];
	}
	else {
		[textString appendString:[NSString stringWithFormat:@"\n\n%ld sampling sequences completed\n\n", 
			cumulative.sequences]];
		if (previous.samples > 0) {
			[textString appendString:@"Last Sequence:\n\n"];
			[textString appendString:[self valueString:&previous]];
		}
		[textString appendString:@"All Sequences:\n\n"];
		[textString appendString:[self valueString:&cumulative]];
	}
    attr = [[[NSDictionary alloc] initWithObjectsAndKeys:
                    [NSFont userFixedPitchFontOfSize:10], NSFontAttributeName,
                    nil] autorelease];
	return [[[NSAttributedString alloc] initWithString:textString attributes:attr] autorelease];
}

- (void)resetCounters {

    [self initValues:&cumulative];
	[[NSNotificationCenter defaultCenter] postNotificationName:LLMonitorUpdated object:self];
}

- (NSString *)valueString:(LabjackU6MonitorValues *)pValues {

    long index;
    double LabjackU6MS, CPUMS;
    NSMutableString *string = [[NSMutableString alloc] init];
    
    LabjackU6MS = pValues->instructions * pValues->instructionPeriodMS;
    CPUMS = pValues->cumulativeTimeMS;
	[string appendString:[NSString stringWithFormat:
                @" Did %.0f ms of samples in %.0f ms (%.1f ms difference, 1:%.0f; ", 
                LabjackU6MS, CPUMS, CPUMS - LabjackU6MS, ((LabjackU6MS + CPUMS) / 2)/(CPUMS - LabjackU6MS)]];
	[string appendString:[NSString stringWithFormat:
                @"%.3f-%.3f ms period)\n\n Channel:", 
                pValues->cumulativeTimeMS / (pValues->samples + pValues->sequences), 
                pValues->cumulativeTimeMS / pValues->samples]];
    for (index = 0; index < kLLLabjackU6DigitalBits; index++) {
        if (pValues->timestampCount[index] > 0) {
            [string appendString:[NSString stringWithFormat:@" %8ld", index]];
        }
    }
    [string appendString:@"\n  Counts:"];
    for (index = 0; index < kLLLabjackU6DigitalBits; index++) {
        if (pValues->timestampCount[index] > 0) {
            [string appendString:[NSString stringWithFormat:@" %8ld", pValues->timestampCount[index]]];
        }
    }
    [string appendString:@"\n   Per S:"];
    for (index = 0; index < kLLLabjackU6DigitalBits; index++) {
        if (pValues->timestampCount[index] > 0) {
            [string appendString:[NSString stringWithFormat:@" %8.1f", pValues->timestampCount[index] /
                pValues->cumulativeTimeMS * 1000.0]];
        }
    }
    [string appendString:@"\n\n"];

    return [NSString stringWithString:string];
}

// Record the occurrence of an event.  This is the method that should be called 
// when the event being monitored occurs.

- (void)sequenceValues:(LabjackU6MonitorValues)current {

    long index;
    
	previous = current;									// Save for the report
    cumulative.samplePeriodMS = current.samplePeriodMS;
    cumulative.instructionPeriodMS = current.instructionPeriodMS;
    
	cumulative.sequences += current.sequences;
	cumulative.cumulativeTimeMS += current.cumulativeTimeMS;
	cumulative.samples += current.samples;
    cumulative.instructions += current.instructions;
    
	for (index = 0; index < kLLLabjackU6DigitalBits; index++) {
		cumulative.timestampCount[index] += current.timestampCount[index];
	}
	for (index = 0; index < kLLLabjackU6ADChannels; index++) {
		cumulative.ADMaxValues[index] = MAX(cumulative.ADMaxValues[index], current.ADMaxValues[index]);
		cumulative.ADMinValues[index] = MIN(cumulative.ADMinValues[index], current.ADMinValues[index]);
	}

	[self checkWarnings];
	[[NSNotificationCenter defaultCenter] postNotificationName:LLMonitorUpdated object:self];
}

- (BOOL)success;
{
    double LabjackU6MS, CPUMS, driftParts;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    if (![defaults boolForKey:[self uniqueKey:doWarnDriftKey]] || previous.sequences < 1) {
        return YES;
    }
    LabjackU6MS = previous.instructions * previous.instructionPeriodMS;
    CPUMS = previous.cumulativeTimeMS;
    driftParts = ((LabjackU6MS + CPUMS) / 2)/(CPUMS - LabjackU6MS);
    return (fabs(driftParts) >= [defaults integerForKey:[self uniqueKey:driftLimitKey]]);
}
// Because there may be many instances of some objects, we save using keys that are made
// unique by prepending the IDString

- (NSString *)uniqueKey:(NSString *)commonKey {

	return [NSString stringWithFormat:@"%@ %@", IDString, commonKey]; 
}

@end
