//
//  ViewController.m
//  SimpleTest
//
//  Created by Austin Cherry on 2/24/15.
//  Copyright (c) 2015 Vluxe. All rights reserved.
//

#import "ViewController.h"
#import "JFRWebSocket.h"
#import "TestWebSocket.h"
#import "TestCase.h"
#import "TestCaseTableViewcell.h"
#import "TestOperation.h"

@interface ViewController ()
@property (nonatomic) NSOperationQueue *queue;
@property (nonatomic) NSMutableArray *testCases;
@property (nonatomic) UIAlertView *alertView;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.queue = [NSOperationQueue new];
    self.queue.maxConcurrentOperationCount = 1;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    if (self.testCases) {
        return;  // only need to automatically run one time
    }
    
    TestOperation *countOp = [[TestOperation alloc] initWithTestCase:nil command:@"getCaseCount"];
    [self.queue addOperation:countOp];
    [self.queue addOperationWithBlock:^{
        NSInteger testCount = [countOp.socket.receivedText integerValue];
        NSLog(@"Test Count: %lu", testCount);
        
        NSMutableArray *testCases = [[NSMutableArray alloc] init];
        for (int i = 1; i < testCount+1; i++) {
            TestCase *testCase = [TestCase new];
            testCase.number = i;
            [testCases addObject:testCase];
        }
        self.testCases = [testCases copy];
        [self.tableView performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:NO];
        
        for (TestCase *testCase in self.testCases) {
            [self getAutobahnTestInfo:testCase];
            [self runAutobahnTest:testCase];
            [self verifyAutobahnTest:testCase];
        }
    }];
}

#pragma mark - test control

- (void)getAutobahnTestInfo:(TestCase *)test {
    TestOperation *op = [[TestOperation alloc] initWithTestCase:test command:@"getCaseInfo"];
    [self.queue addOperation:op];
    [self.queue addOperationWithBlock:^{
        NSString *jsonStr = op.socket.receivedText;
        NSData *jsonData = [NSData dataWithBytesNoCopy:(void *)[jsonStr UTF8String]
                                                length:[jsonStr length]
                                          freeWhenDone:NO];
        NSDictionary *info = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
        test.identifier = info[@"id"];
        test.summary = info[@"description"];
        
        dispatch_sync(dispatch_get_main_queue(), ^{
            self.navigationItem.title = [NSString stringWithFormat:@"%03lu of %03lu", test.number, self.testCases.count];
        });
        NSLog(@"About to run %@ – %@", test.identifier, test.summary);
    }];
}

- (void)runAutobahnTest:(TestCase *)test {
    //NSLog(@"Running test %@ - %@", test.identifier, test.summary);
    TestOperation *op = [[TestOperation alloc] initWithTestCase:test command:@"runCase"];
    [self.queue addOperation:op];
}

- (void)verifyAutobahnTest:(TestCase *)test {
    TestOperation *op = [[TestOperation alloc] initWithTestCase:test command:@"getCaseStatus"];
    [self.queue addOperation:op];
    [self.queue addOperationWithBlock:^{
        NSString *jsonStr = op.socket.receivedText;
        NSData *jsonData = [NSData dataWithBytesNoCopy:(void *)[jsonStr UTF8String]
                                                length:[jsonStr length]
                                          freeWhenDone:NO];
        NSDictionary *info = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
        if ([info[@"behavior"] isEqualToString:@"OK"]) {
            NSLog(@"VERIFED %@", test.identifier);
            test.status = TestCaseStatusPassed;
        } else {
            NSLog(@"FAILED: %@ - %@", test.identifier, test.summary);
            test.status = TestCaseStatusFailed;
        }
    }];
}

#pragma mark - Table View Datasource and Delegate

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.testCases.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    TestCaseTableViewcell *cell = [tableView dequeueReusableCellWithIdentifier:@"BasicCellIdentifier" forIndexPath:indexPath];
    
    cell.testCase = self.testCases[indexPath.row];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!self.alertView) {
        self.alertView = [[UIAlertView alloc] initWithTitle:nil
                                                    message:nil
                                                   delegate:nil
                                          cancelButtonTitle:@"Dismiss"
                                          otherButtonTitles:nil];
    }
    
    TestCase *testCase = self.testCases[indexPath.row];
    self.alertView.title = testCase.identifier;
    self.alertView.message = testCase.summary;
    
    [self.alertView dismissWithClickedButtonIndex:0 animated:NO];
    [self.alertView show];
}

/*
 #pragma mark - Navigation
 
 // In a storyboard-based application, you will often want to do a little preparation before navigation
 - (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
 // Get the new view controller using [segue destinationViewController].
 // Pass the selected object to the new view controller.
 }
 */

@end
