//
//  LLITCMonitorSettings.h
//  Lablib
//
//  Created by John Maunsell on Thu Jul 31 2003.
//  Copyright (c) 2003. All rights reserved.
//

@interface LLLabjackU6MonitorSettings : NSWindowController {

@private
	NSString *IDString;
    id monitor;
    
	IBOutlet NSButton	 	*resetButton;
    IBOutlet NSButton	 	*warnDriftButton;
	IBOutlet NSTextField	*driftLimitField;
}

- (id)initWithID:(NSString *)ID monitor:(id)monitorID;
- (NSString *)uniqueKey:(NSString *)commonKey;

- (IBAction)changeDoWarnDrift:(id)sender;
- (IBAction)changeDriftLimit:(id)sender;
- (IBAction)resetCounters:(id)sender;

@end
