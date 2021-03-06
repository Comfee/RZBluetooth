//
//  RZBSimulatedTests.m
//  RZBluetooth
//
//  Created by Brian King on 8/6/15.
//  Copyright (c) 2015 Raizlabs. All rights reserved.
//

#import "RZBSimulatedTestCase.h"
#import "RZBPeripheral+RZBBattery.h"
#import "RZBSimulatedDevice+RZBBatteryLevel.h"
#import "CBUUID+RZBPublic.h"

@interface RZBSimulatedTests : RZBSimulatedTestCase <RZBPeripheralConnectionDelegate>

@property (nonatomic, assign) NSUInteger connectCount;
@property (nonatomic, assign) NSUInteger connectFailureCount;
@property (nonatomic, assign) NSUInteger disconnectCount;

@end

@implementation RZBSimulatedTests

- (void)peripheral:(RZBPeripheral *)peripheral connectionEvent:(RZBPeripheralStateEvent)event error:(NSError *)error;
{
    switch (event) {
        case RZBPeripheralStateEventConnectSuccess:
            self.connectCount++;
            break;
        case RZBPeripheralStateEventConnectFailure:
            self.connectFailureCount++;
            break;
        case RZBPeripheralStateEventDisconnected:
            self.disconnectCount++;
            break;
    }
}

- (void)testScanForDevices
{
    XCTestExpectation *discovered = [self expectationWithDescription:@"Peripheral will connect"];

    [self.centralManager scanForPeripheralsWithServices:nil
                                                options:nil
                                 onDiscoveredPeripheral:^(RZBScanInfo *scanInfo, NSError *error) {
                                     [discovered fulfill];
                                     XCTAssert([scanInfo.peripheral.identifier isEqual:self.connection.identifier]);
                                 }];
    [self.device.peripheralManager startAdvertising:@{}];

    [self waitForExpectationsWithTimeout:5.0 handler:nil];
    [self.centralManager stopScan];
}

