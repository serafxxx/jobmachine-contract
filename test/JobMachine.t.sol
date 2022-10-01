// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/JobMachine.sol";

contract JobMachineTest is Test {
    JobMachine public jobmachine;
    address payable contractOwner = payable(address(0x100));
    address admin = address(0x101);
    address payable owner = payable(address(0x102));
    address payable customer = payable(address(0x103));
    address payable contractor = payable(address(0x104));
    address payable unknownPerson = payable(address(0x105));
    address payable resolver1 = payable(address(0x106));
    address payable resolver2 = payable(address(0x107));
    address payable resolver3 = payable(address(0x108));
    address payable resolver4 = payable(address(0x109));
    uint160 jobId;
    uint160 unexpectedJobId;
    
    function setUp() public {
        vm.deal(contractOwner, 10000);
        vm.deal(owner, 10000);
        vm.deal(customer, 10000);
        vm.deal(contractor, 10000);
        vm.deal(unknownPerson, 10000);
        vm.startPrank(contractOwner);
        jobmachine = new JobMachine();
        jobmachine.setJobMintFee(100);
        jobmachine.setAdmin(admin);
        vm.stopPrank();
    }

    function testSetJobMintFee() public{
        vm.prank(contractOwner);
        jobmachine.setJobMintFee(10);
        assertEq(jobmachine.jobMintFee(), 10);

        vm.prank(owner);
        vm.expectRevert(Unauthorized.selector);
        jobmachine.setJobMintFee(10);
    }

    function makeJob() public{
        vm.prank(owner);
        jobId = jobmachine.mintJob{value:100}({
            _customer: customer, 
            _contractor: contractor, 
            _reviewEnabled: false,
            _disputeEnabled: false,
            _rewardTarget: 5000, 
            _deadlineFineTarget: 1000,
            _metadataHash: bytes32(uint256(0x60)),
            timersConfig: JobMachine.TimersConfig({
                initial: 0,
                work: 0,
                reviewInitial: 0
            })
        });
    }

    function gotoWork() public{
        vm.startPrank(customer);
        jobmachine.fundReward{value:5000}(jobId);
        jobmachine.signAsCustomer(jobId);
        vm.stopPrank();

        vm.startPrank(contractor);
        jobmachine.fundDeadlineFine{value:1000}(jobId);
        jobmachine.signAsContractor(jobId);
        jobmachine.gotoWork(jobId);
        vm.stopPrank();
    }

    function testMintJob() public{
        makeJob();
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Initial));
        assertEq(jobmachine.owner(jobId), owner);
        assertEq(jobmachine.customer(jobId), customer);
        assertEq(jobmachine.contractor(jobId), contractor);
        assertEq(jobmachine.reviewEnabled(jobId), false);
        assertEq(jobmachine.disputeEnabled(jobId), false);
        assertEq(jobmachine.rewardTarget(jobId), 5000);
        assertEq(jobmachine.deadlineFineTarget(jobId), 1000);
        assertEq(jobmachine.metadataHash(jobId), bytes32(uint256(0x60)));
        assertEq(jobmachine.customerSigned(jobId), false);
        assertEq(jobmachine.contractorSigned(jobId), false);
    }

    function testMintJobFeePaid() public{
        uint contractOwnerBalance = contractOwner.balance;
        makeJob();
        assertEq(contractOwner.balance, contractOwnerBalance + jobmachine.jobMintFee());
    }

    function testMintUnsufficentFunds() public{
        vm.prank(owner);
        vm.expectRevert(UnsufficentFunds.selector);
        jobId = jobmachine.mintJob{value:99}({
            _customer: customer, 
            _contractor: contractor, 
            _reviewEnabled: false,
            _disputeEnabled: false,
            _rewardTarget: 5000, 
            _deadlineFineTarget: 1000,
            _metadataHash: bytes32(uint256(0x60)),
            timersConfig: JobMachine.TimersConfig({
                initial: 0,
                work: 0,
                reviewInitial: 0
            })
        });
    }

    // function testMintMany() public{
    //     makeJob();
    //     makeJob();
    //     makeJob();
    // }

    function testSetCustomer() public{
        // TODO: Test while not in Initial state
        makeJob();
        signAsCustomer();
        signAsContractor();

        // Change customer
        vm.prank(owner);
        address payable newCustomer = payable(address(4));
        jobmachine.customer(jobId, newCustomer);

        assertEq(jobmachine.customer(jobId), newCustomer);
        // Customers signature should be discarded
        assertEq(jobmachine.customerSigned(jobId), false);
        // Contractors signature shouldn't be discarded
        assertEq(jobmachine.contractorSigned(jobId), true);

        vm.prank(customer);
        vm.expectRevert(Unauthorized.selector);
        jobmachine.customer(jobId, customer);
    }

    function testSetContractor() public{
        // TODO: Test while not in Initial state
        makeJob();
        signAsCustomer();
        signAsContractor();

        // Change contractor
        vm.prank(owner);
        address payable newContractor = payable(address(4));
        jobmachine.contractor(jobId, newContractor);
        assertEq(jobmachine.contractor(jobId), newContractor);
        // Contractor's signature should be discarded
        assertEq(jobmachine.contractorSigned(jobId), false);
        // Customer's signature should be preserved
        assertEq(jobmachine.customerSigned(jobId), true);

        vm.prank(customer);
        vm.expectRevert(Unauthorized.selector);
        jobmachine.contractor(jobId, contractor);
    }

    function testSetreviewEnabled() public{
        makeJob();
        assertEq(jobmachine.reviewEnabled(jobId), false);
        vm.prank(owner);
        jobmachine.reviewEnabled(jobId, true);
        assertEq(jobmachine.reviewEnabled(jobId), true);
        gotoWork();
        assertEq(jobmachine.reviewEnabled(jobId), true);

        vm.prank(owner);
        vm.expectRevert(UnauthorizedState.selector);
        jobmachine.reviewEnabled(jobId, false);
        
    }

    function signAsCustomer() public{
        vm.prank(customer);
        jobmachine.signAsCustomer(jobId);
    }

    function signAsContractor() public{
        vm.prank(contractor);
        jobmachine.signAsContractor(jobId);
    }

    function testSetReward() public{
        // TODO: Test while not in Initial state
        makeJob();
        assertEq(jobmachine.rewardTarget(jobId), 5000);
        signAsCustomer();
        signAsContractor();
        vm.prank(owner);
        jobmachine.rewardTarget(jobId, 6000);
        assertEq(jobmachine.rewardTarget(jobId), 6000);
        assertEq(jobmachine.customerSigned(jobId), false);
        assertEq(jobmachine.contractorSigned(jobId), false);

        vm.prank(customer);
        vm.expectRevert(Unauthorized.selector);
        jobmachine.rewardTarget(jobId, 7000);
    }

    function testSetDeadlineFine() public{
        // TODO: Test while not in Initial state
        makeJob();
        assertEq(jobmachine.deadlineFineTarget(jobId), 1000);
        signAsCustomer();
        signAsContractor();
        vm.prank(owner);
        jobmachine.deadlineFineTarget(jobId, 1500);
        assertEq(jobmachine.deadlineFineTarget(jobId), 1500);
        assertEq(jobmachine.customerSigned(jobId), false);
        assertEq(jobmachine.contractorSigned(jobId), false);

        vm.prank(customer);
        vm.expectRevert(Unauthorized.selector);
        jobmachine.deadlineFineTarget(jobId, 2000);
    }

    function testSetMetadataHash() public{
        // TODO: Test while not in Initial state
        makeJob();
        assertEq(jobmachine.metadataHash(jobId), bytes32(uint256(0x60)));
        signAsCustomer();
        signAsContractor();
        vm.prank(owner);
        jobmachine.metadataHash(jobId, bytes32(uint256(0x61)));
        assertEq(jobmachine.metadataHash(jobId), bytes32(uint256(0x61)));
        assertEq(jobmachine.customerSigned(jobId), false);
        assertEq(jobmachine.contractorSigned(jobId), false);

        vm.prank(customer);
        vm.expectRevert(Unauthorized.selector);
        jobmachine.metadataHash(jobId, bytes32(uint256(0x62)));
    }

    function testSetResultHash() public{
        makeJob();
        assertEq(jobmachine.resultHash(jobId), bytes32(uint256(0x0)));
        signAsCustomer();
        signAsContractor();
        vm.prank(owner);
        vm.expectRevert(Unauthorized.selector);
        jobmachine.resultHash(jobId, bytes32(uint256(0x61)));
        vm.prank(customer);
        vm.expectRevert(Unauthorized.selector);
        jobmachine.resultHash(jobId, bytes32(uint256(0x61)));

        assertEq(jobmachine.resultHash(jobId), bytes32(uint256(0x0)));

        vm.prank(contractor);
        vm.expectRevert(UnauthorizedState.selector);
        jobmachine.resultHash(jobId, bytes32(uint256(0x61)));

        gotoWork();
        vm.prank(contractor);
        jobmachine.resultHash(jobId, bytes32(uint256(0x62)));
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Work));
        assertEq(jobmachine.resultHash(jobId), bytes32(uint256(0x62)));
    }

    function testSignAsCustomer() public{
        makeJob();
        signAsCustomer();
        assertEq(jobmachine.customerSigned(jobId), true);

        vm.prank(customer);
        vm.expectRevert(Unauthorized.selector);
        jobmachine.signAsCustomer(unexpectedJobId);

        vm.prank(contractor);
        vm.expectRevert(Unauthorized.selector);
        jobmachine.signAsCustomer(jobId);
    }

    function testSignAsContractor() public{
        makeJob();
        signAsContractor();
        assertEq(jobmachine.contractorSigned(jobId), true);

        vm.prank(contractor);
        vm.expectRevert(Unauthorized.selector);
        jobmachine.signAsContractor(unexpectedJobId);

        vm.prank(customer);
        vm.expectRevert(Unauthorized.selector);
        jobmachine.signAsContractor(jobId);
    }

    function testFundRefund() public{
        makeJob();
        vm.prank(owner);
        jobmachine.fundReward{value:100}(jobId);
        assertEq(jobmachine.rewardBalance(jobId), 100);
        assertEq(jobmachine.rewardFunder(jobId), owner);

        // Topup
        vm.prank(owner);
        jobmachine.fundReward{value:50}(jobId);
        assertEq(jobmachine.rewardBalance(jobId), 150);
        assertEq(jobmachine.rewardFunder(jobId), owner);
        
        // Only one funder allowed
        vm.prank(customer);
        vm.expectRevert(MultipleFundersNotAllowed.selector);
        jobmachine.fundReward{value:50}(jobId);
        assertEq(jobmachine.rewardFunder(jobId), owner);

        // Refund
        vm.prank(owner);
        jobmachine.refundReward(jobId, 100);
        assertEq(jobmachine.rewardBalance(jobId), 50);
        assertEq(jobmachine.rewardFunder(jobId), owner);

        // Try to refund too much
        vm.prank(owner);
        vm.expectRevert(UnsufficentFunds.selector);
        jobmachine.refundReward(jobId, 100);
        assertEq(jobmachine.rewardBalance(jobId), 50);
        assertEq(jobmachine.rewardFunder(jobId), owner);

        // Put balance to zero
        vm.prank(owner);
        jobmachine.refundReward(jobId, 50);
        assertEq(jobmachine.rewardBalance(jobId), 0);
        assertEq(jobmachine.rewardFunder(jobId), owner);

        // Fund by customer
        vm.prank(customer);
        jobmachine.fundReward{value:100}(jobId);
        assertEq(jobmachine.rewardBalance(jobId), 100);
        assertEq(jobmachine.rewardFunder(jobId), customer);
        // Refund by customer
        vm.prank(customer);
        jobmachine.refundReward(jobId, 100);
        assertEq(jobmachine.rewardBalance(jobId), 0);
        assertEq(jobmachine.rewardFunder(jobId), customer);

        // Fund by anybody
        vm.prank(unknownPerson);
        jobmachine.fundReward{value:100}(jobId);
        assertEq(jobmachine.rewardBalance(jobId), 100);
        assertEq(jobmachine.rewardFunder(jobId), unknownPerson);

        // Refund by customer should fail
        vm.prank(customer);
        vm.expectRevert(Unauthorized.selector);
        jobmachine.refundReward(jobId, 100);
        assertEq(jobmachine.rewardBalance(jobId), 100);
        assertEq(jobmachine.rewardFunder(jobId), unknownPerson);

        // Refund by oner should work
        uint balance = unknownPerson.balance;
        vm.prank(owner);
        jobmachine.refundReward(jobId, 100);
        assertEq(jobmachine.rewardBalance(jobId), 0);
        assertEq(unknownPerson.balance, balance+100);
    }

    function testFundDeadlineFine() public{
        makeJob();
        vm.prank(owner);
        jobmachine.fundDeadlineFine{value:100}(jobId);
        assertEq(jobmachine.deadlineFineBalance(jobId), 100);
        assertEq(jobmachine.deadlineFineFunder(jobId), owner);

        // Topup
        vm.prank(owner);
        jobmachine.fundDeadlineFine{value:50}(jobId);
        assertEq(jobmachine.deadlineFineBalance(jobId), 150);
        assertEq(jobmachine.deadlineFineFunder(jobId), owner);
        
        // Only one funder allowed
        vm.prank(customer);
        vm.expectRevert(MultipleFundersNotAllowed.selector);
        jobmachine.fundDeadlineFine{value:50}(jobId);
        assertEq(jobmachine.deadlineFineFunder(jobId), owner);

        // Refund
        vm.prank(owner);
        jobmachine.refundDeadlineFine(jobId, 100);
        assertEq(jobmachine.deadlineFineBalance(jobId), 50);
        assertEq(jobmachine.deadlineFineFunder(jobId), owner);

        // Try to refund too much
        vm.prank(owner);
        vm.expectRevert(UnsufficentFunds.selector);
        jobmachine.refundDeadlineFine(jobId, 100);
        assertEq(jobmachine.deadlineFineBalance(jobId), 50);
        assertEq(jobmachine.deadlineFineFunder(jobId), owner);

        // Put balance to zero
        vm.prank(owner);
        jobmachine.refundDeadlineFine(jobId, 50);
        assertEq(jobmachine.deadlineFineBalance(jobId), 0);
        assertEq(jobmachine.deadlineFineFunder(jobId), owner);

        // Fund by customer
        vm.prank(customer);
        jobmachine.fundDeadlineFine{value:100}(jobId);
        assertEq(jobmachine.deadlineFineBalance(jobId), 100);
        assertEq(jobmachine.deadlineFineFunder(jobId), customer);
        // Refund by customer
        vm.prank(customer);
        jobmachine.refundDeadlineFine(jobId, 100);
        assertEq(jobmachine.deadlineFineBalance(jobId), 0);
        assertEq(jobmachine.deadlineFineFunder(jobId), customer);

        // Fund by anybody
        vm.prank(unknownPerson);
        jobmachine.fundDeadlineFine{value:100}(jobId);
        assertEq(jobmachine.deadlineFineBalance(jobId), 100);
        assertEq(jobmachine.deadlineFineFunder(jobId), unknownPerson);

        // Refund by customer should fail
        vm.prank(customer);
        vm.expectRevert(Unauthorized.selector);
        jobmachine.refundDeadlineFine(jobId, 100);
        assertEq(jobmachine.deadlineFineBalance(jobId), 100);
        assertEq(jobmachine.deadlineFineFunder(jobId), unknownPerson);

        // Refund by oner should work
        uint balance = unknownPerson.balance;
        vm.prank(owner);
        jobmachine.refundDeadlineFine(jobId, 100);
        assertEq(jobmachine.deadlineFineBalance(jobId), 0);
        assertEq(unknownPerson.balance, balance+100);
    }

    function testGotoWork() public {
        makeJob();
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Initial));

        vm.expectRevert(MissingPartySignature.selector);
        jobmachine.gotoWork(jobId);

        vm.prank(customer);
        jobmachine.signAsCustomer(jobId);
        vm.expectRevert(MissingPartySignature.selector);
        vm.prank(customer);
        jobmachine.gotoWork(jobId);
        
        vm.prank(contractor);
        jobmachine.signAsContractor(jobId);
        // Now everything is signed but no funds
        vm.expectRevert(UnsufficentFunds.selector);
        vm.prank(contractor);
        jobmachine.gotoWork(jobId);

        vm.prank(customer);
        jobmachine.fundReward{value:4500}(jobId);
        vm.expectRevert(UnsufficentFunds.selector);
        vm.prank(customer);
        jobmachine.gotoWork(jobId);

        vm.prank(contractor);
        jobmachine.fundDeadlineFine{value:500}(jobId);
        vm.expectRevert(UnsufficentFunds.selector);
        vm.prank(customer);
        jobmachine.gotoWork(jobId);

        vm.prank(customer);
        jobmachine.fundReward{value:500}(jobId);
        vm.expectRevert(UnsufficentFunds.selector);
        vm.prank(customer);
        jobmachine.gotoWork(jobId);

        vm.prank(contractor);
        jobmachine.fundDeadlineFine{value:500}(jobId);
        vm.prank(customer);
        jobmachine.gotoWork(jobId);
        
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Work));
    }

    function testTimerWork() public {
        makeJob();
        assertEq(jobmachine.timerWork(jobId), 0);

        // Only owner could set timer
        vm.expectRevert(Unauthorized.selector);
        vm.prank(customer);
        jobmachine.timerWork(jobId, 1 days);

        vm.prank(owner);
        jobmachine.timerWork(jobId, 1 days);

        gotoWork();
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Work));

        assertEq(jobmachine.timerWork(jobId), 1 days);

        uint timer = jobmachine.timerWork(jobId);
        uint timestamp = jobmachine.timerTimestamp(jobId);
        // 100 sec later
        vm.warp(timestamp + 100);
        jobmachine.tick(jobId);
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Work));
        assertEq(jobmachine.timerWork(jobId), timer-100);

        // Day later minus one sec
        vm.warp(timestamp + 1 days - 1);
        jobmachine.tick(jobId);
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Work));
        assertEq(jobmachine.timerWork(jobId), timer - 1 days + 1);

        // Deadline
        uint customerBalance = customer.balance;
        uint contractorBalance = contractor.balance;
        vm.warp(timestamp + 1 days);
        jobmachine.tick(jobId);
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Fail));
        assertEq(jobmachine.timerWork(jobId), 0);
        assertEq(jobmachine.rewardBalance(jobId), 0);
        assertEq(jobmachine.deadlineFineBalance(jobId), 0);
        assertEq(customer.balance, customerBalance + 5000 + 1000 );
        assertEq(contractor.balance, contractorBalance);
    }

    function testTimerWork2() public {
        // Try to go to success after deadline
        makeJob();
        vm.prank(owner);
        jobmachine.timerWork(jobId, 1 days);
        gotoWork();

        uint customerBalance = customer.balance;
        uint contractorBalance = contractor.balance;
        uint timestamp = jobmachine.timerTimestamp(jobId);
        vm.warp(timestamp + 2 days);
        vm.prank(contractor);
        jobmachine.gotoSuccess(jobId);
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Fail));
        assertEq(jobmachine.timerWork(jobId), 0);
        assertEq(jobmachine.rewardBalance(jobId), 0);
        assertEq(jobmachine.deadlineFineBalance(jobId), 0);
        assertEq(customer.balance, customerBalance + 5000 + 1000 );
        assertEq(contractor.balance, contractorBalance);
    }

    function testTimerWork3() public {
        // Zero deadline fine
        vm.startPrank(customer);
        jobId = jobmachine.mintJob{value:100}({
            _customer: customer, 
            _contractor: contractor, 
            _reviewEnabled: false,
            _disputeEnabled: false,
            _rewardTarget: 5000, 
            _deadlineFineTarget: 0,
            _metadataHash: bytes32(uint256(0x60)),
            timersConfig: JobMachine.TimersConfig({
                initial: 0,
                work: 0,
                reviewInitial: 0
            })
        });
        jobmachine.fundReward{value:5000}(jobId);
        jobmachine.signAsCustomer(jobId);
        vm.stopPrank();
        vm.startPrank(contractor);
        jobmachine.signAsContractor(jobId);
        jobmachine.gotoWork(jobId);
        jobmachine.resultHash(jobId, bytes32(uint256(0x60)));
        uint timestamp = jobmachine.timerTimestamp(jobId);
        uint customerBalance = customer.balance;
        uint contractorBalance = contractor.balance;
        vm.warp(timestamp + 2 days);
        jobmachine.gotoSuccess(jobId);
        vm.stopPrank();
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Success));
        assertEq(jobmachine.rewardBalance(jobId), 0);
        assertEq(jobmachine.deadlineFineBalance(jobId), 0);
        assertEq(customer.balance, customerBalance);
        assertEq(contractor.balance, contractorBalance + 5000);
    }

    function testGotoSuccess() public {
        makeJob();
        // Can't move to Success from Initial
        vm.prank(contractor);
        jobmachine.gotoSuccess(jobId);
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Initial));
        gotoWork();

        vm.prank(contractor);
        jobmachine.resultHash(jobId, bytes32(uint256(0x60)));
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Work));
        vm.prank(contractor);
        jobmachine.gotoSuccess(jobId);
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Success));
    }

    function testCustomerShortcutToSuccess1() public {
        // Customer could trancision from Work to Success
        makeJob();
        gotoWork();
        vm.prank(customer);
        jobmachine.gotoSuccess(jobId);
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Success));
    }

    function testCustomerShortcutToSuccess2() public {
        // Customer could trancision from Work to Success
        makeJob();
        vm.prank(owner);
        jobmachine.reviewEnabled(jobId, true);
        gotoWork();
        vm.prank(customer);
        jobmachine.gotoSuccess(jobId);
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Success));
    }

    function testGotoDisabledReview() public {
        makeJob();
        vm.prank(customer);
        jobmachine.gotoReview(jobId);
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Initial));
        gotoWork();
        vm.prank(customer);
        jobmachine.gotoReview(jobId);
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Work));

        // Can't goto Review as contractor as its disabled
        vm.prank(contractor);
        jobmachine.gotoReview(jobId);
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Work));
    }

    function testGotoEnabledReview() public {
        makeJob();
        vm.prank(owner);
        jobmachine.reviewEnabled(jobId, true);
        gotoWork();
        // Can't goto Review as customer
        vm.prank(customer);
        jobmachine.gotoReview(jobId);
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Work));

        // Can't goto Review as contractor without result set
        vm.prank(contractor);
        jobmachine.gotoReview(jobId);
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Work));

        // Can goto Review as contractor
        vm.prank(contractor);
        jobmachine.resultHash(jobId, bytes32(uint256(0x60)));
        vm.prank(contractor);
        jobmachine.gotoReview(jobId);
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Review));
    }


    function testTimerReviewOverflow() public {
        makeJob();
        vm.startPrank(owner);
        jobmachine.timerReviewInitial(jobId, 1 days);
        jobmachine.reviewEnabled(jobId, true);
        vm.stopPrank();
        gotoWork();
        jobmachine.tick(jobId);
        uint timestamp = jobmachine.timerTimestamp(jobId);
        vm.prank(contractor);
        jobmachine.resultHash(jobId, bytes32(uint256(0x60)));
        vm.prank(contractor);
        jobmachine.gotoReview(jobId);
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Review));
        assertEq(jobmachine.timerReview(jobId), 1 days);

        vm.warp(timestamp + 100);
        jobmachine.tick(jobId);
        assertEq(jobmachine.timerReview(jobId), 1 days - 100);

        uint contractorBalance = contractor.balance;
        uint reward = jobmachine.rewardBalance(jobId);
        uint deadlineFine = jobmachine.deadlineFineBalance(jobId);
        // Should go to Success and funds be released to contractor
        vm.warp(timestamp + 1 days);
        jobmachine.tick(jobId);
        assertEq(jobmachine.timerReview(jobId), 0);
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Success));
        assertEq(jobmachine.rewardBalance(jobId), 0);
        assertEq(jobmachine.deadlineFineBalance(jobId), 0);
        assertEq(contractor.balance, contractorBalance + reward + deadlineFine);

    }

    function testTimerReviewReset() public {
        makeJob();
        vm.startPrank(owner);
        jobmachine.timerReviewInitial(jobId, 1 days);
        jobmachine.reviewEnabled(jobId, true);
        vm.stopPrank();
        gotoWork();
        jobmachine.tick(jobId);
        uint timestamp = jobmachine.timerTimestamp(jobId);
        vm.prank(contractor);
        jobmachine.resultHash(jobId, bytes32(uint256(0x60)));
        vm.prank(contractor);
        jobmachine.gotoReview(jobId);
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Review));
        assertEq(jobmachine.timerReview(jobId), 1 days);
        assertEq(jobmachine.timerReview(jobId), jobmachine.timerReviewInitial(jobId));

        vm.warp(timestamp + 100);
        jobmachine.tick(jobId);
        assertEq(jobmachine.timerReview(jobId), 1 days - 100);

        // Now go to work and back to review - timer should reset.
        vm.warp(timestamp + 200);
        vm.prank(customer);
        jobmachine.gotoWork(jobId);
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Work));
        assertEq(jobmachine.timerReview(jobId), 1 days - 200);

        vm.prank(contractor);
        vm.warp(timestamp + 300);
        jobmachine.gotoReview(jobId);
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Review));
        assertEq(jobmachine.timerReview(jobId), 1 days);

        vm.prank(contractor);
        vm.warp(timestamp + 400);
        jobmachine.tick(jobId);
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Review));
        assertEq(jobmachine.timerReview(jobId), 1 days - 100);
    }

    function testReviewSuccessButTimerOverflowed() public {
        makeJob();
        vm.startPrank(owner);
        jobmachine.timerReviewInitial(jobId, 1 days);
        jobmachine.reviewEnabled(jobId, true);
        vm.stopPrank();
        gotoWork();
        vm.startPrank(contractor);
        jobmachine.resultHash(jobId, bytes32(uint256(0x60)));
        jobmachine.gotoReview(jobId);
        vm.stopPrank();
        uint timestamp = jobmachine.timerTimestamp(jobId);
        uint contractorBalance = contractor.balance;
        uint reward = jobmachine.rewardBalance(jobId);
        uint deadlineFine = jobmachine.deadlineFineBalance(jobId);

        // Should go to Success and funds be released to contractor
        vm.warp(timestamp + 2 days);
        vm.prank(customer);
        jobmachine.gotoWork(jobId);
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Success));
        assertEq(jobmachine.rewardBalance(jobId), 0);
        assertEq(jobmachine.deadlineFineBalance(jobId), 0);
        assertEq(contractor.balance, contractorBalance + reward + deadlineFine);
    }

    function testReviewSuccess() public {
        makeJob();
        vm.startPrank(owner);
        jobmachine.timerReviewInitial(jobId, 1 days);
        jobmachine.reviewEnabled(jobId, true);
        vm.stopPrank();
        gotoWork();
        vm.prank(contractor);
        jobmachine.gotoReview(jobId);

        uint contractorBalance = contractor.balance;
        uint reward = jobmachine.rewardBalance(jobId);
        uint deadlineFine = jobmachine.deadlineFineBalance(jobId);
        // Should go to Success and funds be released to contractor
        vm.prank(customer);
        jobmachine.gotoSuccess(jobId);
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Success));
        assertEq(jobmachine.rewardBalance(jobId), 0);
        assertEq(jobmachine.deadlineFineBalance(jobId), 0);
        assertEq(contractor.balance, contractorBalance + reward + deadlineFine);
    }

    function testNobodyFailToTransition() public {
        makeJob();
        gotoWork();
        // Fail to goto Success and not (customer or contractor)
        jobmachine.gotoSuccess(jobId);
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Work));
    }


    
    /***********************/
    /* Apply as Contractor */
    /***********************/

    function testApplyAsContractor() public {
        makeJob();

        vm.expectRevert(Unauthorized.selector);
        vm.prank(unknownPerson);
        // Customer is not signed
        jobmachine.applyAsContractor(jobId);
        
        vm.prank(customer);
        jobmachine.signAsCustomer(jobId);
        // Contractor is not undefined
        vm.expectRevert(Unauthorized.selector);
        vm.prank(unknownPerson);
        jobmachine.applyAsContractor(jobId);

        vm.prank(owner);
        jobmachine.contractor(jobId, payable(address(0)));
        vm.prank(unknownPerson);
        vm.expectRevert(UnsufficentFunds.selector);
        jobmachine.applyAsContractor(jobId);

        uint deadlineFineTarget = jobmachine.deadlineFineTarget(jobId);
        vm.prank(unknownPerson);
        jobmachine.applyAsContractor{value: deadlineFineTarget}(jobId);
        assertEq(jobmachine.contractor(jobId), payable(address(unknownPerson)));
        assertEq(jobmachine.deadlineFineBalance(jobId), deadlineFineTarget);

        // Try as another contractor should fail
        vm.prank(contractor);
        vm.expectRevert(Unauthorized.selector);
        jobmachine.applyAsContractor{value: deadlineFineTarget}(jobId);

    }



    /************/
    /* Disputes */
    /************/

    function testDisputeDisabled() public {
        makeJob();
        gotoWork();
        vm.expectRevert(DisputesDisabled.selector);
        vm.prank(contractor);
        jobmachine.startDispute(jobId, 3, JobMachine.TimersConfig(1,1,0));
    }

    function testMintDisputeUnsufficentFunds() public {
        vm.prank(owner);
        jobId = jobmachine.mintJob{value:100}({
            _customer: customer, 
            _contractor: contractor, 
            _reviewEnabled: false,
            _disputeEnabled: true,
            _rewardTarget: 5000, 
            _deadlineFineTarget: 1000,
            _metadataHash: bytes32(uint256(0x60)),
            timersConfig: JobMachine.TimersConfig({
                initial: 0,
                work: 10,
                reviewInitial: 0
            })
        });
        gotoWork();

        vm.prank(contractor);
        vm.expectRevert(UnsufficentFunds.selector);
        jobmachine.startDispute(jobId, 3, JobMachine.TimersConfig(1,1,0));

        uint jobMintFee = jobmachine.jobMintFee();
        vm.prank(contractor);
        vm.expectRevert(UnsufficentFunds.selector);
        jobmachine.startDispute{value:jobMintFee*3+3 - 1}(jobId, 3, JobMachine.TimersConfig(1,1,0));
    }

    function testMintDisputeEvenJobsAmount() public {
        makeJob();
        vm.prank(owner);
        jobmachine.disputeEnabled(jobId, true);
        gotoWork();
        
        vm.expectRevert(EvenJobsAmount.selector);
        vm.prank(contractor);
        jobmachine.startDispute(jobId, 2, JobMachine.TimersConfig(1,1,0));
    }

    function testMintDispute() public {
        vm.prank(owner);
        jobId = jobmachine.mintJob{value:100}({
            _customer: customer, 
            _contractor: contractor, 
            _reviewEnabled: false,
            _disputeEnabled: true,
            _rewardTarget: 5000, 
            _deadlineFineTarget: 1000,
            _metadataHash: bytes32(uint256(0x60)),
            timersConfig: JobMachine.TimersConfig({
                initial: 0,
                work: 10,
                reviewInitial: 0
            })
        });
        gotoWork();
        uint jobMintFee = jobmachine.jobMintFee();

        vm.prank(contractor);
        jobmachine.startDispute{value:jobMintFee*3+3}(jobId, 3, JobMachine.TimersConfig(1,1,0));
        
        // Created disputes
        uint160[][] memory disputes = jobmachine.disputes(jobId);
        assertEq(disputes.length, 1);
        assertEq(disputes[0].length, 3);

        // Dispute funds
        uint160 dispute = disputes[0][0];
        assertEq(jobmachine.owner(dispute), payable(address(jobmachine)));
        assertEq(jobmachine.customer(dispute), payable(address(jobmachine)));
        assertEq(jobmachine.contractor(dispute), payable(address(jobmachine)));
        assertEq(jobmachine.reviewEnabled(dispute), false);
        assertEq(jobmachine.disputeEnabled(dispute), false);
        assertEq(jobmachine.rewardTarget(dispute), 1);
        assertEq(jobmachine.rewardBalance(dispute), 1);
        // Refund will go back directly to contractor (if job will fail)
        assertEq(jobmachine.rewardFunder(dispute), contractor);
        assertEq(jobmachine.deadlineFineTarget(dispute), 0);
        assertEq(jobmachine.customerSigned(dispute), true);
        assertEq(jobmachine.contractorSigned(dispute), false);

    }

    function testTimerWork2Dispute() public {
        // Confirm Work timer ticks during the dispute
        vm.prank(owner);
        jobId = jobmachine.mintJob{value:100}({
            _customer: customer, 
            _contractor: contractor, 
            _reviewEnabled: false,
            _disputeEnabled: true,
            _rewardTarget: 5000, 
            _deadlineFineTarget: 1000,
            _metadataHash: bytes32(uint256(0x60)),
            timersConfig: JobMachine.TimersConfig({
                initial: 0,
                work: 10 days,
                reviewInitial: 0
            })
        });
        
        gotoWork();
        uint jobMintFee = jobmachine.jobMintFee();
        uint timestamp = jobmachine.timerTimestamp(jobId);

        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Work));
        // In 5 days start dispute
        vm.warp(timestamp + 5 days);
        vm.prank(contractor);
        jobmachine.startDispute{value:jobMintFee*3+30}(jobId, 3, JobMachine.TimersConfig(1,1,0));
        // Job's state should stay equal to Work
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Work));
        // And in 5 days more job should move to Failed state
        vm.warp(timestamp + 10 days);
        jobmachine.tick(jobId);
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Fail));
    }

    function testAssignDisputeReviewer1() public{
        vm.prank(owner);
        jobId = jobmachine.mintJob{value:100}({
            _customer: customer, 
            _contractor: contractor, 
            _reviewEnabled: false,
            _disputeEnabled: true,
            _rewardTarget: 5000, 
            _deadlineFineTarget: 1000,
            _metadataHash: bytes32(uint256(0x60)),
            timersConfig: JobMachine.TimersConfig({
                initial: 0,
                work: 10 days,
                reviewInitial: 0
            })
        });
        
        vm.prank(admin);
        vm.expectRevert(UnauthorizedState.selector);
        jobmachine.assignDisputeResolver(jobId, 0, resolver1);

        gotoWork();

        vm.prank(admin);
        vm.expectRevert(DisputeNotFound.selector);
        jobmachine.assignDisputeResolver(jobId, 0, resolver1);

        uint jobMintFee = jobmachine.jobMintFee();
        vm.prank(contractor);
        jobmachine.startDispute{value:jobMintFee*3+30}(jobId, 3, JobMachine.TimersConfig(1,1,0));

        vm.prank(admin);
        jobmachine.assignDisputeResolver(jobId, 0, resolver1);

    }

    function startDispute() public{
        vm.prank(owner);
        jobId = jobmachine.mintJob{value:100}({
            _customer: customer, 
            _contractor: contractor, 
            _reviewEnabled: false,
            _disputeEnabled: true,
            _rewardTarget: 5000, 
            _deadlineFineTarget: 1000,
            _metadataHash: bytes32(uint256(0x60)),
            timersConfig: JobMachine.TimersConfig({
                initial: 0,
                work: 10 days,
                reviewInitial: 0
            })
        });
        gotoWork();
        uint jobMintFee = jobmachine.jobMintFee();
        vm.prank(contractor);
        jobmachine.startDispute{value:jobMintFee*3+30}(jobId, 3, JobMachine.TimersConfig(1,1,0));
    }
    
    function testAssignDisputeReviewer2() public{
        startDispute();

        vm.prank(owner);
        vm.expectRevert(Unauthorized.selector);
        jobmachine.assignDisputeResolver(jobId, 0, resolver1);

        vm.prank(customer);
        vm.expectRevert(Unauthorized.selector);
        jobmachine.assignDisputeResolver(jobId, 0, resolver1);

        vm.prank(contractor);
        vm.expectRevert(Unauthorized.selector);
        jobmachine.assignDisputeResolver(jobId, 0, resolver1);

        vm.prank(admin);
        jobmachine.assignDisputeResolver(jobId, 0, resolver1);

    }

    function testAssignDisputeReviewerDisputeNotFound() public{
        startDispute();
        vm.prank(admin);
        vm.expectRevert(DisputeNotFound.selector);
        jobmachine.assignDisputeResolver(jobId, 3, resolver3);
    }

    function testAssignDisputeReviewerOnlyOneDisputePerReviewer() public{
        startDispute();
        vm.startPrank(admin);
        jobmachine.assignDisputeResolver(jobId, 0, resolver1);
        vm.expectRevert(OnlyOneDisputePerResolver.selector);
        jobmachine.assignDisputeResolver(jobId, 1, resolver1);
        vm.stopPrank();
    }

    function testAssignDisputeReviewer() public{
        startDispute();
        vm.startPrank(admin);
        jobmachine.assignDisputeResolver(jobId, 0, resolver1);
        jobmachine.assignDisputeResolver(jobId, 1, resolver2);
        jobmachine.assignDisputeResolver(jobId, 2, resolver3);
        vm.stopPrank();
        uint160 disputeId = jobmachine.disputes(jobId)[0][0];
        assertEq(jobmachine.contractor(disputeId), resolver1);
        assertEq(uint(jobmachine.state(disputeId)), uint(JobMachine.JobState.Initial));
        assertEq(jobmachine.customerSigned(disputeId), true);
        assertEq(jobmachine.contractorSigned(disputeId), false);
    }

    function testDisputeSuccessByAdmin() public {
        startDispute();
        uint160[][] memory disputes = jobmachine.disputes(jobId);

        vm.startPrank(admin);
        jobmachine.assignDisputeResolver(jobId, 0, resolver1);
        jobmachine.assignDisputeResolver(jobId, 1, resolver2);
        jobmachine.assignDisputeResolver(jobId, 2, resolver3);
        vm.stopPrank();

        assertEq(jobmachine.contractor(disputes[0][0]), resolver1);
        assertEq(jobmachine.contractor(disputes[0][1]), resolver2);
        assertEq(jobmachine.contractor(disputes[0][2]), resolver3);

        vm.startPrank(resolver1);
        jobmachine.signAsContractor(disputes[0][0]);

        jobmachine.gotoSuccess(disputes[0][0]);
        assertEq(uint(jobmachine.state(disputes[0][0])), uint(JobMachine.JobState.Initial));

        jobmachine.gotoWork(disputes[0][0]);
        // Should fail as no result provided
        jobmachine.gotoSuccess(disputes[0][0]);
        assertEq(uint(jobmachine.state(disputes[0][0])), uint(JobMachine.JobState.Work));

        jobmachine.resultHash(disputes[0][0], bytes32(uint256(0x60)));
        jobmachine.gotoSuccess(disputes[0][0]);
        assertEq(uint(jobmachine.state(disputes[0][0])), uint(JobMachine.JobState.Success));
        vm.stopPrank();

        vm.prank(admin);
        // Should fail as no quorum
        jobmachine.gotoSuccess(jobId);
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Work));

        // Resolve 2nd job
        vm.startPrank(resolver2);
        jobmachine.signAsContractor(disputes[0][1]);
        jobmachine.gotoWork(disputes[0][1]);
        jobmachine.resultHash(disputes[0][1], bytes32(uint256(0x60)));
        jobmachine.gotoSuccess(disputes[0][1]);
        vm.stopPrank();

        // Should work
        vm.prank(admin);
        jobmachine.gotoSuccess(jobId);
        assertEq(uint(jobmachine.state(jobId)), uint(JobMachine.JobState.Success));
    }

    function testSecondDispute() public {
        vm.prank(owner);
        jobId = jobmachine.mintJob{value:100}({
            _customer: customer, 
            _contractor: contractor, 
            _reviewEnabled: false,
            _disputeEnabled: true,
            _rewardTarget: 5000, 
            _deadlineFineTarget: 1000,
            _metadataHash: bytes32(uint256(0x60)),
            timersConfig: JobMachine.TimersConfig({
                initial: 0,
                work: 10 days,
                reviewInitial: 0
            })
        });
        gotoWork();
        uint jobMintFee = jobmachine.jobMintFee();
        vm.prank(contractor);
        jobmachine.startDispute{value:jobMintFee*3+30}(jobId, 3, JobMachine.TimersConfig(1,1,0));

        uint160[][] memory disputes = jobmachine.disputes(jobId);
        vm.prank(admin);
        jobmachine.assignDisputeResolver(jobId, 0, resolver1);
        assertEq(jobmachine.contractor(disputes[0][0]), resolver1);
        
        vm.prank(contractor);
        jobmachine.startDispute{value:jobMintFee*3+30}(jobId, 3, JobMachine.TimersConfig(1,1,0));

        disputes = jobmachine.disputes(jobId);
        vm.startPrank(admin);
        jobmachine.assignDisputeResolver(jobId, 0, resolver2);
        jobmachine.assignDisputeResolver(jobId, 1, resolver3);
        vm.stopPrank();

        assertEq(jobmachine.contractor(disputes[0][0]), resolver1);
        assertEq(jobmachine.contractor(disputes[0][1]), address(jobmachine));
        assertEq(jobmachine.contractor(disputes[0][2]), address(jobmachine));
        assertEq(jobmachine.contractor(disputes[1][0]), resolver2);
        assertEq(jobmachine.contractor(disputes[1][1]), resolver3);
        assertEq(jobmachine.contractor(disputes[1][2]), address(jobmachine));
    }

}
