//
//  SPRelationshipResolverTests.m
//  Simperium
//
//  Created by Jorge Leandro Perez on 4/17/14.
//  Copyright (c) 2014 Simperium. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "SPRelationshipResolver.h"
#import "MockStorage.h"
#import "XCTestCase+Simperium.h"
#import "NSString+Simperium.h"
#import "SPObject.h"
#import "SPBucket.h"


#pragma mark ====================================================================================
#pragma mark Constants
#pragma mark ====================================================================================

static NSString *SPTestSourceBucket     = @"SPMockSource";
static NSString *SPTestSourceAttribute  = @"sourceAttribute";

static NSString *SPTestTargetBucket     = @"SPMockTarget";
static NSString *SPTestTargetAttribute1 = @"targetAttribute1";
static NSString *SPTestTargetAttribute2 = @"targetAttribute2";

static NSString *SPLegacyPathKey        = @"SPPathKey";
static NSString *SPLegacyPathBucket     = @"SPPathBucket";
static NSString *SPLegacyPathAttribute  = @"SPPathAttribute";
static NSString *SPLegacyPendingsKey    = @"SPPendingReferences";

static NSInteger SPTestStressIterations = 1000;
static NSInteger SPTestIterations       = 100;
static NSInteger SPTestSubIterations    = 10;


#pragma mark ====================================================================================
#pragma mark Interface
#pragma mark ====================================================================================

@interface SPRelationshipResolverTests : XCTestCase
@property (nonatomic, strong) SPRelationshipResolver    *resolver;
@property (nonatomic, strong) MockStorage               *storage;
@end


#pragma mark ====================================================================================
#pragma mark SPRelationshipResolverTests!
#pragma mark ====================================================================================

@implementation SPRelationshipResolverTests

- (void)setUp
{
    [super setUp];
    self.resolver   = [SPRelationshipResolver new];
    self.storage    = [MockStorage new];
}

- (void)testSetPendingRelationships {
    
    // Set 'SPTestIterations' pending relationships
    NSMutableArray *relationships = [NSMutableArray array];
    
    for (NSInteger i = 1; i <= SPTestIterations; ++i) {
        NSString *sourceKey = [NSString sp_makeUUID];
        NSString *targetKey = [NSString sp_makeUUID];
        
        SPRelationship *pending = [SPRelationship relationshipFromObjectWithKey:sourceKey
                                                                   andAttribute:SPTestSourceAttribute
                                                                       inBucket:SPTestSourceBucket
                                                                toObjectWithKey:targetKey
                                                                       inBucket:SPTestTargetBucket];
        [self.resolver addPendingRelationship:pending];
        [relationships addObject:pending];
    }
    
    // Verify: No persistance involved
    XCTAssert( [self.resolver countPendingRelationships] == SPTestIterations, @"Inconsistency Detected" );

    for (SPRelationship *relationship in relationships) {
        
        BOOL isMapped           = [self.resolver verifyBidirectionalMappingBetweenKey:relationship.sourceKey andKey:relationship.targetKey];
        BOOL isCardinalityOkay  = [self.resolver countPendingRelationshipsWithSourceKey:relationship.sourceKey andTargetKey:relationship.targetKey] == 1;
        
        XCTAssertTrue(isMapped, @"Error in bidirectional mapping" );
        XCTAssertTrue(isCardinalityOkay, @"Error while checking pending relationships" );
    }
    
    XCTAssertTrue( [self.resolver countPendingRelationships] == SPTestIterations, @"Inconsitency Detected" );
}

- (void)testLoadingPendingRelationships {
    
    // Set 'SPTestIterations' pending relationships
    NSMutableArray *relationships = [NSMutableArray array];
    
    for (NSInteger i = 1; i <= SPTestIterations; ++i) {
        NSString *sourceKey = [NSString sp_makeUUID];
        NSString *targetKey = [NSString sp_makeUUID];
        
        SPRelationship *pending = [SPRelationship relationshipFromObjectWithKey:sourceKey
                                                                   andAttribute:SPTestSourceAttribute
                                                                       inBucket:SPTestSourceBucket
                                                                toObjectWithKey:targetKey
                                                                       inBucket:SPTestTargetBucket];
        [self.resolver addPendingRelationship:pending];
        [relationships addObject:pending];
    }
    
    // Let's save now
    [self.resolver saveWithStorage:self.storage];
    
    // ""Simulate"" App Relaunch
    self.resolver = [SPRelationshipResolver new];
    [self.resolver loadPendingRelationships:self.storage];
    
    // Verify: After Reload
    XCTAssert( [self.resolver countPendingRelationships] == SPTestIterations, @"Inconsistency Detected" );
    
    for (SPRelationship *relationship in relationships) {
        
        BOOL isMapped           = [self.resolver verifyBidirectionalMappingBetweenKey:relationship.sourceKey andKey:relationship.targetKey];
        BOOL isCardinalityOkay  = [self.resolver countPendingRelationshipsWithSourceKey:relationship.sourceKey andTargetKey:relationship.targetKey] == 1;
        
        XCTAssertTrue(isMapped, @"Error in bidirectional mapping" );
        XCTAssertTrue(isCardinalityOkay, @"Error while checking pending relationships" );
    }
    
    XCTAssertTrue( [self.resolver countPendingRelationships] == SPTestIterations, @"Inconsitency Detected" );
}

