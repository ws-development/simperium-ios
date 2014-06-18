//
//  SPChangeProcessorTests.m
//  Simperium
//
//  Created by Jorge Leandro Perez on 6/10/14.
//  Copyright (c) 2014 Simperium. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "XCTestCase+Simperium.h"
#import "MockSimperium.h"
#import "SPBucket+Internals.h"
#import "SPGhost.h"
#import "SPChangeProcessor.h"
#import "SPCoreDataStorage.h"
#import "Config.h"

#import "NSString+Simperium.h"
#import "JSONKit+Simperium.h"

#import "DiffMatchPatch.h"



#pragma mark ====================================================================================
#pragma mark Constants
#pragma mark ====================================================================================

static NSInteger const SPNumberOfEntities       = 100;
static NSString * const SPRemoteClientID        = @"OSX-Remote!";
static NSUInteger const SPRandomStringLength    = 1000;


#pragma mark ====================================================================================
#pragma mark SPChangeProcessorTests
#pragma mark ====================================================================================

@interface SPChangeProcessorTests : XCTestCase

@end

@implementation SPChangeProcessorTests

- (void)testProcessRemoteChangeWithInvalidDelta {
    
    // ===================================================================================================
	// Helpers
    // ===================================================================================================
    //
	MockSimperium* s                    = [MockSimperium mockSimperium];
	SPBucket* bucket                    = [s bucketForName:NSStringFromClass([Config class])];
	SPCoreDataStorage* storage          = bucket.storage;
	NSMutableArray* configs             = [NSMutableArray array];
    NSMutableDictionary *changes        = [NSMutableDictionary dictionary];
    NSMutableDictionary *originalLogs   = [NSMutableDictionary dictionary];
    
    
    // ===================================================================================================
	// Insert Config
    // ===================================================================================================
    //
	for (NSInteger i = 0; ++i <= SPNumberOfEntities; ) {
        NSString *originalLog           = [NSString sp_randomStringOfLength:SPRandomStringLength];
        
        // New post please!
		Config* config                  = [storage insertNewObjectForBucketName:bucket.name simperiumKey:nil];
		config.captainsLog              = originalLog;
        
        // Manually Intialize SPGhost: we're not relying on the backend to confirm these additions!
        NSMutableDictionary *memberData = [config.dictionary mutableCopy];
        SPGhost *ghost                  = [[SPGhost alloc] initWithKey:config.simperiumKey memberData:memberData];
        ghost.version                   = @"1";
        config.ghost                    = ghost;
        config.ghostData                = [memberData sp_JSONString];
        
        // Keep a copy of the original title
        NSString *key                   = config.simperiumKey;
        originalLogs[key]               = originalLog;
        
        // And keep a reference to the post
		[configs addObject:config];
	}
    
	[storage save];
    
    NSLog(@"<> Successfully inserted %d objects", (int)SPNumberOfEntities);
    
    
    // ===================================================================================================
    // Prepare Remote Changes
    // ===================================================================================================
    //
    for (Config *config in configs) {
        NSString *changeVersion     = [NSString sp_makeUUID];
        NSString *startVersion      = config.ghost.version;
        NSString *endVersion        = [NSString stringWithFormat:@"%d", startVersion.intValue + 1];
        NSString *delta             = @"An invalid delta here!";
        
        // Prepare the change itself
        NSDictionary *change    = @{
                                    CH_CLIENT_ID        : SPRemoteClientID,
                                    CH_CHANGE_VERSION   : changeVersion,
                                    CH_START_VERSION    : startVersion,
                                    CH_END_VERSION      : endVersion,
                                    CH_KEY              : config.simperiumKey,
                                    CH_OPERATION        : CH_MODIFY,
                                    CH_VALUE            : @{
                                            NSStringFromSelector(@selector(captainsLog))    : @{
                                                    CH_OPERATION    : CH_DATA,
                                                    CH_VALUE        : delta
                                            }
                                        }
                                    };
        
        changes[config.simperiumKey] = change;
    }
    
    NSLog(@"<> Successfully generated remote changes");
    
    
    // ===================================================================================================
    // Process remote changes
    // ===================================================================================================
    //
	StartBlock();
    
    dispatch_async(bucket.processorQueue, ^{
        __block NSInteger errorCount = 0;
        [bucket.changeProcessor processRemoteChanges:changes.allValues
                                              bucket:bucket
                                        errorHandler:^(NSString *simperiumKey, NSString *version, NSError *error) {
                                            XCTAssertTrue(error.code == SPProcessorErrorsReceivedInvalidChange, @"Invalid error code");
                                            ++errorCount;
                                        }];
        
        XCTAssertTrue(errorCount == changes.count, @"Missed an error?");
        
		dispatch_async(dispatch_get_main_queue(), ^{
			EndBlock();
		});
    });
    
	WaitUntilBlockCompletes();
    
    NSLog(@"<> Finished processing remote changes");
    
    
    // ===================================================================================================
    // Verify if the changeProcessor actually did its job
    // ===================================================================================================
    //
    for (Config *config in configs) {
        NSDictionary *change    = changes[config.simperiumKey];
        NSString *endVersion    = change[CH_END_VERSION];
        NSString *originalTitle = originalLogs[config.simperiumKey];
        
        // THE check!
        XCTAssertEqualObjects(config.captainsLog, originalTitle,    @"Invalid CaptainsLog");
        XCTAssertFalse([config.ghost.version isEqual:endVersion],   @"Invalid Ghost Version");
    }
}

