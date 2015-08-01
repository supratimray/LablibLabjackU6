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
 
// 1 Aug 2015 - As of now only the digital ports have been configured for controlling the juice system and also send digital pulses. This works as long as eye data can be acquired from a separate source, such as an Eyelink.
*/

#import "LLLabjackU6DataDevice.h"
#import <Lablib/LLSystemUtil.h>
#import <Lablib/LLPluginController.h>

#define kUseLLDataDevices							// needed for versioning
/*
extern size_t malloc_size(void *ptr);

#define kIsDigitalInput(i)			((instructions[i] & ITC18_INPUT_DIGITAL) && (instructions[i] != ITC18_INPUT_SKIP))
#define kDigitalOverSample			4
#define kDriftTimeLimitMS			0.010
#define kDriftFractionLimit			0.001
#define kGarbageLength				3
#define	kReadDataIntervalS			(USB18 ? 0.005 : 0.000)

#define chunksAtOneTickPerInstructHz	(kLLITC18TicksPerMS * 1000.0 / numInstructions)
#define maxSampleRateHz					(chunksAtOneTickPerInstructHz / ITC18_MINIMUM_TICKS)
#define minSampleRateHz					(chunksAtOneTickPerInstructHz / ITC18_MAXIMUM_TICKS)
*/

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
        labjack = nil;
        [deviceLock unlock];
    }
}

- (void)configure;
{
    [self setDataEnabled:[NSNumber numberWithBool:NO]];
    [NSApp runModalForWindow:settingsWindow];
    [settingsWindow orderOut:self];
    [self ljU6ConfigDigitalPorts];
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
        [self ljU6WriteStrobedWord:digitalOutputWord];
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
        [self ljU6WriteStrobedWord:digitalOutputWord];
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
        [self ljU6WriteStrobedWord:digitalOutputWord];
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
        [self ljU6ConfigDigitalPorts];
        [self digitalOutputBits:0xffff];
        [self loadInstructions];
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
    int available, overflow=0;
    
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
    // Configure Labjack streaming mode based on the digital (CI0-3) and analog sampling rates
    [self ljU6ConfigStreaming];
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
    devicePresent = NO;
    
    if (devNum==0) {
        [deviceLock lock];
        if (labjack != NULL) {            // close if currently open
            closeUSBConnection(labjack);
        }
        labjack = openUSBConnection(-1); // Open the first found Labjack
        if (labjack != NULL) {
            NSLog(@" Labjack U6 opened successfully");
            devicePresent = YES;
        }
    }
    else {
        NSLog(@"This case is not supported yet. Todo: Find the local ID of the device and initialize using that..");
    }
    [deviceLock unlock];
    return devicePresent;
}