- (void)testMigrateLegacyRelationships {
    // Set 'SPTestIterations x SPTestIterations' pending legacy relationships
    NSMutableDictionary *legacy = [NSMutableDictionary dictionary];
    
    for (NSInteger i = 1; i <= SPTestIterations; ++i) {
        NSString *targetKey = [NSString sp_makeUUID];
    
        NSMutableArray *relationships = [NSMutableArray array];
        for (NSInteger j = 1; j <= SPTestSubIterations; ++j) {
            [relationships addObject: @{
                SPLegacyPathKey          : [NSString sp_makeUUID],
                SPLegacyPathBucket       : SPTestSourceBucket,
                SPLegacyPathAttribute    : SPTestSourceAttribute
            }];
        }
        
        legacy[targetKey] = relationships;
    }
    
    NSMutableDictionary *metadata   = [NSMutableDictionary dictionary];
    metadata[SPLegacyPendingsKey]   = legacy;
    self.storage.metadata           = metadata;

    // Sanity Check
    XCTAssertTrue([self.resolver countPendingRelationships] == 0, @"Inconsistency Detected");
    
    // Load + Migrate
    [self.resolver loadPendingRelationships:self.storage];
    
    XCTAssertTrue([self.resolver countPendingRelationships] == SPTestIterations * SPTestSubIterations, @"Inconsistency Detected");
 
    // Verify
    for (NSString *targetKey in [legacy allKeys]) {
        
        for (NSDictionary *legacyDescriptor in legacy[targetKey]) {
            NSString *sourceKey = legacyDescriptor[SPLegacyPathKey];
            
            XCTAssertTrue( [self.resolver verifyBidirectionalMappingBetweenKey:sourceKey andKey:targetKey], @"Inconsistency Detected" );
            XCTAssertTrue( [self.resolver countPendingRelationshipsWithSourceKey:sourceKey andTargetKey:targetKey] == 1, @"Inconsistency Detected" );
        }
    }
}

- (void)testResetPendingRelationships {
    // Set SPTestIterations pendings
    for (NSInteger i = 1; i <= SPTestIterations; ++i) {
        NSString *sourceKey = [NSString sp_makeUUID];
        NSString *targetKey = [NSString sp_makeUUID];
        
        SPRelationship *pending = [SPRelationship relationshipFromObjectWithKey:sourceKey
                                                                   andAttribute:SPTestSourceAttribute
                                                                       inBucket:SPTestSourceBucket
                                                                toObjectWithKey:targetKey
                                                                       inBucket:SPTestTargetBucket];
        [self.resolver addPendingRelationship:pending];
    }
    
    [self.resolver saveWithStorage:self.storage];
    
    // Verify
    XCTAssertTrue( [self.resolver countPendingRelationships] == SPTestIterations, @"Inconsistency detected" );

    // Reset + Verify again
    [self.resolver reset:self.storage];
    
    XCTAssertTrue( [self.resolver countPendingRelationships] == 0, @"Inconsistency detected" );
    
    // ""Simulate"" App Relaunch
    self.resolver = [SPRelationshipResolver new];
    [self.resolver loadPendingRelationships:self.storage];
    
    // After relaunch, relationships should be zero as well
    XCTAssertTrue( [self.resolver countPendingRelationships] == 0, @"Inconsistency detected" );
}

- (void)testInsertDuplicateRelationships {
    NSString *firstKey  = [NSString sp_makeUUID];
    NSString *secondKey = [NSString sp_makeUUID];

    SPRelationship *relationship1 = [SPRelationship relationshipFromObjectWithKey:firstKey
                                                                     andAttribute:SPTestTargetAttribute1
                                                                         inBucket:SPTestTargetBucket
                                                                  toObjectWithKey:secondKey
                                                                         inBucket:SPTestSourceBucket];
    
    SPRelationship *relationship2 = [SPRelationship relationshipFromObjectWithKey:firstKey
                                                                     andAttribute:SPTestTargetAttribute1
                                                                         inBucket:SPTestTargetBucket
                                                                  toObjectWithKey:secondKey
                                                                         inBucket:SPTestSourceBucket];
    
    [self.resolver addPendingRelationship:relationship1];
    [self.resolver addPendingRelationship:relationship2];
    
    XCTAssertTrue( [self.resolver countPendingRelationships] == 1, @"Inconsistency detected" );
}

