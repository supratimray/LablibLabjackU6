//
//  LLLabjackU6DataDevice.m
//  LablibLabjackU6
//
//  Created by Supratim Ray on 12/05/15.
//  Copyright (c) 2015 Supratim Ray. All rights reserved.
//

/*

//  LabjackU6 has 14 single-ended analog inputs and upto 20 digital I/O channels. We use the analog inputs in differential mode, such that we only have 7 Sampledata channels. For now digital channels are used only for sending digital words to other data acquisition systems and controlling the reward circuit, so we do not have any Timestamp data channels.
 
//  We allow different sampling rates on different sampling channels. This is achieved by sampling at the maximum requested rate and then throwing out samples that are not needed, similar to the approach used by ITC18.

*/

#import "LLLabjackU6DataDevice.h"

#define kUseLLDataDevices							// needed for versioning

static long	LabjackU6Count = 0;

@implementation LLLabjackU6DataDevice

+ (NSInteger)version;
{
    return kLLPluginVersion;
}

- (void)allocateSampleBuffer:(short **)ppBuffer size:(long)sizeInShorts;
{
    if (*ppBuffer == nil) {
        *ppBuffer = malloc(sizeof(short) * sizeInShorts);
    }
    else {
        *ppBuffer = reallocf(*ppBuffer, sizeof(short) * sizeInShorts);
    }
    if (*ppBuffer == nil) {
        NSRunAlertPanel(@"LLLabjackU6IODevice",  @"Fatal error: Could not allocate sample memory.",
                        @"OK", nil, nil);
        exit(0);
    }
}

// Close the Labjack.

- (void)closeLabjackU6 {
    
    if (labjack != nil) {
        [deviceLock lock];
//        ITC18_Close(itc);
        free(labjack);
        labjack = nil;
        [deviceLock unlock];
    }
}

/////////////////////////////
// Write Method: configure
/////////////////////////////

- (void)dealloc;
{
    long index;
    
//    [self closeITC18];
    for (index = 0; index < kLLLabjackU6ADChannels; index++) {
        [sampleData[index] release];
    }

    [sampleLock release];
//    [monitor release];
    [deviceLock release];
    [topLevelObjects release];
    [super dealloc];
}

/////////////////////////////
// Write Method: - (void)digitalOutputBits:(unsigned long)bits;
/////////////////////////////

/////////////////////////////
// Write Method: - (void)digitalOutputBitsOff:(unsigned long)bits;
/////////////////////////////

/////////////////////////////
// Write Method: - (void)digitalOutputBitsOn:(unsigned long)bits;
/////////////////////////////

/////////////////////////////
// Write Method: - (void)disableSampleChannels:(NSNumber *)bitPattern;
/////////////////////////////

/////////////////////////////
// Write Method: - (void)doInitializationWithDevice:(long)requestedNum;
/////////////////////////////

- (void)disableSampleChannels:(NSNumber *)bitPattern;
{
    [super disableSampleChannels:bitPattern];
    [self loadInstructions];
}

// Initialization tests for the existence of the ITC, and initializes it if it is there.
// The ITC initialization sets thd AD voltage, and also set the digital input to latch.
// ITC-18 latching is not the same thing as edge triggering.  A short pulse will produce a positive
// value at the next read, but a steady level can also produce a series of positive values.

- (void)doInitializationWithDevice:(long)requestedNum;
{
    long index;
    long channel;
    float period;
    NSUserDefaults *defaults;
    NSString *defaultsPath;
    NSDictionary *defaultsDict;
    NSString *sampleKey = @"LLLabjackU6SamplePeriodMS";
    NSString *keySuffix;
    
    deviceNum = (requestedNum >= 0) ? requestedNum : LabjackU6Count;
    NSLog(@"attempting to initialize LabjackU6 device %ld", deviceNum);
    
    // Register default sampling values
    
    defaultsPath = [[NSBundle bundleForClass:[self class]] pathForResource:@"LLLabjackU6DataDevice" ofType:@"plist"];
    defaultsDict = [NSDictionary dictionaryWithContentsOfFile:defaultsPath];
    defaults = [NSUserDefaults standardUserDefaults];
    [defaults registerDefaults:defaultsDict];
    
    // Initialize data buffers
    
    for (index = 0; index < kLLLabjackU6ADChannels; index++) {
        sampleData[index] = [[NSMutableData alloc] initWithLength:0];
    }
    
    // Load sampling values
    
    for (channel = 0; channel < kLLLabjackU6ADChannels; channel++)  {
        keySuffix = [NSString stringWithFormat:@"%1ld", channel];
        period = [defaults floatForKey:[sampleKey stringByAppendingString:keySuffix]];
        [samplePeriodMS addObject:[NSNumber numberWithFloat:period]];
    }

    labjack = nil;
    sampleLock = [[NSLock alloc] init];
    deviceLock = [[NSLock alloc] init];
//    monitor = [[LLITCMonitor alloc] initWithID:[self name] description:@"Instrutech ITC-18 Lab I/O"];
    [self allocateSampleBuffer:&samples size:kMinSampleBuffer];
/*
    if ([self openLabjackU6:deviceNum]) {
        for (index = 0; index < ITC18_AD_CHANNELS; index++) {	// Set AD voltage range
            ranges[index] = ITC18_AD_RANGE_10V;
        }
        ITC18_SetRange(itc, ranges);
        ITC18_SetDigitalInputMode(itc, YES, NO);				// latch and do not invert
        [self loadInstructions];
        [self digitalOutputBits:0xffff];
    }
 
    [[NSBundle bundleForClass:[self class]] loadNibNamed:@"LLLabjackU6DataSettings" owner:self
                                         topLevelObjects:&topLevelObjects];
    [topLevelObjects retain];
 */
}

- (void)enableSampleChannels:(NSNumber *)bitPattern;
{
    [super enableSampleChannels:bitPattern];
    [self loadInstructions];
}

- (id)init;
{
    if ((self = [super init]) != nil) {
        [self doInitializationWithDevice:LabjackU6Count++];
    }
    return self;
}

// Do the initialize with a particular LabjackU6 device, rather than the default

- (id)initWithDevice:(long)requestedNum;
{
    if ((self = [super init]) != nil) {
        deviceNum = requestedNum;
        [self doInitializationWithDevice:deviceNum];
    }
    return self;
}

- (NSString *)name;
{
    return @"LabjackU6";
}

@end
