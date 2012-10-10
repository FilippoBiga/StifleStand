//
//  SSAppDelegate.h
//  StifleStand
//
//  Created by Filippo Bigarella on 08/10/12.
//  Copyright (c) 2012 Filippo Bigarella. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MobileDevice.h"

@interface SSAppDelegate : NSObject <NSApplicationDelegate>
{
    NSWindow *_window;
    NSButton *_button;
    NSTextField *_statusField;
}


-(IBAction)buttonClicked:(id)sender;

@property (assign) IBOutlet NSWindow *window;
@property (assign) IBOutlet NSButton *button;
@property(assign) IBOutlet NSTextField *statusField;



@end
