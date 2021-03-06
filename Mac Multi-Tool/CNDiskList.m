//
//  CNDiskList.m
//  Mac Multi-Tool
//
//  Created by Kristopher Scruggs on 2/5/16.
//  Copyright © 2016 Corporate Newt Software. All rights reserved.
//

#import "CNDiskList.h"

@implementation CNDiskList

@synthesize diskList;

+ (id)sharedList {
    static CNDiskList *sharedCNDiskList = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedCNDiskList = [[self alloc] init];
    });
    return sharedCNDiskList;
}

- (id)init {
    if (self = [super init]) {
        //Set up anything that needs to happen at init.
    }
    return self;
}

- (void) dealloc {
    // Shouldn't ever be called, but here for clarity.
}

# pragma mark -
# pragma mark Diskutil Functions

- (NSMutableDictionary *)getAllDisksPlist {
    //Let's get the output for diskutil list -plist
    
    //Set up our array of arguments
    NSArray *args = [NSArray arrayWithObjects:@"list", @"-plist", nil];
    
    //Get our mutable dictionary
    NSMutableDictionary *diskPlist = [self diskUtilWithArguments:args];
    
    //Return our dictionary
    return diskPlist;
}

- (NSMutableDictionary *)getPlistForDisk:(NSString *)disk {
    //Let's get the output for diskutil info -plist disk
    
    //Set up our array of arguments
    NSArray *args = [NSArray arrayWithObjects:@"info", @"-plist", disk, nil];
    
    //Get our mutable dictionary
    NSMutableDictionary *diskPlist = [self diskUtilWithArguments:args];
    
    //Return our dictionary
    return diskPlist;
}

- (NSMutableDictionary *)diskUtilWithArguments:(NSArray *)args {
    //Let's run /usr/sbin/diskutil with the arguments and return the output as a plist formatted mutable dictionary
    
    //Set up our pipe, and build our task
    NSPipe *pipe = [NSPipe pipe];
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/sbin/diskutil"];
    [task setArguments:args];
    [task setStandardOutput:pipe];
    
    //Run the task
    [task launch];
    
    //Grab the raw output data
    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    
    //Parse the data into a plist formatted mutable dictionary
    NSString *error;
    NSPropertyListFormat format;
    NSMutableDictionary *diskPlist = [NSPropertyListSerialization propertyListFromData:data mutabilityOption:NSPropertyListMutableContainersAndLeaves format:&format errorDescription:&error];
    
    //Return the dictionary
    return diskPlist;
}

- (NSString *)diskString:(NSString *)disk {
    //Let's run /usr/sbin/diskutil with the arguments and return the output as a plist formatted mutable dictionary
    
    //Set up our pipe, and build our task
    NSPipe *pipe = [NSPipe pipe];
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/sbin/diskutil"];
    NSArray *args = [[NSArray alloc] initWithObjects:@"info", disk, nil];
    [task setArguments:args];
    [task setStandardOutput:pipe];
    
    //Run the task
    [task launch];
    [task waitUntilExit];
    
    //Grab the raw output data
    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    
    NSString* tmpString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    //Return the string
    return tmpString;
}


#pragma mark -
#pragma mark Plist Parsing Functions

- (NSString *)getStringForDisk:(CNDiskRep *)disk {
    NSString *diskID;
    if ([disk objectForKey:@"DeviceNode"]) {
        diskID = [disk objectForKey:@"DeviceNode"];
    } else if ([disk objectForKey:@"DeviceIdentifier"]) {
        diskID = [disk objectForKey:@"DeviceIdentifier"];
    } else if ([disk objectForKey:@"Name"]) {
        diskID = [disk objectForKey:@"Name"];
    } else {
        return nil;
    }
    return [self diskString:diskID];
}

- (NSMutableArray *)getAllDiskIdentifiers {
    NSMutableDictionary *diskPlist = [self getAllDisksPlist];
    
    NSMutableArray *diskIdentifierList = [diskPlist objectForKey:@"AllDisks"];
    
    return diskIdentifierList;
}

- (NSMutableArray *)getWholeDiskIdentifiers {
    NSMutableDictionary *diskPlist = [self getAllDisksPlist];
    
    NSMutableArray *diskIdentifierList = [diskPlist objectForKey:@"WholeDisks"];
    
    return diskIdentifierList;
}

- (NSMutableArray *)getVolumesFromDisks {
    NSMutableDictionary *diskPlist = [self getAllDisksPlist];
    
    NSMutableArray *diskIdentifierList = [diskPlist objectForKey:@"VolumesFromDisks"];
    
    return diskIdentifierList;
}

