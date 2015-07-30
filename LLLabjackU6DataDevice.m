//
//  LLLabjackU6DataDevice.m
//  LablibLabjackU6
//
//  Created by Supratim Ray on 12/05/15.
//  Copyright (c) 2015 Supratim Ray. All rights reserved.
//

/*

//  LabjackU6 has 14 single-ended analog inputs and 20 digital I/O channels. We use the analog inputs in differential mode, such that we only have 7 Sampledata channels. We use 16 digital channels for sending digital words to other data acquisition systems and controlling the reward circuit (FIO-0to7 and EIO-0to7). Therefore we only have 4 Timestamp data channels (CIO0-3).
 
//  We allow different sampling rates on different sampling channels. This is achieved by sampling at the maximum requested rate and then throwing out samples that are not needed, similar to the approach used in ITC18. Read LLITCDataDevice.m for details.
*/

#import "LLLabjackU6DataDevice.h"
#import <Lablib/LLSystemUtil.h>
#import <Lablib/LLPluginController.h>
//#import "labjackusb.h"

NSString *LLLabjackU6InvertBit00Key = @"LLLabjackU6InvertBit00";
NSString *LLLabjackU6InvertBit15Key = @"LLLabjackU6InvertBit15";

enum {kSampleTable = 0, kTimestampTable};

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
        closeUSBConnection(labjack);
        free(labjack);
        labjack = nil;
        [deviceLock unlock];
    }
}

- (void)configure;
{
    [self setDataEnabled:[NSNumber numberWithBool:NO]];
    [NSApp runModalForWindow:settingsWindow];
    [settingsWindow orderOut:self];
    [self loadInstructions];
}

- (void)dealloc;
{
    long index;
    
    [self closeLabjackU6];
    for (index = 0; index < kLLLabjackU6ADChannels; index++) {
        [sampleData[index] release];
    }
    for (index = 0; index < kLLLabjackU6DigitalBits; index++) {
        [timestampData[index] release];
    }

    [sampleLock release];
    [timestampLock release];
    [monitor release];
    [deviceLock release];
    [topLevelObjects release];
    [super dealloc];
}

- (void)digitalOutputBits:(unsigned long)bits;
{
    short invertBit00, invertBit15;
    
    if (labjack != nil) {
        invertBit00 = [[NSUserDefaults standardUserDefaults] integerForKey:LLLabjackU6InvertBit00Key];
        invertBit15 = [[NSUserDefaults standardUserDefaults] integerForKey:LLLabjackU6InvertBit15Key];
        digitalOutputWord = bits;
        if (invertBit00) {
            digitalOutputWord ^= 0x0001;
        }
        if (invertBit15) {
            digitalOutputWord ^=  0x8000;
        }
        [deviceLock lock];
//        ITC18_WriteAuxiliaryDigitalOutput(itc, digitalOutputWord);
        NSLog(@"writing bits: %ld",digitalOutputWord);
        [deviceLock unlock];
    }
}

- (void)digitalOutputBitsOff:(unsigned long)bits;
{
    short invertBit00, invertBit15;
    
    if (labjack != nil) {
        invertBit00 = [[NSUserDefaults standardUserDefaults] integerForKey:LLLabjackU6InvertBit00Key];
        invertBit15 = [[NSUserDefaults standardUserDefaults] integerForKey:LLLabjackU6InvertBit15Key];
        digitalOutputWord &= ~bits;
        if (invertBit00 && (bits & 0x0001)) {
            digitalOutputWord ^= 0x0001;
        }
        if (invertBit15 && (bits & 0x8000)) {
            digitalOutputWord ^= 0x8000;
        }
        [deviceLock lock];
//        ITC18_WriteAuxiliaryDigitalOutput(itc, digitalOutputWord);
        NSLog(@"writing bits: %ld",digitalOutputWord);
        [deviceLock unlock];
    }
}

