#import <UIKit/UIKit.h>
#import "../shared.m"

@interface PKGRootViewController : UITableViewController
- (void)reloadButtonPressed;
@end

static void PKGRootViewController_DidUpdateLogsCallback(
	CFNotificationCenterRef center,
	void *observer,
	CFNotificationName name,
	const void *object,
	CFDictionaryRef userInfo
) {
	PKGRootViewController *vc = (__bridge PKGRootViewController *)observer;
	[vc reloadButtonPressed];
}

@implementation PKGRootViewController {
	NSArray<NSString *> *_dates;
	NSArray<NSArray<NSArray<NSAttributedString *> *> *> *_strings;
	BOOL _didAppearBefore;
}

static NSDateFormatter *_dateFormatter;

+ (void)initialize {
	if (self == [PKGRootViewController class]) {
		_dateFormatter = [NSDateFormatter new];
		_dateFormatter.timeStyle = NSDateFormatterShortStyle;
		_dateFormatter.dateStyle = NSDateFormatterLongStyle;
	}
}

- (NSAttributedString *)attributedStringForChangingKey:(NSString *)key
	fromValue:(NSString *)from
	toValue:(NSString *)to
{
	UIFont *font = [UIFont systemFontOfSize:15.0];
	UIFont *boldFont = [UIFont boldSystemFontOfSize:15.0];
	NSMutableAttributedString *str = [[NSMutableAttributedString alloc]
		initWithString:[key stringByAppendingString:@": "]
		attributes:@{
			NSFontAttributeName : boldFont
		}
	];
	NSString *following;
	if (to && ![from isEqualToString:to]) {
		following = [NSString stringWithFormat:@"%@ ⮕ %@", from, to];
	}
	else {
		following = from;
	}
	[str appendAttributedString:[[NSAttributedString alloc]
		initWithString:following
		attributes:@{
			NSFontAttributeName : font
		}
	]];
	return str.copy;
}

- (NSAttributedString *)titleForChange:(NSString *)change package:(NSString *)package {
	static NSDictionary *map;
	static dispatch_once_t token;
	dispatch_once(&token, ^{
		map = @{
			@"changed" : @"Modified",
			@"removed" : @"Removed",
			@"added" : @"Installed"
		};
	});
	UIFont *font = [UIFont systemFontOfSize:18.5];
	NSMutableAttributedString *str = [[NSMutableAttributedString alloc]
		initWithString:[map[change] stringByAppendingString:@" "]
		attributes:@{
			NSFontAttributeName : font
		}
	];
	UIFont *boldFont = [UIFont boldSystemFontOfSize:18.5];
	[str appendAttributedString:[[NSAttributedString alloc]
		initWithString:package
		attributes:@{
			NSFontAttributeName : boldFont
		}
	]];
	return str.copy;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Package History";
	/*self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
		initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
		target:self
		action:@selector(reloadButtonPressed)
	];*/
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	if (!_didAppearBefore) {
		_didAppearBefore = YES;
		[self reloadButtonPressed];
		CFNotificationCenterAddObserver(
			CFNotificationCenterGetDarwinNotifyCenter(),
			(__bridge void *)self,
			PKGRootViewController_DidUpdateLogsCallback,
			CFSTR("com.pixelomer.dpkglogger/DidUpdateLogs"),
			NULL,
			0
		);
		int daemonLock = open("/Library/DPKGLogger/.daemon-running", O_CREAT, O_RDONLY);
		if ((daemonLock == -1) || (flock(daemonLock, (LOCK_EX | LOCK_NB)) == 0) || (errno != EWOULDBLOCK)) {
			UIAlertController *alert = [UIAlertController
				alertControllerWithTitle:@"Daemon Warning"
				message:@"The PkgHistory daemon is not running! Without this daemon, packages will not be logged by PkgHistory. Make sure your jailbreak properly launches launch daemons in \"/Library/LaunchDaemons\" on startup. If it does, something else might be wrong, so check \"/Library/DPKGLogger/daemon.log\"."
				preferredStyle:UIAlertControllerStyleAlert
			];
			[alert addAction:[UIAlertAction
				actionWithTitle:@"OK"
				style:UIAlertActionStyleDefault
				handler:nil
			]];
			[self presentViewController:alert animated:YES completion:nil];
		}
		flock(daemonLock, LOCK_UN);
		close(daemonLock);
	}
}

- (void)reloadButtonPressed {
	AcquireLock(NO);
	NSDictionary *logs = [[NSDictionary alloc] initWithContentsOfFile:@"/Library/DPKGLogger/logs.plist"];
	ReleaseLock();
	if (!logs) {
		_dates = @[];
		_strings = @[];
		[self.tableView reloadData];
		return;
	}
	NSMutableArray *dates = [NSMutableArray new];
	NSMutableArray *strings = [NSMutableArray new];
	for (NSDictionary *dict in logs[@"logs"]) {
		[dates addObject:[_dateFormatter stringFromDate:dict[@"date"]]];
		NSMutableArray *substrings = [NSMutableArray new];
		for (NSString *key in @[@"added", @"removed", @"changed"]) {
			for (NSString *ID in dict[key]) {
				NSDictionary *fields = ((NSDictionary *)dict[key])[ID];
				BOOL isChanged = [key isEqualToString:@"changed"];
				NSMutableAttributedString *desc = [self
					attributedStringForChangingKey:@"ID"
					fromValue:ID
					toValue:nil
				].mutableCopy;
				[desc appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
				[desc appendAttributedString:[self
					attributedStringForChangingKey:@"Version"
					fromValue:(isChanged ? ((NSDictionary *)fields[@"old"])[@"version"] : fields[@"version"])
					toValue:(isChanged ? ((NSDictionary *)fields[@"new"])[@"version"] : nil)
				]];
				[substrings addObject:@[
					[self titleForChange:key package:(
						isChanged ?
						((NSDictionary *)fields[@"new"])[@"name"] :
						fields[@"name"]
					)],
					[desc copy]
				]];
			}
		}
		[strings addObject:substrings.copy];
	}
	_strings = strings.copy;
	_dates = dates.copy;
	[self.tableView reloadData];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return _dates[section];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return _dates.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return _strings[section].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
	if (!cell) {
		cell = [[UITableViewCell alloc]
			initWithStyle:UITableViewCellStyleSubtitle
			reuseIdentifier:@"cell"
		];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		cell.detailTextLabel.numberOfLines = 0;
		cell.textLabel.numberOfLines = 1;
	}
	cell.textLabel.attributedText = _strings[indexPath.section][indexPath.row][0];
	cell.detailTextLabel.attributedText = _strings[indexPath.section][indexPath.row][1];
	return cell;
}

- (void)dealloc {
	CFNotificationCenterRemoveObserver(
		CFNotificationCenterGetDarwinNotifyCenter(),
		(__bridge void *)self,
		NULL,
		NULL
	);
}

@end