- (void)testConnection
{
    XCTestExpectation *connected = [self expectationWithDescription:@"Peripheral will connect"];
    RZBPeripheral *peripheral = [self.centralManager peripheralForUUID:self.connection.identifier];
    [peripheral connectWithCompletion:^(NSError * _Nullable error) {
        [connected fulfill];
        XCTAssert([peripheral.identifier isEqual:self.connection.identifier]);
    }];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testConnectionError
{
    XCTestExpectation *connected = [self expectationWithDescription:@"Peripheral will connect"];
    self.connection.connectCallback.injectError = [NSError rzb_connectionError];
    RZBPeripheral *peripheral = [self.centralManager peripheralForUUID:self.connection.identifier];
    [peripheral connectWithCompletion:^(NSError * _Nullable error) {
        [connected fulfill];
        XCTAssertNotNil(error);
        XCTAssert([peripheral.identifier isEqual:self.connection.identifier]);
    }];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testConnectable
{
    XCTestExpectation *connected = [self expectationWithDescription:@"Peripheral will connect"];
    RZBPeripheral *peripheral = [self.centralManager peripheralForUUID:self.connection.identifier];
    XCTAssert(peripheral.state == CBPeripheralStateDisconnected);
    self.connection.connectable = NO;

    [peripheral connectWithCompletion:^(NSError * _Nullable error) {
        [connected fulfill];
        XCTAssert([peripheral.identifier isEqual:self.connection.identifier]);
    }];
    [self waitForQueueFlush];
    XCTAssert(peripheral.state == CBPeripheralStateConnecting);

    self.connection.connectable = YES;
    XCTAssert(peripheral.state == CBPeripheralStateConnecting);

    [self waitForExpectationsWithTimeout:5.0 handler:nil];
    XCTAssert(peripheral.state == CBPeripheralStateConnected);
}

- (void)testConnectionAndCancelWhileNotConnectable
{
    XCTestExpectation *connectCallback = [self expectationWithDescription:@"Connect Callback"];
    XCTestExpectation *cancelConnectCallback = [self expectationWithDescription:@"Connect Cancelation Callback"];

    RZBPeripheral *peripheral = [self.centralManager peripheralForUUID:self.connection.identifier];
    XCTAssert(peripheral.state == CBPeripheralStateDisconnected);
    self.connection.connectable = NO;

    [peripheral connectWithCompletion:^(NSError *error) {
        XCTAssertNil(error);
        [connectCallback fulfill];
    }];
    [self waitForQueueFlush];
    XCTAssert(peripheral.state == CBPeripheralStateConnecting);

    [peripheral cancelConnectionWithCompletion:^(NSError *error) {
        XCTAssertNil(error);
        [cancelConnectCallback fulfill];
    }];
    [self waitForQueueFlush];

    self.connection.connectable = YES;
    [self waitForQueueFlush];
    XCTAssert(peripheral.state == CBPeripheralStateDisconnected);

    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testMaintainConnection
{
    self.disconnectCount = 0;
    self.connectCount = 0;
    self.connectFailureCount = 0;
    RZBPeripheral *p = [self.centralManager peripheralForUUID:self.connection.identifier];
    XCTAssert(p.state == CBPeripheralStateDisconnected);
    self.connection.connectable = NO;
    p.connectionDelegate = self;
    p.maintainConnection = YES;

#define TEST_COUNT 10
    for (NSUInteger i = 0; i < TEST_COUNT; i++) {
        [self waitForQueueFlush];
        XCTAssert(p.state == CBPeripheralStateConnecting);

        self.connection.connectable = YES;
        [self waitForQueueFlush];
        XCTAssert(p.state == CBPeripheralStateConnected);
        XCTAssert(self.connectCount == i + 1);

        // Disable the connection maintenance on the last iteration.
        if (i == TEST_COUNT - 1) {
            [p cancelConnectionWithCompletion:nil];
        }
        else {
            self.connection.connectable = NO;
        }
        [self waitForQueueFlush];
        XCTAssert(self.disconnectCount == i + 1);
    }
    [self waitForQueueFlush];
    XCTAssert(p.state == CBPeripheralStateDisconnected);
    XCTAssert(self.connectFailureCount == 0);
}

- (void)testStateBounce
{
    [self.device addBatteryService];

    // Configure the peripheral, set up the observer, and wait for connection
    RZBPeripheral *p = [self.centralManager peripheralForUUID:self.connection.identifier];
    XCTAssert(p.state == CBPeripheralStateDisconnected);
    p.connectionDelegate = self;
    p.maintainConnection = YES;
    NSMutableArray *values = [NSMutableArray array];
    [p addBatteryLevelObserver:^(NSUInteger level, NSError *error) {
        [values addObject:@(level)];
    } completion:^(NSError *error) {
    }];
    [self waitForQueueFlush];
    XCTAssert(p.state == CBPeripheralStateConnected);

    self.connection.connectable = NO;
    [self waitForQueueFlush];
    XCTAssert(p.state == CBPeripheralStateConnecting);

    [self.mockCentralManager fakeStateChange:CBManagerStatePoweredOff];
    [self.connection reset];
    [self waitForQueueFlush];

    [self.mockCentralManager fakeStateChange:CBManagerStatePoweredOn];
    self.connection.connectable = YES;
    [self waitForQueueFlush];

    [p addBatteryLevelObserver:^(NSUInteger level, NSError *error) {
        [values addObject:@(level)];
    } completion:^(NSError *error) {
    }];
    [self waitForQueueFlush];
    XCTAssert(p.state == CBPeripheralStateConnected);
    
    // Change the battery level and ensure the observer is notified of the new battery level
    self.device.batteryLevel = 88;
    [self waitForQueueFlush];
    XCTAssertEqualObjects(values, @[@88]);

}

@end