- (void)testProcessRemoteEntityWithLocalPendingChangesSucceedsRebasing {
    
    // ===================================================================================================
	// Testing values! yay!
    // ===================================================================================================
    //
    NSString *originalLog               = @"Original Captains Log";
    NSNumber *originalWarp              = @(29);
    
    NSNumber *localPendingWarp          = @(31337);
    NSDecimalNumber *localPendingCost   = [NSDecimalNumber decimalNumberWithString:@"900"];
    NSString *localPendingLog           = @"Something Original Captains Log";
    
    NSString *newRemoteLog              = @"Remote Original Captains Log Suffixed";
    NSDecimalNumber *newRemoteCost      = [NSDecimalNumber decimalNumberWithString:@"300"];
    NSNumber *newRemoteWarp             = @(10);

    NSString *expectedLog               = @"Remote Something Original Captains Log Suffixed";
    NSDecimalNumber *expectedCost       = localPendingCost;
    NSNumber *expectedWarp              = localPendingWarp;
    
    
    // ===================================================================================================
	// Helpers
    // ===================================================================================================
    //
	MockSimperium* s                    = [MockSimperium mockSimperium];
	SPBucket* bucket                    = [s bucketForName:NSStringFromClass([Config class])];
	SPCoreDataStorage* storage          = bucket.storage;
    
    
    // ===================================================================================================
	// Insert Config
    // ===================================================================================================
    //
    Config* config                      = [storage insertNewObjectForBucketName:bucket.name simperiumKey:nil];
    config.captainsLog                  = originalLog;
    config.warpSpeed                    = originalWarp;
    
    // Manually Intialize SPGhost: we're not relying on the backend to confirm these additions!
    NSMutableDictionary *memberData     = [config.dictionary mutableCopy];
    SPGhost *ghost                      = [[SPGhost alloc] initWithKey:config.simperiumKey memberData:memberData];
    ghost.version                       = @"1";
    config.ghost                        = ghost;
    config.ghostData                    = [memberData sp_JSONString];
    
	[storage save];
    
    NSLog(@"<> Successfully inserted Config object");
    
    
    // ===================================================================================================
    // Prepare Remote Entity Message
    // ===================================================================================================
    //
    NSString *endVersion    = [NSString stringWithFormat:@"%d", config.ghost.version.intValue + 1];
    
    // Prepare the change itself
    NSDictionary *entity    = @{
        NSStringFromSelector(@selector(captainsLog))    : newRemoteLog,
        NSStringFromSelector(@selector(cost))           : newRemoteCost,
        NSStringFromSelector(@selector(warpSpeed))      : newRemoteWarp,
    };
    
    NSLog(@"<> Successfully generated remote change");
    
    
    // ===================================================================================================
    // Add local pending changes
    // ===================================================================================================
    //
    config.captainsLog  = localPendingLog;
    config.warpSpeed    = localPendingWarp;
    config.cost         = localPendingCost;
    
    [storage save];
    
    
    // ===================================================================================================
    // Process remote changes
    // ===================================================================================================
    //
	StartBlock();
    
    dispatch_async(bucket.processorQueue, ^{
        [bucket.changeProcessor processRemoteEntityWithKey:config.simperiumKey version:endVersion data:entity bucket:bucket];
        
		dispatch_async(dispatch_get_main_queue(), ^{
			EndBlock();
		});
    });
    
	WaitUntilBlockCompletes();
    
    NSLog(@"<> Finished processing remote changes");
    
    
    // ===================================================================================================
    // Verify if the changeProcessor actually did its job
    // ===================================================================================================
    //

    [storage refaultObjects:@[config]];
    
    XCTAssertEqualObjects(config.captainsLog, expectedLog,  @"Invalid Log");
    XCTAssertEqualObjects(config.cost, expectedCost,        @"Invalid Cost");
    XCTAssertEqualObjects(config.warpSpeed, expectedWarp,   @"Invalid Warp");
    XCTAssertEqualObjects(config.ghost.version, endVersion, @"Invalid Ghost Version");
    XCTAssertEqualObjects(config.ghost.memberData, entity,  @"Invalid Ghost MemberData");
}

