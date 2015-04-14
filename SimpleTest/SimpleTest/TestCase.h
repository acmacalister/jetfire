//
//  TestCase.h
//  SimpleTest
//
//  Created by Adam Kaplan on 4/14/15.
//  Copyright (c) 2015 Vluxe. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, TestCaseStatus) {
    TestCaseStatusNotRun = 0,
    TestCaseStatusRunning,
    TestCaseStatusPassed,
    TestCaseStatusFailed
};

@interface TestCase : NSObject

@property (nonatomic) NSString *summary;
@property (nonatomic) NSString *expectation;
@property (nonatomic) NSString *identifier;
@property (nonatomic) NSInteger number;
@property (nonatomic) TestCaseStatus status;

@end