- (void)testResolvePendingRelationshipWithMissingObject {
    // New Objects please
    SPObject *target            = [SPObject new];
    target.simperiumKey         = [NSString sp_makeUUID];
    
    SPObject *firstSource       = [SPObject new];
    firstSource.simperiumKey    = [NSString sp_makeUUID];

    SPObject *secondSource      = [SPObject new];
    secondSource.simperiumKey   = [NSString sp_makeUUID];

    // Set 4 pendings:  target >> firstSource + secondSource  ||  firstSource >> target  ||  secondSource >> target
    SPRelationship *relationship1 = [SPRelationship relationshipFromObjectWithKey:target.simperiumKey
                                                                     andAttribute:SPTestTargetAttribute1
                                                                         inBucket:SPTestTargetBucket
                                                                  toObjectWithKey:firstSource.simperiumKey
                                                                         inBucket:SPTestSourceBucket];

    SPRelationship *relationship2 = [SPRelationship relationshipFromObjectWithKey:target.simperiumKey
                                                                     andAttribute:SPTestTargetAttribute2
                                                                         inBucket:SPTestTargetBucket
                                                                  toObjectWithKey:secondSource.simperiumKey
                                                                         inBucket:SPTestSourceBucket];
    
    SPRelationship *relationship3 = [SPRelationship relationshipFromObjectWithKey:firstSource.simperiumKey
                                                                     andAttribute:SPTestSourceAttribute
                                                                         inBucket:SPTestSourceBucket
                                                                  toObjectWithKey:target.simperiumKey
                                                                         inBucket:SPTestTargetBucket];
    
    SPRelationship *relationship4 = [SPRelationship relationshipFromObjectWithKey:secondSource.simperiumKey
                                                                     andAttribute:SPTestSourceAttribute
                                                                         inBucket:SPTestSourceBucket
                                                                  toObjectWithKey:target.simperiumKey
                                                                         inBucket:SPTestTargetBucket];
    
    [self.resolver addPendingRelationship:relationship1];
    [self.resolver addPendingRelationship:relationship2];
    [self.resolver addPendingRelationship:relationship3];
    [self.resolver addPendingRelationship:relationship4];
    
    // Verify
    XCTAssertTrue( [self.resolver countPendingRelationships] == 4, @"Inconsistency detected" );
    XCTAssertTrue( [self.resolver verifyBidirectionalMappingBetweenKey:firstSource.simperiumKey andKey:target.simperiumKey], @"Inconsistency detected" );
    XCTAssertTrue( [self.resolver verifyBidirectionalMappingBetweenKey:secondSource.simperiumKey andKey:target.simperiumKey], @"Inconsistency detected" );
    XCTAssertTrue( [self.resolver verifyBidirectionalMappingBetweenKey:target.simperiumKey andKey:firstSource.simperiumKey], @"Inconsistency detected" );
    XCTAssertTrue( [self.resolver verifyBidirectionalMappingBetweenKey:target.simperiumKey andKey:firstSource.simperiumKey], @"Inconsistency detected" );
    
    // Insert Target
    [self.storage insertObject:target bucketName:SPTestTargetBucket];

    // NO-OP's
    [self.resolver resolvePendingRelationshipsForKey:target.simperiumKey bucketName:SPTestSourceBucket storage:self.storage];
    [self.resolver resolvePendingRelationshipsForKey:firstSource.simperiumKey bucketName:SPTestSourceBucket storage:self.storage];
    [self.resolver resolvePendingRelationshipsForKey:secondSource.simperiumKey bucketName:SPTestSourceBucket storage:self.storage];
    
    // Resolve OP is async
    [self waitFor:1.0f];
    
    // We should still have 4 relationships
    XCTAssertTrue( [self.resolver countPendingRelationships] == 4, @"Inconsistency detected" );
    
    // Insert First Source
    [self.storage insertObject:firstSource bucketName:SPTestSourceBucket];
    [self.resolver resolvePendingRelationshipsForKey:firstSource.simperiumKey bucketName:SPTestSourceBucket storage:self.storage];
    
    // Resolve OP is async
    [self waitFor:1.0f];

    // Verify
    XCTAssert([firstSource simperiumValueForKey:SPTestSourceAttribute] == target, @"Inconsistency detected" );
    XCTAssert([target simperiumValueForKey:SPTestTargetAttribute1] == firstSource, @"Inconsistency detected" );
    XCTAssertTrue( [self.resolver countPendingRelationships] == 2, @"Inconsistency detected" );
    XCTAssertFalse([self.resolver verifyBidirectionalMappingBetweenKey:target.simperiumKey andKey:firstSource.simperiumKey], @"Inconsistency detected");
    
    // Insert Second Source
    [self.storage insertObject:secondSource bucketName:SPTestSourceBucket];
    [self.resolver resolvePendingRelationshipsForKey:secondSource.simperiumKey bucketName:SPTestSourceBucket storage:self.storage];

    // Resolve OP is async
    [self waitFor:1.0f];
    
    // Verify
    XCTAssert([secondSource simperiumValueForKey:SPTestSourceAttribute] == target, @"Inconsistency detected" );
    XCTAssert([target simperiumValueForKey:SPTestTargetAttribute2] == secondSource, @"Inconsistency detected" );
    XCTAssertFalse([self.resolver verifyBidirectionalMappingBetweenKey:target.simperiumKey andKey:secondSource.simperiumKey], @"Inconsistency detected");
    XCTAssertTrue( [self.resolver countPendingRelationships] == 0, @"Inconsistency detected" );
}

