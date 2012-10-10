//
//  SSAppDelegate.m
//  StifleStand
//
//  Created by Filippo Bigarella on 08/10/12.
//  Copyright (c) 2012 Filippo Bigarella. All rights reserved.
//

#import "SSAppDelegate.h"
#include <sys/socket.h>

#define SS_DEBUG

void amdevice_Callback(struct am_device_notification_callback_info *info, void *context);


//kern_return_t send_message(void *socket, CFPropertyListRef plist);
//CFPropertyListRef receive_message(void *socket);

// we use these instead of the private routines above
bool send_xml_message(service_conn_t connection, CFDictionaryRef dict);
CFPropertyListRef receive_xml_reply(service_conn_t connection, CFStringRef *error);


void hide_newsstand(struct am_device *device);

static SSAppDelegate *delegateInstance = nil;
static struct am_device *device;
static BOOL foundDevice = NO;


@implementation SSAppDelegate

@synthesize window=_window, button=_button, statusField=_statusField;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    
#ifdef SS_DEBUG
    AMDSetLogLevel(INT_MAX);
    AMDAddLogFileDescriptor(fileno(stdout));
    #define DLog(...)   NSLog(__VA_ARGS__)
#else
    #define DLog(...)
#endif
    
    delegateInstance = self;
    
    am_device_notification *notification;
    
    AMDeviceNotificationSubscribe(amdevice_Callback, 0, 0, NULL, &notification);
    
    [self.button setEnabled:NO];
}


-(IBAction)buttonClicked:(id)sender
{
    if (device == NULL)
    {
        DLog(@"device is NULL!");
        [self updateLabel:@"Is the device still there?"];
    }
    
    hide_newsstand(device);
}


-(void)updateLabel:(NSString *)str
{
    self.statusField.stringValue = str;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app
{
	return YES;
}


- (void)dealloc
{
    if (device != NULL)
    {
        AMDeviceRelease(device);
        AMDeviceStopSession(device);
        AMDeviceDisconnect(device);
        
        device = NULL;
    }
    
    delegateInstance = nil;
    [super dealloc];
}


@end


void amdevice_Callback(struct am_device_notification_callback_info *info, void *context)
{        
    switch (info->msg)
    {
        case ADNCI_MSG_CONNECTED:
        {
            DLog(@"ADNCI_MSG_CONNECTED");

            if (foundDevice)
                return;

            device = info->dev;

            if (AMDeviceConnect(device) == MDERR_OK)
            {
                if (AMDeviceIsPaired(device) && (AMDeviceValidatePairing(device) == MDERR_OK))
                {
                    if (AMDeviceStartSession(device) == MDERR_OK)
                    {
                        DLog(@"Started session");
                        
                        CFStringRef name = (CFStringRef)AMDeviceCopyValue(device, 0, CFSTR("DeviceName"));

                        NSString *status = [NSString stringWithFormat:@"Device connected: %@", (NSString *)name];
                        
                        CFRelease(name);
                        
                        foundDevice = YES;
                        
                        AMDeviceRetain(device);
                        
                        [delegateInstance updateLabel:status];
                        [delegateInstance.button setEnabled:YES];
                    }
                }
            }
           
            break;
        }
            
        case ADNCI_MSG_DISCONNECTED:
        {
            DLog(@"ADNCI_MSG_DISCONNECTED");
            
            foundDevice = NO;

            AMDeviceRelease(device);
            AMDeviceStopSession(device);
            AMDeviceDisconnect(device);
            
            device = NULL;
            
            [delegateInstance updateLabel:@"No device connected"];
            [delegateInstance.button setEnabled:NO];
            
            break;
        }
            
        default:
        {
            DLog(@"amdevice_Callback: 0x%x", info->msg);
        }
            break;
    }
}


CFMutableArrayRef process_iconState(CFArrayRef iconState, int *didFindNewsstand)
{
    CFMutableArrayRef processedState = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    int foundNewsstand = 0;
    
    CFIndex outerIndex = 0;
    for (outerIndex = 0; outerIndex < CFArrayGetCount(iconState); outerIndex++)
    {
        CFArrayRef innerArray = CFArrayGetValueAtIndex(iconState, outerIndex);
        CFMutableArrayRef processedInnerArray = CFArrayCreateMutableCopy(kCFAllocatorDefault, 0, innerArray);
        
        CFIndex innerIndex = 0;
        for (innerIndex = 0; innerIndex < CFArrayGetCount(innerArray); innerIndex++)
        {
            CFMutableDictionaryRef iconDict =  CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0,
                                                                             CFArrayGetValueAtIndex(innerArray, innerIndex));
            CFStringRef listType;
            
            if (CFDictionaryGetValueIfPresent(iconDict, CFSTR("listType"), (const void **)&listType) &&
                CFStringCompare(listType, CFSTR("newsstand"), 0) == kCFCompareEqualTo)
            {
                DLog(@"Found Newsstand: (%ld,%ld)",outerIndex,innerIndex);
                foundNewsstand = 1;
                
                CFMutableDictionaryRef magicFolder = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                                                               &kCFTypeDictionaryKeyCallBacks,
                                                                               &kCFTypeDictionaryValueCallBacks);
                
                CFDictionarySetValue(magicFolder, CFSTR("displayName"), CFSTR("Magic"));
                CFDictionarySetValue(magicFolder, CFSTR("listType"), CFSTR("folder"));


                CFMutableArrayRef iconLists = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
                CFMutableArrayRef singleList = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
                
                CFArrayAppendValue(singleList, iconDict);
                CFArrayAppendValue(iconLists, singleList);
                
                CFDictionarySetValue(magicFolder, CFSTR("iconLists"), iconLists);
                
                CFArraySetValueAtIndex(processedInnerArray, innerIndex, magicFolder);
                
                CFRelease(iconLists);
                CFRelease(singleList);
                CFRelease(magicFolder);

            } else
            {
                CFDictionaryRemoveValue(iconDict, CFSTR("iconModDate"));
                CFArrayAppendValue(processedInnerArray, iconDict);
                
                CFRelease(iconDict);
            }
        }
        
        CFArrayAppendValue(processedState, processedInnerArray);
        
        CFRelease(processedInnerArray);
    }
    
    *didFindNewsstand = foundNewsstand;
    if (!foundNewsstand)
    {
        CFRelease(processedState);
        return NULL;
    }
    
    return processedState;
}