- (void)readData;
{
/*
    short index, bitIndex, sampleChannel, *pSamples;
    unsigned short whichBit, timestamp;
    long sets, set;
    BOOL bitOn;
    int available;
    
    // Don't attempt to read if we just read a little while ago
    
    if (lastReadDataTimeS + kReadDataIntervalS > [LLSystemUtil getTimeS]) {
        return;
    }
    
    if (![deviceLock tryLock]) {
        [deviceLock lock];			// Wait here for the lock, then check time again
        if (lastReadDataTimeS + kReadDataIntervalS > [LLSystemUtil getTimeS]) {
            [deviceLock unlock];
            return;
        }
    }
    
    // When a sequence is started, the first three entries in the FIFO are garbage.  They should be thrown out.
    
    if (justStartedITC18) {
        available = [self getAvailable];
        if (available < kGarbageLength + 1) {
            lastReadDataTimeS = [LLSystemUtil getTimeS];
            [deviceLock unlock];
            return;
        }
        ITC18_ReadFIFO(itc, kGarbageLength, samples);
        justStartedITC18 = NO;
    }
    
    // Unloading complete cycles of samples.  We gather all complete sets in one call to
    // ITC18_ReadFIFO, and we don't check again when we are done.  This is prevent overloading
    // the USB with frequent calls, which can happen if the sample sets are small and coming
    // in at a fast rate.  We need to leave it so that they can be read in large sets.
    
    available = [self getAvailable];
    if (available > numInstructions) {									// >, so ITC doesn't go empty
        sets = available / numInstructions;								// number of complete sets available
        if (numInstructions * sets * sizeof(short) > malloc_size(samples)) {
            [self allocateSampleBuffer:&samples size:numInstructions * sets];
        }
        ITC18_ReadFIFO(itc, numInstructions * sets, samples);			// read all available sets
        for (set = 0; set < sets; set++) {								// process each set
            pSamples = &samples[numInstructions * set];					// point to start of set
            for (index = sampleChannel = 0; index < numInstructions; index++) {	// for every instruction
                
                // If this is a digital input word, process as a timestamp
                
                if (kIsDigitalInput(index)) {								// digital input instruction
                    digitalInputBits = pSamples[index];						// save the digital input word
                    for (bitIndex = 0; bitIndex < kLLITC18DigitalBits; bitIndex++) { // check every bit
                        whichBit = (0x1 << bitIndex);						// get the bit pattern for one bit
                        if (whichBit & timestampChannels) {					// enabled bit?
                            bitOn = (whichBit & pSamples[index]); 			// bit on?
                            if (timestampActiveBits & whichBit) {			// was active
                                if (!bitOn) {								//  but now inactive
                                    timestampActiveBits &= ~whichBit;		//  so clear flag
                                }
                            }
                            else if (bitOn) {								// active now but was not before
                                timestampActiveBits |= whichBit;			// flag channel as active
                                values.timestampCount[bitIndex]++;			// increment timestamp count
                                [timestampLock lock];						// add to timestamp buffer
                                timestamp = round(sampleTimeS / timestampTickS[bitIndex]);
                                [timestampData[bitIndex] appendBytes:&timestamp length:sizeof(unsigned short)];
                                [timestampLock unlock];
                            }
                        }
                    }
                }
                
                // It's AD or a skipped sample.  If this is an A/D sample, save it (if it is enabled)
                
                else {
                    while (sampleChannel < kLLITC18ADChannels && !(sampleChannels & (0x1 << sampleChannel))) {
                        sampleChannel++;
                    }
                    if (sampleChannel < kLLITC18ADChannels && sampleTimeS >= nextSampleTimeS[sampleChannel]) {
                        [sampleLock lock];										// add to AD sample buffer
                        [sampleData[sampleChannel] appendBytes:&pSamples[index] length:sizeof(short)];
                        nextSampleTimeS[sampleChannel] += [[samplePeriodMS objectAtIndex:sampleChannel] floatValue] / 1000.0;
                        [sampleLock unlock];									// add to AD sample buffer
                    }
                    sampleChannel++;
                }
            }
            sampleTimeS += ITCSamplePeriodS;
            values.samples++; 
        }
    }
    lastReadDataTimeS = [LLSystemUtil getTimeS];
    [deviceLock unlock];
 */
}