- (void)digitalOutputBitsOn:(unsigned long)bits;
{
    short invertBit00, invertBit15;
    
    if (labjack != nil) {
        invertBit00 = [[NSUserDefaults standardUserDefaults] integerForKey:LLLabjackU6InvertBit00Key];
        invertBit15 = [[NSUserDefaults standardUserDefaults] integerForKey:LLLabjackU6InvertBit15Key];
        digitalOutputWord |= bits;
        if (invertBit00 && (bits & 0x0001)) {
            digitalOutputWord ^= 0x0001;
        }
        if (invertBit15 && (bits & 0x8000)) {
            digitalOutputWord ^= 0x8000;
        }
        [deviceLock lock];
//        ITC18_WriteAuxiliaryDigitalOutput(itc, digitalOutputWord);
        NSLog(@"writing bits: %ld",digitalOutputWord);
        [deviceLock unlock];
    }
}

- (void)disableSampleChannels:(NSNumber *)bitPattern;
{
    [super disableSampleChannels:bitPattern];
    [self loadInstructions];
}

// Initialization tests for the existence of the LabjackU6, and initializes it if it is there.
// The Labjack initialization sets thd AD voltages.

- (void)doInitializationWithDevice:(long)requestedNum;
{
    long index;
//    int ranges[kLLLabjackU6ADChannels];
    long channel;
    float period;
    NSUserDefaults *defaults;
    NSString *defaultsPath;
    NSDictionary *defaultsDict;
    NSString *sampleKey = @"LLLabjackU6SamplePeriodMS";
    NSString *timestampKey = @"LLLabjackU6TimestampPeriodMS";
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
    for (index = 0; index < kLLLabjackU6DigitalBits; index++) {
        timestampData[index] = [[NSMutableData alloc] initWithLength:0];
    }
    
    // Load sampling values
    
    for (channel = 0; channel < kLLLabjackU6ADChannels; channel++)  {
        keySuffix = [NSString stringWithFormat:@"%1ld", channel];
        period = [defaults floatForKey:[sampleKey stringByAppendingString:keySuffix]];
        [samplePeriodMS addObject:[NSNumber numberWithFloat:period]];
    }
    for (channel = 0; channel < kLLLabjackU6DigitalBits; channel++)  {
        keySuffix = [NSString stringWithFormat:@"%02ld", channel];
        period = [defaults floatForKey:[timestampKey stringByAppendingString:keySuffix]];
        [timestampPeriodMS addObject:[NSNumber numberWithFloat:period]];
    }
    
    labjack = nil;
    sampleLock = [[NSLock alloc] init];
    timestampLock = [[NSLock alloc] init];
    deviceLock = [[NSLock alloc] init];
    monitor = [[LLLabjackU6Monitor alloc] initWithID:[self name] description:@"Labjack U6 I/O"];
    [self allocateSampleBuffer:&samples size:kMinSampleBuffer];
    if ([self openLabjackU6:deviceNum]) {
//        for (index = 0; index < ITC18_AD_CHANNELS; index++) {	// Set AD voltage range
//            ranges[index] = ITC18_AD_RANGE_10V;
//        }
//        ITC18_SetRange(itc, ranges);
//        ITC18_SetDigitalInputMode(itc, YES, NO);				// latch and do not invert
        [self loadInstructions];
        [self digitalOutputBits:0xffff];
    }
    [[NSBundle bundleForClass:[self class]] loadNibNamed:@"LLLabjackU6DataSettings" owner:self topLevelObjects:&topLevelObjects];
    [topLevelObjects retain];
}

- (void)enableSampleChannels:(NSNumber *)bitPattern;
{
    [super enableSampleChannels:bitPattern];
    [self loadInstructions];
}

- (void)enableTimestampChannels:(NSNumber *)bitPattern;
{
    [super enableTimestampChannels:bitPattern];
    [self loadInstructions];
}