void hide_newsstand(struct am_device *device)
{
    CFStringRef error = NULL;
    service_conn_t connection;
    if (AMDeviceStartService(device, AMSVC_SPRINGBOARD_SERVICES, &connection, NULL) == MDERR_OK)
    {
        DLog(@"Started service %@", (NSString *)AMSVC_SPRINGBOARD_SERVICES);;
        
        CFMutableDictionaryRef dict = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                                                &kCFTypeDictionaryKeyCallBacks,
                                                                &kCFTypeDictionaryValueCallBacks);
        
        CFDictionarySetValue(dict, CFSTR("command"), CFSTR("getIconState"));
        CFDictionarySetValue(dict, CFSTR("formatVersion"), CFSTR("2"));
        
        DLog(@"Getting icon state from device");
        
        if (send_xml_message(connection, dict))
        {
            CFPropertyListRef reply = receive_xml_reply(connection, &error);
            
            if (reply)
            {
                DLog(@"Looking for Newsstand");
                
                CFArrayRef iconStateArray = (CFArrayRef)reply;
                int foundNewsstand = 0;
                
                CFMutableArrayRef processedState = process_iconState(iconStateArray, &foundNewsstand);
                
                if (foundNewsstand)
                {
                    CFDictionaryRemoveValue(dict, CFSTR("formatVersion"));
                    CFDictionarySetValue(dict, CFSTR("command"), CFSTR("setIconState"));
                    
                    CFDictionarySetValue(dict, CFSTR("iconState"), (CFPropertyListRef)processedState);
                    
                    CFRelease(processedState);                    
                    
                    if (send_xml_message(connection, dict))
                    {
                        CFPropertyListRef _repl = receive_xml_reply(connection, &error);
                        if (_repl)
                        {
                            CFShow(_repl);
                            CFRelease(_repl);
                        }
                        
                        if (error)
                        {
                            [delegateInstance updateLabel:@"Couldn't send icon state to the device!"];
                            CFRelease(error);
                            
                        } else {
                        
                            [delegateInstance updateLabel:@"Done!"];
                        }
                        
                        [delegateInstance.button setEnabled:NO];
                        
                    } else {
                        
                        [delegateInstance updateLabel:@"Failed to set icon state!"];
                    }
                    
                    
                } else {
                    
                    [delegateInstance updateLabel:@"Couldn't find Newsstand. Has it already been hidden?"];
                }
                
                CFRelease(reply);
                
            } else {
                
                if (error)
                {
                    DLog(@"Error receiving icon state from device: %@", (NSString *)error);
                    CFRelease(error);
                }

                [delegateInstance updateLabel:@"Couldn't get icon state!"];
            }
        }
        
        CFRelease(dict);
    }
}