- (NSMutableArray *)getAllDisksAndPartitionsList {
    NSMutableDictionary *diskPlist = [[self getAllDisksPlist] objectForKey:@"AllDisksAndPartitions"];
    
    NSMutableArray *allDisksAndParts = [[NSMutableArray alloc] init];
    
    for (id disk in diskPlist) {
        //Iterate through, add disks - then add partitions
        
        NSMutableDictionary *diskP = [self getPlistForDisk:[disk objectForKey:@"DeviceIdentifier"]];
        NSString *diskSize = [self getReadableSizeFromString:[diskP objectForKey:@"TotalSize"]];
        
        CNDiskRep *diskRep = [[CNDiskRep alloc] init];
        [diskRep setObjects:disk];
        [diskRep removeObjectWithKey:@"Partitions"];
        [diskRep setObject:[diskP objectForKey:@"MediaName"] forKey:@"Name"];
        [diskRep setObject:diskSize forKey:@"SizeReadable"];
        
        for (id part in [disk objectForKey:@"Partitions" ]) {
            NSString *partSize = [self getReadableSizeFromString:[part objectForKey:@"Size"]];
            
            CNDiskRep *partRep = [[CNDiskRep alloc] init];
            [partRep setObjects:part];
            if ([part objectForKey:@"VolumeName"]) {
                [partRep setObject:[part objectForKey:@"VolumeName"] forKey:@"Name"];
            } else {
                [partRep setObject:@"" forKey:@"Name"];
            }
            [partRep setObject:partSize forKey:@"SizeReadable"];
            
            if ([[part objectForKey:@"MountPoint"] isEqualToString:@"/"]) {
                [partRep setIsBoot:YES];
                [diskRep setIsBoot:YES];
            }
            
            [diskRep addChild:partRep];
        }
        
        [allDisksAndParts addObject:diskRep];
        
    }
    
    return allDisksAndParts;
    
}

- (NSMutableArray *)getOutlineViewList {
    //This is where we're going to put everything into digestable chunks.
    //We do this by building arrays of CNDiskReps
    
    //Let's start by grabbing all the whole disks, then working our way through
    NSMutableArray *wholeDisks = [self getWholeDiskIdentifiers];
    NSMutableArray *allDisks = [self getAllDiskIdentifiers];
    
    //Create a fresh array for our final product
    NSMutableArray *outlineList = [[NSMutableArray alloc] init];
    
    //Iterate through each object
    for (id disk in wholeDisks) {
        //disk will be a string in the format disk0, disk1, disk2, etc
        NSMutableDictionary *diskPlist = [self getPlistForDisk:disk];
        NSString *diskSize = [self getReadableSizeFromString:[diskPlist objectForKey:@"TotalSize"]];
        
        /*CNDiskRep *diskRep = [[CNDiskRep alloc] initWithName:[diskPlist objectForKey:@"MediaName"]];
        [diskRep setSize:diskSize];
        [diskRep setType:[diskPlist objectForKey:@"Content"]];
        [diskRep setIdentifier:[NSString stringWithFormat:@"/dev/%@", disk]];*/
        
        CNDiskRep *diskRep = [[CNDiskRep alloc] init];
        [diskRep setObjects:diskPlist];
        [diskRep setObject:[diskPlist objectForKey:@"MediaName"] forKey:@"Name"];
        [diskRep setObject:diskSize forKey:@"SizeReadable"];
        [diskRep setObject:[diskPlist objectForKey:@"DeviceNode"] forKey:@"DeviceIdentifier"];
        
        
        //Iterate through all disk identifiers (disk0, disk0s1, disk0s2) and
        //create diskreps for each - then add to the children of the parentdisk
        for (id part in allDisks) {
            if ([part containsString:disk] && ![part isEqualToString:disk]) {
                //part is a partition of disk, but not the disk itself
                
                NSMutableDictionary *partPlist = [self getPlistForDisk:part];
                //Create our partition diskrep
                NSString *partSize = [self getReadableSizeFromString:[partPlist objectForKey:@"TotalSize"]];
                
                CNDiskRep *partRep = [[CNDiskRep alloc] init];
                [partRep setObjects:partPlist];
                [partRep setObject:[partPlist objectForKey:@"VolumeName"] forKey:@"Name"];
                [partRep setObject:partSize forKey:@"SizeReadable"];
                
                
                /*CNDiskRep *partRep = [[CNDiskRep alloc] initWithName:[partPlist objectForKey:@"VolumeName"]];
                [partRep setType:[partPlist objectForKey:@"Content"]];
                [partRep setSize:partSize];
                [partRep setIdentifier:part];*/
                //[partRep setIsChild:YES];
                if ([[partPlist objectForKey:@"MountPoint"] isEqualToString:@"/"]) {
                    [partRep setIsBoot:YES];
                    [diskRep setIsBoot:YES];
                }
                
                [diskRep addChild:partRep];
            }
        }
        [outlineList addObject:diskRep];
    }
    
    return outlineList;
}

- (NSMutableArray *)getVolumesViewList {
    NSMutableArray *volumes = [self getVolumesFromDisks];
    NSMutableArray *volumesList = [[NSMutableArray alloc] init];
    
    for (id vol in volumes) {
        NSMutableDictionary *volPlist = [self getPlistForDisk:vol];
        NSString *volSize = [self getReadableSizeFromString:[volPlist objectForKey:@"TotalSize"]];
        
        CNDiskRep *volRep = [[CNDiskRep alloc] init];
        [volRep setObjects:volPlist];
        [volRep setObject:vol forKey:@"Name"];
        [volRep setObject:volSize forKey:@"SizeReadable"];
        
        if ([[volPlist objectForKey:@"MountPoint"] isEqualToString:@"/"]) {
            [volRep setIsBoot:YES];
        }
        
        [volumesList addObject:volRep];
    }
    
    return volumesList;
}

