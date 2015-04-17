//
//  TestCaseTableViewcell.m
//  SimpleTest
//
//  Created by Adam Kaplan on 4/14/15.
//  Copyright (c) 2015 Vluxe. All rights reserved.
//

#import "TestCaseTableViewcell.h"
#import "TestCase.h"

@interface TestCaseTableViewcell ()
@property (nonatomic) UILabel *statusLabel;
@end

@implementation TestCaseTableViewcell

- (void)awakeFromNib {
    // Initialization code
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 60, 30)];
    self.statusLabel.font = [UIFont systemFontOfSize:[UIFont smallSystemFontSize]];
    self.statusLabel.minimumScaleFactor = 0.2;
    self.statusLabel.textAlignment = NSTextAlignmentRight;
    
    self.detailTextLabel.text = @" ";
}

/*
- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}
*/

- (void)prepareForReuse {
    [super prepareForReuse];
    self.testCase = nil;
    self.textLabel.text = nil;
    self.detailTextLabel.text = nil;
    self.accessoryView = nil;
}

- (void)setTestCase:(TestCase *)testCase {
    [self.testCase removeObserver:self forKeyPath:@"identifier"];
    [self.testCase removeObserver:self forKeyPath:@"summary"];
    [self.testCase removeObserver:self forKeyPath:@"status"];
    
    _testCase = testCase;

    if (testCase) {
        [testCase addObserver:self forKeyPath:@"identifier" options:NSKeyValueObservingOptionNew context:nil];
        [testCase addObserver:self forKeyPath:@"summary" options:NSKeyValueObservingOptionNew context:nil];
        [testCase addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
    
        self.textLabel.text = _testCase.identifier ?: @" "; // For some reason blank strings break the cell updating
        self.detailTextLabel.text = _testCase.summary ?: @" "; // For some reason blank strings break the cell updating
        [self updateStatusLabel];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    NSAssert(![change[NSKeyValueChangeNewKey] isKindOfClass:[NSNull class]], @"Invalid test case value for %@ from Autobahn: %@", keyPath, change);

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!weakSelf) {
            return;
        }
        
        if ([keyPath isEqualToString:@"identifier"]) {
            weakSelf.textLabel.text = change[NSKeyValueChangeNewKey];
        
        } else if ([keyPath isEqualToString:@"summary"]) {
            weakSelf.detailTextLabel.text = change[NSKeyValueChangeNewKey];
            
        } else {
            [weakSelf updateStatusLabel];
        }
    });
}

- (void)updateStatusLabel {
    static UIActivityIndicatorView *spinnerView;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        spinnerView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        [spinnerView startAnimating];
    });
    
    NSString *text;
    switch (self.testCase.status) {
        case TestCaseStatusNotRun:
            text = @"-";
            break;
            
        case TestCaseStatusPassed:
            text = @"✔︎";
            break;
            
        case TestCaseStatusFailed:
            text = @"❌";
            break;
            
        case TestCaseStatusRunning:
            self.accessoryView = spinnerView;
            break;
            
        default:
            text = @"?";
            break;
    }
    
    if (text) {
        self.statusLabel.text = text;
        self.accessoryView = self.statusLabel;
    }
}

@end