- (void)setDataEnabled:(NSNumber *)state;
{
    int available;
    long channel;
    double channelPeriodMS;
    long maxSamplingRateHz;
    
    if (labjack == nil) {
        return;
    }
    if ([state boolValue] && !dataEnabled) {
        [deviceLock lock];
        
        // Scan through the sample and timestamp sampling settings, finding the fastest enabled rate.
        // The rate here is the requested sampling rate.  It does not take into account the need to
        // oversample digital inputs because that is built into the instruction sequence
        
        for (channel = maxSamplingRateHz = 0; channel < kLLLabjackU6ADChannels; channel++) {
            if (sampleChannels & (0x01 << channel)) {
                channelPeriodMS = [[samplePeriodMS objectAtIndex:channel] floatValue];
                nextSampleTimeS[channel] = channelPeriodMS / 1000.0;
                maxSamplingRateHz = MAX(1000.0 / channelPeriodMS, maxSamplingRateHz);
            }
        }
        for (channel = 0; channel < kLLLabjackU6DigitalBits; channel++) {
            if (timestampChannels & (0x01 << channel)) {
                channelPeriodMS = [[timestampPeriodMS objectAtIndex:channel] floatValue];
                timestampTickS[channel] = 0.001 * channelPeriodMS;
                maxSamplingRateHz = MAX(1000.0 / channelPeriodMS, maxSamplingRateHz);
            }
        }
        if (maxSamplingRateHz != 0) {							// no channels enabled
            sampleTimeS = LabjackSamplePeriodS;					// one period complete on first sample
            timestampActiveBits = 0x0;
            justStartedLabjackU6 = YES;
            [monitor initValues:&values];
            values.samplePeriodMS = LabjackSamplePeriodS * 1000.0;
            values.instructionPeriodMS = LabjackSamplePeriodS / numInstructions * 1000.0;
//            ITC18_SetSamplingInterval(itc, ITCTicksPerInstruction, false);
//            ITC18_StopAndInitialize(itc, YES, YES);
            monitorStartTimeS = [LLSystemUtil getTimeS];
//            ITC18_Start(itc, NO, NO, NO, NO);		// no trigger, no output, no stopOnOverflow, (reserved)
            dataEnabled = YES;
            lastReadDataTimeS = 0;
        }
        [deviceLock unlock];
    }
    else if (![state boolValue] && dataEnabled) {
        [deviceLock lock];
//        ITC18_Stop(itc);										// stop the ITC18
        [deviceLock unlock];
        values.cumulativeTimeMS = ([LLSystemUtil getTimeS] - monitorStartTimeS) * 1000.0;
        
        // Check whether the number of samples collected is what is predicted based on the elapsed time.
        // This is a check for drift between the computer clock and the LabjackU6 clock.  The first step
        // is to drain any complete sample sets from the FIFO.  Then we see how many instructions
        // remain in the FIFO (as an incomplete sample set).
        
        lastReadDataTimeS = 0;									// permit a FIFO read
        [self readData];										// drain FIFO
        [deviceLock lock];
        available = [self getAvailable];
        [deviceLock unlock];
        values.sequences = 1;
        values.instructions = values.samples * numInstructions + available;
        if (values.instructions == 0) {
            NSLog(@" ");
            NSLog(@"WARNING: LLLabjackU6: values.instructions == 0");
            NSLog(@"sequenceStartTimeS: %f", monitorStartTimeS);
            NSLog(@"time now: %f", [LLSystemUtil getTimeS]);
            NSLog(@"justStartedITC18: %d", justStartedLabjackU6);
            NSLog(@"dataEnabled: %d", dataEnabled);
            NSLog(@"values.cumulativeTimeMS: %f", values.cumulativeTimeMS);
            NSLog(@"values.samples: %ld", values.samples);
            NSLog(@"values.samplePeriodMS: %f", values.samplePeriodMS);
            NSLog(@"values.instructions: %ld", values.instructions);
            NSLog(@"values.instructionPeriodMS: %f", values.instructionPeriodMS);
            NSLog(@"values.sequences: %ld", values.sequences);
            NSLog(@" ");
        }
        else {
            [monitor sequenceValues:values];
        }
        dataEnabled = NO;
    }
}

- (NSData **)sampleData;
{
    long channel;
    
    if (labjack == nil) {
        return nil;
    }
    [self readData];								// read data from ITC18
    [sampleLock lock];								// check whether there are samples to return
    for (channel = 0; channel < kLLLabjackU6ADChannels; channel++) {
        if ([sampleData[channel] length] > 0) {
            sampleResults[channel] = [NSData dataWithData:sampleData[channel]];
            [sampleData[channel] setLength:0];
        }
        else {
            sampleResults[channel] = nil;
        }
    }
    [sampleLock unlock];
    return sampleResults;								// return samples
}

/*
// Overload the methods for changing sampling rates to make sure that the value is allowed by
// the limits on the sampling rate

- (BOOL)setSamplePeriodMS:(float)newPeriodMS channel:(long)channel;
{
    float newRateHz = 1000.0 / newPeriodMS;
    
    if (newRateHz >= minSampleRateHz && newRateHz <= maxSampleRateHz) {
        return [super setSamplePeriodMS:newPeriodMS channel:channel];
    }
    else {
        return NO;
    }
}

- (BOOL)setTimestampTicksPerMS:(long)newTicksPerMS channel:(long)channel;
{
    float newRateHz = newTicksPerMS * 1000;
    
    if (newRateHz >= minSampleRateHz && newRateHz <= maxSampleRateHz) {
        return [super setTimestampTicksPerMS:newTicksPerMS channel:channel];
    }
    else {
        return NO;
    }
}
 */

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