- (void)testStressRelationshipResolver {
    
    // Create 'SPTestStressIterations x SPTestStressIterations' objects, and establish a relationship between them
    NSMutableArray *sourceObjects = [NSMutableArray array];
    NSMutableArray *targetObjects = [NSMutableArray array];
    
    for (NSInteger i = 1; i <= SPTestStressIterations; ++i) {
        
        // New Objects please
        SPObject *target    = [SPObject new];
        target.simperiumKey = [NSString sp_makeUUID];
        
        SPObject *source    = [SPObject new];
        source.simperiumKey = [NSString sp_makeUUID];
        
        // Keep them
        [sourceObjects addObject:source];
        [targetObjects addObject:target];
        
        // Set Relationship: Source >> Target
        SPRelationship *relationship = [SPRelationship relationshipFromObjectWithKey:source.simperiumKey
                                                                         andAttribute:SPTestSourceAttribute
                                                                             inBucket:SPTestSourceBucket
                                                                      toObjectWithKey:target.simperiumKey
                                                                             inBucket:SPTestTargetBucket];
        
        [self.resolver addPendingRelationship:relationship];
    }
    
    // Verify if the relationships were correctly established
    XCTAssertTrue( [self.resolver countPendingRelationships] == SPTestStressIterations, @"Inconsistency detected" );
    
    // Helper Structures
    char *sourceLabel               = [@"com.simperium.source" cStringUsingEncoding:NSUTF8StringEncoding];
    char *targetLabel               = [@"com.simperium.target" cStringUsingEncoding:NSUTF8StringEncoding];
    dispatch_queue_t sourceQueue    = dispatch_queue_create(sourceLabel, NULL);
    dispatch_queue_t targetQueue    = dispatch_queue_create(targetLabel, NULL);
	dispatch_group_t group          = dispatch_group_create();

    // Insert Source Objects, asynchronously, and hit resolve on the main thread
    dispatch_group_enter(group);
    dispatch_async(sourceQueue, ^{
        
        for (SPObject *object in sourceObjects) {
            [self.storage insertObject:object bucketName:SPTestSourceBucket];
            
            dispatch_group_enter(group);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.resolver resolvePendingRelationshipsForKey:object.simperiumKey
                                                      bucketName:SPTestSourceBucket
                                                         storage:self.storage
                                                      completion:^{
                                                          dispatch_group_leave(group);
                                                      }];
            });
        }
        
        NSLog(@">> Finished inserting Source Objects");
        dispatch_group_leave(group);
    });

    // Insert Target Objects, asynchronously, and hit resolve on the main thread
    dispatch_group_enter(group);
    dispatch_async(targetQueue, ^{

        for (SPObject *object in targetObjects) {
            [self.storage insertObject:object bucketName:SPTestTargetBucket];

            dispatch_group_enter(group);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.resolver resolvePendingRelationshipsForKey:object.simperiumKey
                                                      bucketName:SPTestTargetBucket
                                                         storage:self.storage
                                                      completion:^{
                                                          dispatch_group_leave(group);
                                                      }];
            });
        }
        
        NSLog(@">> Finished inserting Target Objects");
        dispatch_group_leave(group);
    });
    
    // Wait for completion and verify
    StartBlock();
	dispatch_group_notify(group, dispatch_get_main_queue(), ^ {
        
        NSLog(@">> Begins checking integrity");
        
        for (NSInteger i = 0; i < sourceObjects.count; ++ i) {
            SPObject *source = sourceObjects[i];
            SPObject *target = targetObjects[i];
            XCTAssert([source simperiumValueForKey:SPTestSourceAttribute] == target, @"Inconsistency detected" );
        }

        XCTAssertTrue([self.resolver countPendingRelationships] == 0, @"Inconsistency detected");
        EndBlock();
    });
    
    WaitUntilBlockCompletes();
}

@end