- (int)getAvailable;
{
    int available, overflow;
    
//    ITC18_GetFIFOReadAvailableOverflow(itc, &available, &overflow);
    if (overflow != 0) {
        NSRunAlertPanel(@"LLLabjackU6DataDevice",  @"Fatal error: FIFO overflow", @"OK", nil, nil);
        exit(0);
    }
    return available;
}

- (id)init;
{
    if ((self = [super init]) != nil) {
        [self doInitializationWithDevice:LabjackU6Count++];
    }
    return self;
}

// Initialize with a particular LabjackU6 device, rather than the default

- (id)initWithDevice:(long)requestedNum;
{
    if ((self = [super init]) != nil) {
        deviceNum = requestedNum;
        [self doInitializationWithDevice:deviceNum];
    }
    return self;
}

- (HANDLE)labjack;
{
    return labjack;
}

/*
 Construct and load the ITC18 instruction set, setting the associated variables.  There are three different
 situations that generate different instructions sets: no digital sampling, digital sampling at less than
 1/4 the fastest AD sampling, and digital sampling equal or greater than the fastest AD sampling rate
 */

- (void)loadInstructions;
{
/*
    long channel, c, d;
    long enabledADChannels, maxADRateHz, maxDigitalRateHz, ADPerDigital;
    float channelPeriodMS;
    int ADCommands[] = {ITC18_INPUT_AD0, ITC18_INPUT_AD1, ITC18_INPUT_AD2, ITC18_INPUT_AD3,
        ITC18_INPUT_AD4, ITC18_INPUT_AD5, ITC18_INPUT_AD6, ITC18_INPUT_AD7};
    
    // If no channels are enabled load do-nothing instructions
    
    if (sampleChannels == 0 && timestampChannels == 0) {
        for (c = 0; c < kLLITC18ADChannels; c++) {
            instructions[c] = ITC18_INPUT_SKIP;
        }
        numInstructions = kLLITC18ADChannels;
        if (itc != nil) {
            ITC18_SetSequence(itc, numInstructions, instructions);
        }
        return;
    }
    
    // Find the fastest AD and digital sampling rates
    
    maxADRateHz = maxDigitalRateHz = enabledADChannels = 0;
    if (sampleChannels > 0) {
        for (channel = 0; channel < kLLITC18ADChannels; channel++) {
            if (sampleChannels & (0x01 << channel)) {
                enabledADChannels++;
                channelPeriodMS = [[samplePeriodMS objectAtIndex:channel] floatValue];
                maxADRateHz = MAX(round(1000.0 / channelPeriodMS), maxADRateHz);
            }
        }
    }
    if (timestampChannels > 0) {
        for (channel = 0; channel < kLLITC18DigitalBits; channel++) {
            if (timestampChannels & (0x01 << channel)) {
                //				channelTicksPerMS = [[timestampTicksPerMS objectAtIndex:channel] longValue];
                channelPeriodMS = [[timestampPeriodMS objectAtIndex:channel] floatValue];
                timestampTickS[channel] = 0.001 * channelPeriodMS;
                maxDigitalRateHz = MAX(1000.0 / channelPeriodMS, maxDigitalRateHz);
            }
        }
    }
    
    // NB: No new values are read into the ITC until a command with the ITC18_INPUT_UPDATE bit
    // set is read.  This applies to the digital input lines as well as the AD lines.  For this
    // reason, every digital input command must have the update bit set.   FURTHERMORE, it is
    // essential that none of the AD read commands does an update unless no digital sampling is
    // occuring.  If it does, it will cause the digital values to be updated, clearing any latched bits.
    //  When the next digital read command goes, its update will cause the a new digital word to be read,
    // so that any previously latched values that were updated by the Analog read command would be lost.
    
    
    // If digital sampling is not rate determining, then we simply make a chunk of data that includes
    // one sample for each active channel
    
    numInstructions = 0;
    
    if (maxDigitalRateHz * kDigitalOverSample < maxADRateHz) {
        if (maxDigitalRateHz > 0) {
            instructions[numInstructions++] = ITC18_INPUT_DIGITAL;
        }
        for (channel = 0; channel < kLLITC18ADChannels; channel++) {
            if (sampleChannels & (0x01 << channel)) {
                instructions[numInstructions++] = ADCommands[channel];
            }
        }
        instructions[0] |= ITC18_INPUT_UPDATE | ITC18_OUTPUT_TRIGGER;
    }
    
    // If digital sampling is rate determining, then we make a chuck that includes enough digital samples
    // to achieve the required oversampling, with the active AD channels embedded between the digital samples
    
    else {
        ADPerDigital = (enabledADChannels + 3) / kDigitalOverSample;
        channel = 0;
        for (d = 0; d < kDigitalOverSample; d++) {
            instructions[numInstructions++] = ITC18_INPUT_DIGITAL | ITC18_INPUT_UPDATE | ITC18_OUTPUT_TRIGGER;
            for (c = 0; c < ADPerDigital; c++) {
                while (channel < kLLITC18ADChannels && (!(sampleChannels & (0x01 << channel)))) {
                    channel++;
                }
                instructions[numInstructions++] = (channel < kLLITC18ADChannels) ? ADCommands[channel] : ITC18_INPUT_SKIP;
                channel++;
            }
        }
    }
    if (itc != nil) {
        ITC18_SetSequence(itc, numInstructions, instructions);
    }
    ITCTicksPerInstruction = chunksAtOneTickPerInstructHz / MAX(maxDigitalRateHz, maxADRateHz);
    ITCSamplePeriodS = (numInstructions * ITCTicksPerInstruction) / (kLLITC18TicksPerMS * 1000.0);
    
    // When we change the instructions, we change the maximum sampling rate.  Make sure that all the sampling
    // rates are attainable
    
    for (channel = 0; channel <  kLLITC18ADChannels; channel++) {
        if (![self setSamplePeriodMS:[[samplePeriodMS objectAtIndex:channel] floatValue] channel:channel]) {
            [self setSamplePeriodMS:(1000.0 / maxSampleRateHz) channel:channel];
        }
    }
    for (channel = 0; channel <  kLLITC18DigitalBits; channel++) {
        if (![self setTimestampPeriodMS:[[timestampPeriodMS objectAtIndex:channel] floatValue] channel:channel]) {
            [self setTimestampPeriodMS:(1000.0 / maxSampleRateHz) channel:channel];
        }
    }
 */
    NSLog(@"Loading instructions");
}

