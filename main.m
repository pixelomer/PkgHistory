#import <Foundation/Foundation.h>
#import <dirent.h>
#import <sys/stat.h>
#import "shared.m"

static void PXApplication_DidChangePreferencesCallback(
	CFNotificationCenterRef center,
	void *observer,
	CFNotificationName name,
	const void *object,
	CFDictionaryRef userInfo
) {
	// This notification is not implemented!
}

@interface PXApplication : NSObject
@end

@implementation PXApplication

+ (int)main:(NSArray<NSString *> *)args {
	NSError *error;

	// Check the user ID
	if (getuid() != 0) {
		NSLog(@"%s must be ran as root.\n", args[0].UTF8String);
		return EXIT_FAILURE;
	}

	// Set the working directory
	const char *workingDirectoryPath = "/Library/DPKGLogger";
	DIR *workingDirectory = opendir(workingDirectoryPath);
	if (!workingDirectory) {
		NSLog(@"Could not open %s: %s", workingDirectoryPath, strerror(errno));
		return EXIT_FAILURE;
	}
	fchdir(dirfd(workingDirectory));

	// Check if the number of arguments is 2
	if (args.count != 2) {
		fprintf(stderr,
			"Usage: %s <command>\n"
			"Commands:\n"
			"  reset - delete the existing logs\n"
			"  about - details about this utility\n", [args[0] UTF8String]);
		return EXIT_FAILURE;
	}

	// Perform the expected actions depending on the arguments
	if ([args[1] isEqualToString:@"daemon"]) {
		CFNotificationCenterAddObserver(
			CFNotificationCenterGetDarwinNotifyCenter(),
			NULL,
			PXApplication_DidChangePreferencesCallback,
			CFSTR("com.pixelomer.dpkglogger/DidChangePreferences"),
			NULL,
			0
		);
		NSDate *lastModificationDate = [NSDate distantPast];
		while (1) { @autoreleasepool {
			NSString *errorMessage = nil;
			#define PXAssert(test, args...) do { if (!(test)) { \
				errorMessage = [NSString stringWithFormat:args]; \
				break; \
			}} while (0)
			do {
				// Acquire the lock
				PXAssert(AcquireLock(YES), @"Couldn't acquire the lock");

				// Check if the modification date changed
				NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:@"/var/lib/dpkg/status" error:&error];
				PXAssert(attributes, @"%@", error.localizedDescription);
				if (lastModificationDate.timeIntervalSince1970 >= attributes.fileModificationDate.timeIntervalSince1970) {
					break;
				}

				// Read and process the current status file
				NSString *newStatusFile = [NSString
					stringWithContentsOfFile:@"/var/lib/dpkg/status"
					encoding:NSUTF8StringEncoding
					error:&error
				];
				PXAssert(newStatusFile, @"Failed to read the status file. %@", error.localizedDescription);

				// Process the new status file
				NSDictionary *newItems;
				@autoreleasepool {
					NSArray<NSString *> *items = [newStatusFile componentsSeparatedByString:@"\n\n"];
					PXAssert(items, @"Failed to split the status file.");
					NSUInteger count = items.count;
					if (items.lastObject && ([items.lastObject length] == 0)) {
						count--;
					}
					newItems = (NSDictionary *)[NSMutableDictionary dictionaryWithCapacity:items.count];
					for (NSUInteger i=0; i<count; i++) { @autoreleasepool {
						NSArray *lines = [items[i] componentsSeparatedByString:@"\n"];
						NSMutableDictionary *dict = @{
							@"version" : [NSNull null],
							@"package" : [NSNull null],
							@"name" : @[@"package"]
						}.mutableCopy;
						for (NSString *line in lines) {
							if ([line hasPrefix:@"\t"] || [line hasPrefix:@" "]) continue;
							NSMutableArray *components = [line componentsSeparatedByString:@":"].mutableCopy;
							NSString *field = [(NSString *)components.firstObject lowercaseString];
							if (!field || !dict[field]) continue;
							[components removeObjectAtIndex:0];
							dict[field] = [components componentsJoinedByString:@":"];
						}
						for (NSString *key in [dict.allKeys copy]) {
							if ([dict[key] isKindOfClass:[NSArray class]]) {
								dict[key] = dict[[dict[key] firstObject]];
							}
							if ([dict[key] isKindOfClass:[NSNull class]]) {
								dict = nil;
								break;
							}
							dict[key] = [(NSString *)dict[key] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
						}
						if (dict) {
							NSString *package = dict[@"package"];
							[dict removeObjectForKey:@"package"];
							((NSMutableDictionary *)newItems)[package] = dict.copy;
						}
					}}
					newItems = newItems.copy;
				}

				// If an older processed status file doesn't exist, write the new one to disk and exit
				if ([NSFileManager.defaultManager fileExistsAtPath:@"status.plist.tmp"]) {
					PXAssert([NSFileManager.defaultManager removeItemAtPath:@"status.plist.tmp" error:&error], @"%@", error.localizedDescription);
				}
				BOOL iOS11 = NO;
				if (@available(iOS 11.0, *)) iOS11 = YES;
				NSData *data = [NSPropertyListSerialization
					dataWithPropertyList:newItems
					format:NSPropertyListBinaryFormat_v1_0
					options:0
					error:&error
				];
				PXAssert(data, @"%@", error.localizedDescription);
				PXAssert(
					[data
						writeToFile:@"status.plist.tmp"
						options:0
						error:&error
					],
					@"%@", error.localizedDescription
				);
				NSDictionary *oldItems = (
					[NSFileManager.defaultManager fileExistsAtPath:@"status.plist"] ?
					(
						iOS11 ?
						[NSDictionary dictionaryWithContentsOfURL:[NSURL fileURLWithPath:@"status.plist"] error:&error] :
						[[NSDictionary alloc] initWithContentsOfFile:@"status.plist"]
					) :
					(NSDictionary *)[NSNull null]
				);
				PXAssert(oldItems, @"%@", iOS11 ? error.localizedDescription : @"Failed to read status.plist");
				PXAssert(
					(
						[oldItems isKindOfClass:[NSNull class]] ?:
						[NSFileManager.defaultManager removeItemAtPath:@"status.plist" error:&error]
					), @"%@", error.localizedDescription
				);
				PXAssert(
					[NSFileManager.defaultManager
						moveItemAtPath:@"status.plist.tmp"
						toPath:@"status.plist"
						error:&error
					], @"%@", error.localizedDescription
				);
				if ([oldItems isKindOfClass:[NSNull class]]) continue;

				// Find the differences between the old and the new file
				NSMutableDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *addedItems = [NSMutableDictionary new];
				NSMutableDictionary<NSString *, NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *> *changedItems = [NSMutableDictionary new];
				NSMutableDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *removedItems = [NSMutableDictionary new];
				@autoreleasepool {
					// Find removed items
					for (NSString *key in oldItems) {
						if (!newItems[key]) {
							removedItems[key] = oldItems[key];
						}
					}

					// Find new and changed items
					for (NSString *key in newItems) {
						if (!oldItems[key]) {
							addedItems[key] = newItems[key];
						}
						else if (![oldItems[key] isEqualToDictionary:newItems[key]]) {
							changedItems[key] = @{ @"old" : oldItems[key], @"new" : newItems[key] };
						}
					}

					if (!changedItems.count && !addedItems.count && !removedItems.count) {
						// Nothing changed!
						break;
					}
				}

				// Prepare the new plist
				NSMutableDictionary *newLogs = (
					iOS11 ?
					[NSDictionary dictionaryWithContentsOfURL:[NSURL fileURLWithPath:@"logs.plist"] error:&error] :
					[[NSDictionary alloc] initWithContentsOfFile:@"logs.plist"]
				).mutableCopy;
				PXAssert(
					(newLogs || ![NSFileManager.defaultManager fileExistsAtPath:@"logs.plist"]),
					@"%@", iOS11 ? error.localizedDescription : @"Couldn't read logs.plist"
				);
				if (!newLogs) newLogs = [NSMutableDictionary new];
				NSArray *oldLogsArray = newLogs[@"logs"] ?: [NSArray new];
				NSMutableDictionary *newArrayItem = [NSMutableDictionary new];
				if (addedItems.count) {
					newArrayItem[@"added"] = addedItems;
				}
				if (removedItems.count) {
					newArrayItem[@"removed"] = removedItems;
				}
				if (changedItems.count) {
					newArrayItem[@"changed"] = changedItems;
				}
				newArrayItem[@"date"] = [NSDate date];
				newLogs[@"logs"] = [@[newArrayItem] arrayByAddingObjectsFromArray:oldLogsArray];

				// Write the new plist to the disk
				data = [NSPropertyListSerialization
					dataWithPropertyList:newLogs
					format:NSPropertyListBinaryFormat_v1_0
					options:0
					error:&error
				];
				PXAssert(data, @"%@", error.localizedDescription);
				PXAssert(
					[data
						writeToFile:@"logs.plist"
						options:NSDataWritingAtomic
						error:&error
					],
					@"%@", error.localizedDescription
				);

				// Make sure the logs are readable by everyone
				chmod("logs.plist", 0644);

				// Save the new modification date
				lastModificationDate = attributes.fileModificationDate;

				// Post a notification about the update
				CFNotificationCenterPostNotification(
					CFNotificationCenterGetDarwinNotifyCenter(),
					CFSTR("com.pixelomer.dpkglogger/DidUpdateLogs"),
					NULL,
					NULL,
					0
				);
			} while(0);
			#undef PXAssert
			ReleaseLock();
			NSDate *date;
			if (errorMessage) {
				NSLog(@"Daemon error: %@", errorMessage);
				date = [NSDate dateWithTimeIntervalSinceNow:30];
			}
			else {
				date = [NSDate dateWithTimeIntervalSinceNow:3];
			}
			[[NSRunLoop currentRunLoop] runUntilDate:date];
			[NSThread sleepUntilDate:date];
		}}
	}
	else if ([args[1] isEqualToString:@"about"]) {
		printf(
			"This utility is a part of PkgHistory by pixelomer.\n"
			"It runs in the background and looks for package\n"
			"modifications such as installations, removals,\n"
			"upgrades and downgrades. If you think PkgHistory is\n"
			"not working properly, see \"/Library/DPKGLogger/\n"
			"daemon.log\". If you think there's a problem, contact\n"
			"@pixelomer on Twitter.\n"
		);
		return EXIT_SUCCESS;
	}
	else if ([args[1] isEqualToString:@"reset"]) {
		if (![NSFileManager.defaultManager fileExistsAtPath:@"logs.plist"]) {
			printf("There is nothing to remove!\n");
			return EXIT_SUCCESS;
		}
		printf(
			"Resetting DPKGLogger will delete all your\n"
			"history of package installations, removals,\n"
			"downgrades and upgrades. THIS ACTION CANNOT\n"
			"BE REVERSED.\n"
			"\n"
			"Do you want to continue? [y/N]: "
		);
		fflush(stdout);
		char input[3];
		fgets(input, 3, stdin);
		if (memcmp(&input[1], "\n", 2)) {
			input[0] = 'n';
		}
		switch (input[0]) {
			case 'y': case 'Y': {
				AcquireLock(YES);
				if (![NSFileManager.defaultManager removeItemAtPath:@"logs.plist" error:&error]) {
					printf("Reset failed: %s\n", error.localizedDescription.UTF8String);
				}
				else {
					printf("Reset succeeded.\n");

					// Post a notification about the update
					CFNotificationCenterPostNotification(
						CFNotificationCenterGetDarwinNotifyCenter(),
						CFSTR("com.pixelomer.dpkglogger/DidUpdateLogs"),
						NULL,
						NULL,
						0
					);
				}
				ReleaseLock();
				return EXIT_SUCCESS;
			}
			default: {
				printf("Cancelled.\n");
				return EXIT_FAILURE;
			}
		}
	}
	else {
		fprintf(stderr, "%s: unknown command: %s\n", [args[0] UTF8String], [args[1] UTF8String]);
	}
	return EXIT_FAILURE;
}

@end

int main(int argc, char **argv) {
	NSArray *finalArgs;
	@autoreleasepool {
		NSMutableArray *args = [NSMutableArray arrayWithCapacity:argc];
		for (int i=0; i<argc; i++) {
			[args addObject:@(argv[i])];
		}
		finalArgs = args.copy;
	}
	int ret = [PXApplication main:finalArgs];
	return ret;
}