//////////////////////// Labajck Low Level Functions //////////////////////////////
-(void)ljU6ConfigStreaming;
{
    // Use streamConfig function (see 5.2.12 in U6 User Manual
}

-(void)ljU6ConfigDigitalPorts;
{
    /// set up IO ports
    uint8 sendDataBuff[7];
    uint8 Errorcode, ErrorFrame;
    
    // Setup FIO as output.
    //       EIO as output
    //       CIO as input
    
    sendDataBuff[0] = 29;       // PortDirWrite
    sendDataBuff[1] = 0xff;     // update mask for FIO: update all
    sendDataBuff[2] = 0xff;     // update mask for EIO
    sendDataBuff[3] = 0x0f;     // update mask for CIO (only 4 bits)
    
    sendDataBuff[4] = 0xff;
    sendDataBuff[5] = 0xff;
    sendDataBuff[6] = 0x00;
    
    if(ehFeedback(labjack, sendDataBuff, 7, &Errorcode, &ErrorFrame, NULL, 0) < 0) {
        NSLog(@"bug: ehFeedback error, see stdout");  // note we will get a more informative error on stdout
    }
    if(Errorcode) {
        NSLog(@"ehFeedback: error with command, errorcode was %d",Errorcode);
    }
}

- (void)ljU6WriteStrobedWord:(unsigned long)inWord;          // Copied and subsequently modified from LabjackU6 MWorks Plugin
{

    uint8 outFioBits = inWord & 0x00ff;       // Bits 0-7
    uint8 outEioBits = (inWord & 0xff00) >> 8;  // Bits 8-15
    
    uint8 sendDataBuff[7];
    uint8 Errorcode, ErrorFrame;
    
    if (inWord > 0xffff) {
        NSLog(@"LLLabjackU6IODevice: error writing strobed word; value is larger than 16 bits");
    }
    
//    NSLog(@"FIO: %d, EIO: %d",outFioBits,outEioBits);
/*
    sendDataBuff[0] = 29;			// PortDirWrite - for some reason the above seems to reset the FIO input/output state
    sendDataBuff[1] = 0xff;         //  FIO: update
    sendDataBuff[2] = 0xff;         //  EIO: update
    sendDataBuff[3] = 0x0f;         //  CIO: update
    sendDataBuff[4] = 0xff;         //  FIO hardcoded above
    sendDataBuff[5] = 0xff;         //  EIO hardcoded above
    sendDataBuff[6] = 0x00;         //  CIO hardcoded above
    
    sendDataBuff[7] = 27;			// PortStateWrite, 7 bytes total
    sendDataBuff[8] = 0xff;			// FIO: update
    sendDataBuff[9] = 0xff;			// EIO: update
    sendDataBuff[10] = 0x00;		// CIO: don't update
    sendDataBuff[11] = outFioBits;	// FIO: data
    sendDataBuff[12] = outEioBits;	// EIO: data
    sendDataBuff[13] = 0x00;        // CIO: data
*/
    sendDataBuff[0] = 27;			// PortStateWrite, 7 bytes total
    sendDataBuff[1] = 0xff;			// FIO: update
    sendDataBuff[2] = 0xff;			// EIO: update
    sendDataBuff[3] = 0x00;         // CIO: don't update
    sendDataBuff[4] = outFioBits;	// FIO: data
    sendDataBuff[5] = outEioBits;	// EIO: data
    sendDataBuff[6] = 0x00;         // CIO: data
    
    if(ehFeedback(labjack, sendDataBuff, 7, &Errorcode, &ErrorFrame, NULL, 0) < 0) {
        NSLog(@"bug: ehFeedback error, see stdout");  // note we will get a more informative error on stdout
    }
    if(Errorcode) {
        NSLog(@"ehFeedback: error with command, errorcode was %d",Errorcode);
    }
}

@end