- (id <LLMonitor>)monitor;
{
    return monitor;
}

- (NSString *)name;
{
    return @"LabjackU6";
}

- (int)numberOfRowsInTableView:(NSTableView *)tableView;
{
    if ([tableView tag] == kSampleTable) {
        return kLLLabjackU6ADChannels;
    }
    else if ([tableView tag] == kTimestampTable) {
        return kLLLabjackU6DigitalBits;
    }
    else {
        return 0;
    }
}

- (IBAction)ok:(id)sender;
{
    [NSApp stopModal];
}

// Open and initialize the ITC18

- (BOOL)openLabjackU6:(long)devNum;
{
    NSLog(@"Opening LabjackU6...");
    
    labjack = openUSBConnection(-1);
/*
    long code;
    long interfaceCodes[] = {0x0, USB18_CL};
    
    [deviceLock lock];
    if (itc == nil) {						// currently opened?
        if ((itc = malloc(ITC18_GetStructureSize())) == nil) {
            [deviceLock unlock];
            NSRunAlertPanel(@"LLITC18IODevice",  @"Failed to allocate pLocal memory.", @"OK", nil, nil);
            exit(0);
        }
    }
    else {
        ITC18_Close(itc);
    }
    
    // Now the ITC is closed, and we have a valid pointer
    
    for (code = 0, devicePresent = NO; code < sizeof(interfaceCodes) / sizeof(long); code++) {
        NSLog(@"LLITC18DataDevice: attempting to initialize device %ld using code %ld",
              devNum, devNum | interfaceCodes[code]);
        if (ITC18_Open(itc, devNum | interfaceCodes[code]) != noErr) {
            continue;									// failed, try another code
        }
        
        // the ITC has opened, now initialize it
        
        if (ITC18_Initialize(itc, ITC18_STANDARD) != noErr) {
            ITC18_Close(itc);							// failed, close to try again
        }
        else {
            USB18 = interfaceCodes[code] == USB18_CL;
            devicePresent = YES;						// successful initialization
            break;
        }
    }
    if (!devicePresent) {
        free(itc);
        itc = nil;
    }
    else {
        NSLog(@"LLITC18DataDevice: succeeded initialize device %ld using code %ld",
              devNum, devNum | interfaceCodes[code]);
    }
    [deviceLock unlock];
 */
    return devicePresent;
}