- (void)testProcessRemoteEntityWithLocalPendingChangesFailsRebasingAndFavorsLocalData {
    
    // ===================================================================================================
	// Testing values! yay!
    // ===================================================================================================
    //
    NSString *originalLog           = @"Original Captains Log";
    NSString *localPendingLog       = @"Local Captains Log";
    NSString *newRemoteLog          = @"Remote Captains Log";
    NSString *expectedLog           = localPendingLog;
    
    
    // ===================================================================================================
	// Helpers
    // ===================================================================================================
    //
	MockSimperium* s                = [MockSimperium mockSimperium];
	SPBucket* bucket                = [s bucketForName:NSStringFromClass([Config class])];
	SPCoreDataStorage* storage      = bucket.storage;
    
    
    // ===================================================================================================
	// Insert Config
    // ===================================================================================================
    //
    Config* config                  = [storage insertNewObjectForBucketName:bucket.name simperiumKey:nil];
    config.captainsLog              = originalLog;
    
    // Manually Intialize SPGhost: we're not relying on the backend to confirm these additions!
    NSMutableDictionary *memberData = [config.dictionary mutableCopy];
    SPGhost *ghost                  = [[SPGhost alloc] initWithKey:config.simperiumKey memberData:memberData];
    ghost.version                   = @"1";
    config.ghost                    = ghost;
    config.ghostData                = [memberData sp_JSONString];
    
	[storage save];
    
    NSLog(@"<> Successfully inserted Config object");
    
    
    // ===================================================================================================
    // Prepare Remote Entity Message
    // ===================================================================================================
    //
    NSString *endVersion    = [NSString stringWithFormat:@"%d", config.ghost.version.intValue + 1];
    
    // Prepare the change itself
    NSDictionary *entity    = @{
        NSStringFromSelector(@selector(captainsLog)) : newRemoteLog,
    };
    
    NSLog(@"<> Successfully generated remote change");
    
    
    // ===================================================================================================
    // Add local pending changes
    // ===================================================================================================
    //
    config.captainsLog  = localPendingLog;
    
    [storage save];
    
    
    // ===================================================================================================
    // Process remote changes
    // ===================================================================================================
    //
	StartBlock();
    
    dispatch_async(bucket.processorQueue, ^{
        [bucket.changeProcessor processRemoteEntityWithKey:config.simperiumKey version:endVersion data:entity bucket:bucket];
        
		dispatch_async(dispatch_get_main_queue(), ^{
			EndBlock();
		});
    });
    
	WaitUntilBlockCompletes();
    
    NSLog(@"<> Finished processing remote changes");
    
    
    // ===================================================================================================
    // Verify if the changeProcessor actually did its job
    // ===================================================================================================
    //
    
    [storage refaultObjects:@[config]];
    
    XCTAssertEqualObjects(config.captainsLog, expectedLog,  @"Invalid Log");
    XCTAssertEqualObjects(config.ghost.version, endVersion, @"Invalid Ghost Version");
    XCTAssertEqualObjects(config.ghost.memberData, entity,  @"Invalid Ghost MemberData");
}