bool send_xml_message(service_conn_t connection, CFDictionaryRef dict)
{
	bool result = false;
    if (!dict)
    {
        DLog(@"NULL dictionary passed to send_xml_message!");
        return result;
    }
    
    
    CFPropertyListRef msgData = CFPropertyListCreateData(NULL, dict, kCFPropertyListBinaryFormat_v1_0,0,NULL);
    
    if (!msgData)
    {
        DLog(@"Can't convert request to XML");
        return false;
    }
    
    CFIndex msgLen = CFDataGetLength(msgData);
    uint32_t size = htonl(msgLen);    
    
    
//    DLog(@"Sending msg:\n{ \n\tdata = [ %.*s ],\n\tlength = %ld", (int)msgLen, CFDataGetBytePtr(msgData), msgLen);
    DLog(@"Sending msg of length: %ld (size=%d)", msgLen, size);
    
    if (send((int)connection, &size, sizeof(uint32_t), 0) == sizeof(size))
    {
        ssize_t bytesSent = send((int)connection, CFDataGetBytePtr(msgData), msgLen, 0);
        NSLog(@"bytesSent: %ld\tmsgLen: %ld", bytesSent,msgLen);
        
        if (bytesSent == msgLen)
        {
            DLog(@"Message sent");
            result = true;
            
        } else {
            
            DLog(@"Can't send message data");
            result = false;
        }
        
    } else {
        
        DLog(@"Can't send message size");
        result = false;
    }
    
    CFRelease(msgData);
    return result;
}

CFPropertyListRef receive_xml_reply(service_conn_t connection, CFStringRef *error)
{
	CFPropertyListRef reply = NULL;
	int sock = (int)((uint32_t)connection);
	uint32_t size = 0;
    
    ssize_t rc = recv(sock, &size, sizeof(size), 0);
    
    if (rc != sizeof(uint32_t))
    {
        *error = CFStringCreateWithFormat(kCFAllocatorDefault, NULL,
                                          CFSTR("Couldn't receive reply size (rc=%ld, expected %ld)"), rc, sizeof(uint32));
        
        DLog(@"%@", *((NSString **)error));
        return NULL;
    }
    
    size = ntohl(size);
    if (!size)
    {
        // assuming that if we received the size, even though it is 0,
        // nothing is wrong
        
        // No words.
        return NULL;
    }
    
    unsigned char *buff = malloc(size);
    if (!buff)
    {
        *error = CFStringCreateWithFormat(kCFAllocatorDefault, NULL,
                                          CFSTR("Failed to allocate reply buffer!!!"));
        
        DLog(@"%@",*((NSString **)error));
        return NULL;
    }
    
    unsigned char *p = buff;
    uint32_t left = size;
    while (left)
    {
        uint32_t received = (uint32_t)recv(sock, p, left, 0);
        if (!received)
        {
            *error = CFStringCreateWithFormat(kCFAllocatorDefault, NULL,
                                              CFSTR("Reply was truncated, expected %d more bytes"), left);
            
            DLog(@"%@",*((NSString **)error));
            free(buff);
            return NULL;
        }        
        
        left -= received, p += received;
    }
    
    CFDataRef r = CFDataCreateWithBytesNoCopy(0,buff,size,kCFAllocatorNull);
    
    reply = CFPropertyListCreateWithData(0, r, kCFPropertyListImmutable, NULL, NULL);
    
    CFRelease(r);
    free(buff);
    
	return reply;
}
