/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "XCUIElement+FBUtilities.h"

#import "FBAlert.h"
#import "FBLogger.h"
#import "FBMacros.h"
#import "FBMathUtils.h"
#import "FBRunLoopSpinner.h"
#import "XCAXClient_iOS.h"
#import "XCUIElement+FBWebDriverAttributes.h"

@implementation XCUIElement (FBUtilities)

static const NSTimeInterval FBANIMATION_TIMEOUT = 5.0;

- (BOOL)fb_waitUntilFrameIsStable
{
  __block CGRect frame;
  // Initial wait
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
  return
  [[[FBRunLoopSpinner new]
     timeout:10.]
   spinUntilTrue:^BOOL{
     [self resolve];
     const BOOL isSameFrame = FBRectFuzzyEqualToRect(self.wdFrame, frame, FBDefaultFrameFuzzyThreshold);
     frame = self.wdFrame;
     return isSameFrame;
   }];
}

- (BOOL)fb_isObstructedByAlert
{
  return [[FBAlert alertWithApplication:self.application].alertElement fb_obstructsElement:self];
}

- (BOOL)fb_obstructsElement:(XCUIElement *)element
{
  if (!self.exists) {
    return NO;
  }
  [self resolve];
  [element resolve];
  if ([self.lastSnapshot _isAncestorOfElement:element.lastSnapshot]) {
    return NO;
  }
  if ([self.lastSnapshot _matchesElement:element.lastSnapshot]) {
    return NO;
  }
  return YES;
}

- (XCElementSnapshot *)fb_lastSnapshot
{
  if (self.lastSnapshot) {
    return self.lastSnapshot;
  }
  [self resolve];
  return self.lastSnapshot;
}

- (NSArray<XCUIElement *> *)fb_filterDescendantsWithSnapshots:(NSArray<XCElementSnapshot *> *)snapshots
{
  if (0 == snapshots.count) {
    return @[];
  }
  NSArray<NSNumber *> *matchedUids = [snapshots valueForKey:FBStringify(XCUIElement, wdUID)];
  XCUIElementType type = XCUIElementTypeAny;
  NSArray<NSNumber *> *uniqueTypes = [snapshots valueForKeyPath:[NSString stringWithFormat:@"@distinctUnionOfObjects.%@", FBStringify(XCUIElement, elementType)]];
  if (uniqueTypes && [uniqueTypes count] == 1) {
    type = [uniqueTypes.firstObject intValue];
  }
  NSArray<XCUIElement *> *filteredElements = [[self descendantsMatchingType:type] matchingPredicate:[NSPredicate predicateWithFormat:@"%K IN %@", FBStringify(XCUIElement, wdUID), matchedUids]].allElementsBoundByIndex;
  if (filteredElements.count <= 1) {
    // There is no need to sort elements if count of matches is not greater than one
    return filteredElements;
  }
  NSMutableArray<XCUIElement *> *sortedElements = [NSMutableArray array];
  NSMutableArray<XCUIElement *> *unmatchedElements = [filteredElements mutableCopy];
  [snapshots enumerateObjectsUsingBlock:^(XCElementSnapshot *snapshot, NSUInteger snapshotIdx, BOOL *stopSnapshotEnum) {
    XCUIElement *matchedElement = nil;
    for (XCUIElement *element in unmatchedElements) {
      if (element.wdUID == snapshot.wdUID) {
        matchedElement = element;
        break;
      }
    }
    if (matchedElement) {
      [sortedElements addObject:matchedElement];
      [unmatchedElements removeObject:matchedElement];
    }
  }];
  return sortedElements.copy;
}

- (BOOL)fb_waitUntilSnapshotIsStable
{
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);
  [[XCAXClient_iOS sharedClient] notifyWhenNoAnimationsAreActiveForApplication:self.application reply:^{dispatch_semaphore_signal(sem);}];
  dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(FBANIMATION_TIMEOUT * NSEC_PER_SEC));
  BOOL result = 0 == dispatch_semaphore_wait(sem, timeout);
  if (!result) {
    [FBLogger logFmt:@"There are still some active animations in progress after %.2f seconds timeout. Visibility detection may cause unexpected delays.", FBANIMATION_TIMEOUT];
  }
  return result;
}

@end