- (void)testProcessRemoteEntityWithoutLocalPendingChanges {
 
    // ===================================================================================================
	// Helpers
    // ===================================================================================================
    //
	MockSimperium* s                = [MockSimperium mockSimperium];
	SPBucket* bucket                = [s bucketForName:NSStringFromClass([Config class])];
	SPCoreDataStorage* storage      = bucket.storage;
    
    
    // ===================================================================================================
	// Insert Config
    // ===================================================================================================
    //
    NSString *originalLog           = @"1111 Captains Log";
    Config* config                  = [storage insertNewObjectForBucketName:bucket.name simperiumKey:nil];
    config.captainsLog              = originalLog;
    
    // Manually Intialize SPGhost: we're not relying on the backend to confirm these additions!
    NSMutableDictionary *memberData = [config.dictionary mutableCopy];
    SPGhost *ghost                  = [[SPGhost alloc] initWithKey:config.simperiumKey memberData:memberData];
    ghost.version                   = @"1";
    config.ghost                    = ghost;
    config.ghostData                = [memberData sp_JSONString];
    
	[storage save];
    
    NSLog(@"<> Successfully inserted Config object");
    
    
    // ===================================================================================================
    // Prepare Remote Entity Message
    // ===================================================================================================
    //
    NSString *endVersion            = [NSString stringWithFormat:@"%d", config.ghost.version.intValue + 1];
    NSString *newRemoteLog          = @"2222 Captains Log";
    NSDecimalNumber *newRemoteCost  = [NSDecimalNumber decimalNumberWithString:@"300"];
    NSNumber *newRemoteWarp         = @(10);
    
    // Prepare the change itself
    NSDictionary *entity = @{
        NSStringFromSelector(@selector(captainsLog))    : newRemoteLog,
        NSStringFromSelector(@selector(cost))           : newRemoteCost,
        NSStringFromSelector(@selector(warpSpeed))      : newRemoteWarp,
    };
    
    NSLog(@"<> Successfully generated remote change");
    
    
    // ===================================================================================================
    // Process remote changes
    // ===================================================================================================
    //
	StartBlock();
    
    dispatch_async(bucket.processorQueue, ^{
        [bucket.changeProcessor processRemoteEntityWithKey:config.simperiumKey version:endVersion data:entity bucket:bucket];
        
		dispatch_async(dispatch_get_main_queue(), ^{
			EndBlock();
		});
    });
    
	WaitUntilBlockCompletes();
    
    NSLog(@"<> Finished processing remote changes");
    
    
    // ===================================================================================================
    // Verify if the changeProcessor actually did its job
    // ===================================================================================================
    //
    
    [storage refaultObjects:@[config]];
    
    XCTAssertEqualObjects(config.captainsLog, newRemoteLog,    @"Invalid Log");
    XCTAssertEqualObjects(config.cost, newRemoteCost,          @"Invalid Cost");
    XCTAssertEqualObjects(config.warpSpeed, newRemoteWarp,     @"Invalid Warp");
    XCTAssertEqualObjects(config.ghost.version, endVersion,    @"Invalid Ghost Version");
    XCTAssertEqualObjects(config.ghost.memberData, entity,     @"Invalid Ghost MemberData");
}

@end
