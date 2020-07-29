#import <Foundation/Foundation.h>
#import <sys/stat.h>

static int lock = -1;

static BOOL AcquireLock(BOOL exclusive) {
	if ((lock == -1) && ((lock = open(".lock", O_CREAT, O_RDONLY)) == -1)) {
		NSLog(@"Failed to open the log file lock: %s", strerror(errno));
		return NO;
	}
	fchmod(lock, 0444);
	if (flock(lock, (exclusive ? LOCK_EX : LOCK_SH)) != 0) {
		NSLog(@"Failed to lock the log file: %s", strerror(errno));
		return NO;
	}
	return YES;
}

static BOOL ReleaseLock(void) {
	if (lock == -1) {
		NSLog(@"Attempted to release a lock before acquiring it");
		return NO;
	}
	if (flock(lock, LOCK_UN) != 0) {
		NSLog(@"Failed to unlock the log file: %s", strerror(errno));
		return NO;
	}
	close(lock);
	lock = -1;
	return YES;
}