- (NSMutableArray *)getDiskViewList:(id)disk {
    if (disk == nil) {
        return nil;
    }
    
    //Grab some blank variables
    NSMutableArray *diskViewList = [[NSMutableArray alloc] init];
    NSMutableDictionary *diskPlist;
    CNDiskRep *diskRep = [[CNDiskRep alloc] init];
    
    
    if ([disk isKindOfClass:[NSString class]]) {
        diskPlist = [self getPlistForDisk:disk];
        [diskRep setObjects:diskPlist];
        [diskViewList addObject:diskRep];
    } else if ([disk isKindOfClass:[CNDiskRep class]]) {
        
        NSLog(@"Disk -\nDN: %@\nDI: %@\nName: %@", [disk objectForKey:@"DeviceNode"], [disk objectForKey:@"DeviceIdentifier"], [disk objectForKey:@"Name"]);
        
        if ([disk objectForKey:@"DeviceNode"]) {
            diskPlist = [self getPlistForDisk:[disk objectForKey:@"DeviceNode"]];
            [diskRep setObjects:diskPlist];
        } else if ([disk objectForKey:@"DeviceIdentifier"]) {
            diskPlist = [self getPlistForDisk:[disk objectForKey:@"DeviceIdentifier"]];
            [diskRep setObjects:diskPlist];
        } else if ([disk objectForKey:@"Name"]) {
            diskPlist = [self getPlistForDisk:[disk objectForKey:@"Name"]];
            [diskRep setObjects:diskPlist];
        } else {
            return nil;
        }
        
        //Set up size and isBoot
        NSString *diskSize = [self getReadableSizeFromString:[diskPlist objectForKey:@"TotalSize"]];
        [diskPlist setObject:diskSize forKey:@"SizeReadable"];
        
        //Make sure we mark isBoot if the boot drive/partition
        if ([self isBootDisk:diskRep]) {
            [diskRep setIsBoot:YES];
        }
        
        
        [diskRep setObjects:diskPlist];
        [diskViewList addObject:diskRep];
    }
    
    NSLog(@"diskViewList:\n%@", diskViewList);
    
    return diskViewList;
}

- (NSString *)getBootDeviceNode {
    NSMutableDictionary *bootVolume = [self getPlistForDisk:@"/"];
    return [bootVolume objectForKey:@"DeviceNode"];
}

- (BOOL)isBootDisk:(id)disk {
    
    //Create a blank dictionary
    NSMutableDictionary *diskPlist = nil;
    
    //if we are passed a valid disk name or rep, get plist
    if ([disk isKindOfClass:[NSString class]]) {
        diskPlist = [self getPlistForDisk:disk];
    } else if ([disk isKindOfClass:[CNDiskRep class]]) {
        if ([disk objectForKey:@"DeviceNode"]) {
            diskPlist = [self getPlistForDisk:[disk objectForKey:@"DeviceNode"]];
        } else if ([disk objectForKey:@"DeviceIdentifier"]) {
            diskPlist = [self getPlistForDisk:[disk objectForKey:@"DeviceIdentifier"]];
        } else if ([disk objectForKey:@"Name"]) {
            diskPlist = [self getPlistForDisk:[disk objectForKey:@"Name"]];
        }
    }
    
    //If diskPlist was initialized, find out if boot
    if (diskPlist != nil) {
        // We initialized :)
        if ([[self getBootDeviceNode] containsString:[diskPlist objectForKey:@"DeviceNode"]]) {
            // if boot device node contains our device node - we're on the boot disk/partition
            return YES;
        }
    }
    
    return NO;
}

- (NSString *)getReadableSizeFromString:(NSString *)string {
    float sizeBytes = [string floatValue];
    float sizeKiloBytes = sizeBytes/1000;
    float sizeMegaBytes = sizeKiloBytes/1000;
    float sizeGigaBytes = sizeMegaBytes/1000;
    float sizeTeraBytes = sizeGigaBytes/1000;
    float sizePetaBytes = sizeTeraBytes/1000;
    
    if (sizePetaBytes > 1) {
        return [NSString stringWithFormat:@"%.02f PB", sizePetaBytes];
    } else if (sizeTeraBytes > 1) {
        return [NSString stringWithFormat:@"%.02f TB", sizeTeraBytes];
    } else if (sizeGigaBytes > 1) {
        return [NSString stringWithFormat:@"%.02f GB", sizeGigaBytes];
    } else if (sizeMegaBytes > 1) {
        return [NSString stringWithFormat:@"%.02f MB", sizeMegaBytes];
    } else if (sizeKiloBytes > 1) {
        return [NSString stringWithFormat:@"%.02f KB", sizeKiloBytes];
    } else {
        return [NSString stringWithFormat:@"%.02f B", sizeBytes];
    }
}

@end