- (void)readData;
{
}

- (void)setDataEnabled:(NSNumber *)state;
{
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(int)row;
{
    unsigned long rows, enabledBits;
    NSArray *valueArray;
    
    if ([tableView tag] == kSampleTable) {
        rows = kLLLabjackU6ADChannels;
        valueArray = samplePeriodMS;
        enabledBits = sampleChannels;
    }
    else if ([tableView tag] == kTimestampTable) {
        rows = kLLLabjackU6DigitalBits;
        valueArray = timestampPeriodMS;
        enabledBits = timestampChannels;
    }
    else {
        return nil;
    }
    NSParameterAssert(row >= 0 && row < rows);
    if ([[tableColumn identifier] isEqual:@"enabled"]) {
        return [NSNumber numberWithBool:((enabledBits & (0x1 << row)) > 0)];
    }
    if ([[tableColumn identifier] isEqual:@"channel"]) {
        return [NSNumber numberWithInt:row];
    }
    if ([[tableColumn identifier] isEqual:@"periodMS"]) {
        return [valueArray objectAtIndex:row];
    }
    if ([[tableColumn identifier] isEqual:@"timestampPeriodMS"]) {
        return [valueArray objectAtIndex:row];
    }
    return @"???";
}

// This method is called when the user has put a new entry in the sample or timestamp tables in the
// settings dialog.

- (void)tableView:(NSTableView *)aTableView setObjectValue:(id)anObject
   forTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex;
{
    unsigned long rows, *pBits;
    
    if ([aTableView tag] == kSampleTable) {
        rows = kLLLabjackU6ADChannels;
        pBits = &sampleChannels;
    }
    else if ([aTableView tag] == kTimestampTable) {
        rows = kLLLabjackU6DigitalBits;
        pBits = &timestampChannels;
    }
    else {
        return;
    }
    NSParameterAssert(rowIndex >= 0 && rowIndex < rows);
    if ([[aTableColumn identifier] isEqual:@"enabled"]) {
        if ([anObject boolValue]) {
            *pBits |= (0x01 << rowIndex);
        }
        else {
            *pBits &= ~(0x01 << rowIndex);
        }
    }
    else if ([[aTableColumn identifier] isEqual:@"periodMS"]) {
        [self setSamplePeriodMS:[anObject floatValue] channel:rowIndex];
    }
    else if ([[aTableColumn identifier] isEqual:@"timestampPeriodMS"]) {
        [self setTimestampPeriodMS:[anObject floatValue] channel:rowIndex];
    }
}

- (NSData **)timestampData;
{
    long channel;
    
    if (labjack == nil) {
        return nil;
    }
    [self readData];									// read data from LabjackU6
    [timestampLock lock];								// check whether there are timestamps to return
    for (channel = 0; channel < kLLLabjackU6DigitalBits; channel++) {
        if ([timestampData[channel] length] > 0) {
            timestampResults[channel] = [NSData dataWithData:timestampData[channel]];
            [timestampData[channel] setLength:0];
        }
        else {
            timestampResults[channel] = nil;
        }
    }
    [timestampLock unlock];
    return timestampResults;								// return samples
}

@end
