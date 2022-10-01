// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;


// TODO: Migrate off from timestamp to block number.
// TODO: Introduce a way for the service to know about minted contract (if minted directly on th blockchain)

error Unauthorized();
error UnauthorizedState();
error UnsufficentFunds();
error JobAlreadyExists();
error MultipleFundersNotAllowed();
error UndefinedParty();
error MissingPartySignature();
error CallTickDirectlyFirst();
error EvenJobsAmount();
error DisputesDisabled();
error DisputeCouldBreakJobsDeadline();
error DisputeNoDeadlineSet();
error DisputeNotFound();
error DisputeContractorSigned();
error OnlyOneDisputePerResolver();

/**
 * The OwnedContract ensures that only the creator (deployer) of a 
 * contract can perform certain tasks.
 */
contract OwnedContract {
    address payable public contractOwner = payable(msg.sender);
    event contractOwnerChanged(address payable indexed old, address payable indexed current);
    modifier onlyContractOwner { 
        if(msg.sender != contractOwner){
            revert Unauthorized();
        }
        _; 
    }
    function setContractOwner(address payable _contractOwner) onlyContractOwner public { 
        emit contractOwnerChanged(contractOwner, _contractOwner); 
        contractOwner = _contractOwner; 
    }
}

contract AdministredContract {
    address public admin = msg.sender;
    event adminChanged(address indexed old, address indexed current);
    modifier onlyAdmin { 
        if(msg.sender != admin){
            revert Unauthorized();
        }
        _; 
    }
    function setAdmin(address _admin) onlyAdmin public { 
        emit adminChanged(admin, _admin); 
        admin = _admin; 
    }
}

contract Balances{
    // The representation of the balance with a single funder allowed.
    struct Balance{
        // Target balance amount
        uint target;
        // Actial balance
        uint balance;
        // Who funded
        address payable funder;
    }

    event balanceFund(address indexed funder, uint amount);
    event balanceRefund(address indexed funder, uint amount);
    event balanceReleasedToCustomerOnJobFail(address indexed funder, uint amount);
    event balanceReleasedToContractorOnJobSuccess(address indexed funder, uint amount);

    function fund(Balance storage balance) internal{
        if(msg.value == 0){
            revert UnsufficentFunds();
        }
        if(balance.balance > 0 && balance.funder != msg.sender){
            // Only one person could topup existing balance. Try to refund first.
            revert MultipleFundersNotAllowed();
        }
        balance.balance += msg.value;
        balance.funder = payable(msg.sender);
        emit balanceFund(balance.funder, msg.value);
    }

    function refund(Balance storage balance, uint amount, address jobOwner) internal {
        if(balance.funder!=msg.sender && jobOwner!=msg.sender){
            // Only funder or owner could initiate refund
            revert Unauthorized();
        }
        if(balance.balance < amount){
            revert UnsufficentFunds();
        }
        balance.balance -= amount;
        emit balanceRefund(balance.funder, amount);
        balance.funder.transfer(amount);
    }

}

contract JobMachineBase is OwnedContract, AdministredContract, Balances{
    bytes32 CHEAT_HASH_ACCEPTED = bytes32(uint256(0xaad504e67d32f5c093d699f6614bee9977b9c793129f955975107bb78ae0a7d5));
    uint public jobMintFee;
    function setJobMintFee(uint newFee) public onlyContractOwner {
        jobMintFee = newFee;
    }
}


contract JobMachine is JobMachineBase {
    
    /* 
    Job States
    Initial - Job minted but not yet started. Job owner could update job in any way
    Work - Parameters locked, funds frozen. Job is in progress. Deadline timer ticks.
    Review - Customer's review time
    Pause - Timers stopped. State change request issued but no confirmation from other party yet
    Successs - Job is done and accepted. Funds released.
    Fail - Deadline timer overflow or something similar
    Cancel - Job cancelled by agreement
    */
    enum JobState { Initial, Work, Review, Success, Fail }
    
    // struct Ability{
    //     string title;
    //     // The percentage of the ability involvement. 100 is default.
    //     uint8 weight;
    //     // Required experience. Zero value allows apply contractors with no verified experience
    //     uint requiredExperience;
    // }

    // Timers count down to zero. Measured in seconds. Timers updated during the tick() function call
    struct Timers {
        // Last time timers were updated
        uint timestamp;
        // Time allowed in initial state
        uint initial;
        // Job will transition to Fail on work timer fire
        uint work;
        // Job will transition to Succes on review timer fire
        uint review;
        // Review timer will reset to reveiwInitial value each time job enters Review state
        uint reviewInitial;
    }


    struct Signatures {
        bool customerSigned;
        bool contractorSigned;
    }

    struct Hashes {
        // Metadata is stored outside the contract but hash should be inside
        bytes32 metadata;
        // The result hash
        bytes32 result;
    }

    struct Job {
        JobState state;
        // The one who minted job
        address owner;
        // Customer role
        address payable customer;
        // Contractor role
        address payable contractor;
        // To be frozen by Customer and released to Contructor upon Success
        Balance reward;
        // To be released to Customer, should the deadline timer flow out
        Balance deadlineFine;
        // Everything timers related
        Timers timers;
        // Job should be reviewed by Customer before moving to Success
        bool reviewEnabled;
        // Is it allowed for the Contractor to initiate dispute resolution
        bool disputeEnabled;
        
        // Array of arrays of dispute jobs. disputes[disputes.length-1] is current list of disputes
        uint160[][] disputes;

        // Signatures
        Signatures signatures;
        Hashes hashes;

    }
    
    mapping(uint160 => Job) public jobs;
    uint160 nonce;

    modifier onlyOwner(uint160 jobId){ 
        if(jobs[jobId].owner != msg.sender){
            revert Unauthorized();
        }
        _; 
    }

    modifier onlyState(uint160 jobId, JobState _state){ 
        if(jobs[jobId].state != _state){
            revert UnauthorizedState();
        }
        _; 
    }

    modifier onlyCustomer(uint160 jobId){
        if(jobs[jobId].customer != msg.sender){
            revert Unauthorized();
        }
        _;
    }

    modifier onlyContractor(uint160 jobId){
        if(jobs[jobId].contractor != msg.sender){
            revert Unauthorized();
        }
        _;
    }

    event mintFeePaid(uint160 indexed jobId, address indexed who, uint price);
    event stateTransition(uint160 indexed jobId, address indexed who, JobState oldState, JobState newState);
    event timerWorkFired(uint160 indexed jobId);
    event timerReviewFired(uint160 indexed jobId);
    event disputeStarted(uint160 indexed jobId);

    struct TimersConfig{
        uint initial;
        uint work;
        uint reviewInitial;
    }
    function mintJob(address payable _customer, address payable _contractor, 
        uint _rewardTarget, uint _deadlineFineTarget, bytes32 _metadataHash, TimersConfig calldata timersConfig, 
        bool _reviewEnabled, bool _disputeEnabled) public payable returns (uint160) {

        if(jobMintFee > msg.value){
            revert UnsufficentFunds();
        }

        uint160 jobId = uint160(uint(keccak256(abi.encodePacked(nonce, msg.sender))));
        nonce = jobId;

        Job storage job = jobs[jobId];

        if(job.owner != address(0)){
            revert JobAlreadyExists();
        }

        job.state = JobState.Initial;
        job.owner = msg.sender;
        job.customer = _customer;
        job.contractor = _contractor;
        job.reviewEnabled = _reviewEnabled;
        job.disputeEnabled = _disputeEnabled;
        job.reward = Balance({
            target: _rewardTarget, 
            balance: 0, 
            funder: payable(address(0))
        });
        job.deadlineFine = Balance({
            target: _deadlineFineTarget, 
            balance: 0, 
            funder: payable(address(0))
        });
        job.timers = Timers({
            timestamp: block.timestamp,
            initial: timersConfig.initial,
            work: timersConfig.work,
            review: 0,
            reviewInitial: timersConfig.reviewInitial
        });
        job.hashes = Hashes({
            metadata: _metadataHash,
            result: bytes32(0x0)
        });
        
        emit mintFeePaid(jobId, msg.sender, jobMintFee);
        contractOwner.transfer(msg.value);
        return jobId;
    }

    /* Getters */
    function state(uint160 jobId) public view returns(JobState){
        return jobs[jobId].state;
    }
    function owner(uint160 jobId) public view returns(address){
        return jobs[jobId].owner;
    }
    function customer(uint160 jobId) public view returns(address payable){
        return jobs[jobId].customer;
    }
    function contractor(uint160 jobId) public view returns(address payable){
        return jobs[jobId].contractor;
    }
    function reviewEnabled(uint160 jobId) public view returns(bool){
        return jobs[jobId].reviewEnabled;
    }
    function disputeEnabled(uint160 jobId) public view returns(bool){
        return jobs[jobId].disputeEnabled;
    }
    function rewardBalance(uint160 jobId) public view returns(uint){
        return jobs[jobId].reward.balance;
    }
    function rewardTarget(uint160 jobId) public view returns(uint){
        return jobs[jobId].reward.target;
    }
    function rewardFunder(uint160 jobId) public view returns(address payable){
        return jobs[jobId].reward.funder;
    }
    function deadlineFineBalance(uint160 jobId) public view returns(uint){
        return jobs[jobId].deadlineFine.balance;
    }
    function deadlineFineTarget(uint160 jobId) public view returns(uint){
        return jobs[jobId].deadlineFine.target;
    }
    function deadlineFineFunder(uint160 jobId) public view returns(address payable){
        return jobs[jobId].deadlineFine.funder;
    }
    function metadataHash(uint160 jobId) public view returns(bytes32){
        return jobs[jobId].hashes.metadata;
    }
    function resultHash(uint160 jobId) public view returns(bytes32){
        return jobs[jobId].hashes.result;
    }
    function customerSigned(uint160 jobId) public view returns(bool){
        return jobs[jobId].signatures.customerSigned;
    }
    function contractorSigned(uint160 jobId) public view returns(bool){
        return jobs[jobId].signatures.contractorSigned;
    }
    function timerTimestamp(uint160 jobId) public view returns(uint){
        return jobs[jobId].timers.timestamp;
    }
    function timerWork(uint160 jobId) public view returns(uint){
        return jobs[jobId].timers.work;
    }
    function timerReview(uint160 jobId) public view returns(uint){
        return jobs[jobId].timers.review;
    }
    function timerReviewInitial(uint160 jobId) public view returns(uint){
        return jobs[jobId].timers.reviewInitial;
    }
    function disputes(uint160 jobId) public view returns(uint160[][] memory){
        return jobs[jobId].disputes;
    }

    /* Setters */
    function customer(uint160 jobId, address payable _customer)
        public onlyOwner(jobId) onlyState(jobId, JobState.Initial){
        // No need to sign again for contractor
        Job storage job = jobs[jobId];
        job.customer = _customer;
        job.signatures.customerSigned = false;
    }

    function contractor(uint160 jobId, address payable _contractor)
        public onlyOwner(jobId) onlyState(jobId, JobState.Initial){
        // No need to sign again for customer
        Job storage job = jobs[jobId];
        job.contractor = _contractor;
        job.signatures.contractorSigned = false;
    }

    function reviewEnabled(uint160 jobId, bool _reviewEnabled) 
        public onlyOwner(jobId) onlyState(jobId, JobState.Initial){
        jobs[jobId].reviewEnabled = _reviewEnabled;
    }

    function disputeEnabled(uint160 jobId, bool _disputeEnabled) 
        public onlyOwner(jobId) onlyState(jobId, JobState.Initial){
        jobs[jobId].disputeEnabled = _disputeEnabled;
    }
    
    function rewardTarget(uint160 jobId, uint _rewardTarget)
        public onlyOwner(jobId) onlyState(jobId, JobState.Initial){
        // Revert signatures
        Job storage job = jobs[jobId];
        job.reward.target = _rewardTarget;
        job.signatures.customerSigned = false;
        job.signatures.contractorSigned = false;
    }

    function deadlineFineTarget(uint160 jobId, uint _deadlineFineTarget)
        public onlyOwner(jobId) onlyState(jobId, JobState.Initial){
        // Revert signatures
        Job storage job = jobs[jobId];
        job.deadlineFine.target = _deadlineFineTarget;
        job.signatures.customerSigned = false;
        job.signatures.contractorSigned = false;
    }

    function metadataHash(uint160 jobId, bytes32 _metadataHash)
        public onlyOwner(jobId) onlyState(jobId, JobState.Initial){
        // Revert signatures
        Job storage job = jobs[jobId];
        job.hashes.metadata = _metadataHash;
        job.signatures.customerSigned = false;
        job.signatures.contractorSigned = false;
    }

    function resultHash(uint160 jobId, bytes32 _resultHash)
        public onlyContractor(jobId) onlyState(jobId, JobState.Work){
        // Contractor could set the result during the Work
        Job storage job = jobs[jobId];
        job.hashes.result = _resultHash;
    }
    
    function signAsCustomer(uint160 jobId) public onlyCustomer(jobId) onlyState(jobId, JobState.Initial){
        jobs[jobId].signatures.customerSigned = true;
    }

    function signAsContractor(uint160 jobId) public onlyContractor(jobId) onlyState(jobId, JobState.Initial){
        jobs[jobId].signatures.contractorSigned = true;
    }

    function timerWork(uint160 jobId, uint _timerWork) public onlyOwner(jobId) onlyState(jobId, JobState.Initial){
        jobs[jobId].timers.work = _timerWork;
    }
    function timerReviewInitial(uint160 jobId, uint _timerReviewInitial) public onlyOwner(jobId) onlyState(jobId, JobState.Initial){
        jobs[jobId].timers.reviewInitial = _timerReviewInitial;
    }

    /* Funding */
    function fundReward(uint160 jobId) public payable onlyState(jobId, JobState.Initial){
        fund(jobs[jobId].reward);
    }
    function refundReward(uint160 jobId, uint amount) public payable onlyState(jobId, JobState.Initial){
        refund(jobs[jobId].reward, amount, jobs[jobId].owner);
    }
    function fundDeadlineFine(uint160 jobId) public payable onlyState(jobId, JobState.Initial){
        fund(jobs[jobId].deadlineFine);
    }
    function refundDeadlineFine(uint160 jobId, uint amount) public payable onlyState(jobId, JobState.Initial){
        refund(jobs[jobId].deadlineFine, amount, jobs[jobId].owner);
    }

    /* 
        A way for random Contractor to apply for a job on his own, without Owner or Customer confirmation.
        Anybody could be a Contractor if job has empty Contractor and Customer has signed the job.
    */
    function applyAsContractor(uint160 jobId) public payable onlyState(jobId, JobState.Initial){
        Job storage job = jobs[jobId];
        // Anybody could set himself as contractor if customer signed the job while contractor is undefined
        if(!job.signatures.customerSigned || job.contractor != payable(address(0))){
            revert Unauthorized();
        }

        if(jobs[jobId].deadlineFine.target > jobs[jobId].deadlineFine.balance + msg.value){
            // The one who is applying should fund the deadline fee right away
            revert UnsufficentFunds();
        }

        fund(jobs[jobId].deadlineFine);
        job.contractor = payable(msg.sender);
        job.signatures.contractorSigned = false;
    }

    /* Timers */
    function updateTimer(uint currentTimerValue, uint lastTimestamp) internal view returns(uint newTimerValue, bool timerFired){
        if(currentTimerValue > 0){
            // Timer could run out just once, so do not bother if its zero.
            uint passed = block.timestamp - lastTimestamp;
            if(currentTimerValue > passed){
                // There is still some time left on the timer
                return (currentTimerValue - passed, false);
            }else{
                // Ding - dong!
                return (0, true);
            }
        }
        return (0, false);
    }

    /* Internal functions to unconditionally move to Success and Fail */
    function _success(uint160 jobId) internal {
        Job storage job = jobs[jobId];
        emit stateTransition(jobId, msg.sender, job.state, JobState.Success);
        // Set state to Success
        job.state = JobState.Success;
        // Transfer reward and deadlineFine to contractor
        uint deadlineFine = job.deadlineFine.balance;
        job.deadlineFine.balance = 0;
        uint reward = job.reward.balance;
        job.reward.balance = 0;
        emit balanceReleasedToContractorOnJobSuccess(job.contractor, reward+deadlineFine);
        job.contractor.transfer(reward+deadlineFine);
    }

    function _fail(uint160 jobId) internal {
        Job storage job = jobs[jobId];
        emit stateTransition(jobId, msg.sender, job.state, JobState.Fail);
        // Set state to Fail
        job.state = JobState.Fail;
        // Transfer reward and deadlineFine to customer
        uint deadlineFine = job.deadlineFine.balance;
        job.deadlineFine.balance = 0;
        uint reward = job.reward.balance;
        job.reward.balance = 0;
        emit balanceReleasedToCustomerOnJobFail(job.customer, reward+deadlineFine);
        job.customer.transfer(reward+deadlineFine);
    }

    /* 
        Tick function update timers and could be called in random times 
        but its important to call it right before the state change
        Be careful as tick function could change state based on timers.
        Do not use onlyState modifyer and tick as tick could change state.
    */
    function tick(uint160 jobId) public {
        Job storage job = jobs[jobId];
        if(job.state == JobState.Work){
            bool timerFired;
            (job.timers.work, timerFired) = updateTimer(job.timers.work, job.timers.timestamp);
            if(timerFired){
                // We reached the deadline
                emit timerWorkFired(jobId);
                _fail(jobId);
            }
        }else if(job.state == JobState.Review){
            bool timerFired;
            (job.timers.review, timerFired) = updateTimer(job.timers.review, job.timers.timestamp);
            if(timerFired){
                // We reached the deadline
                emit timerReviewFired(jobId);
                _success(jobId);
            }
        }
        // Update timestamp
        job.timers.timestamp = block.timestamp;
    }


    /* State management*/
    /* Every state management function should update timers as a first thing via tick() */
    function gotoWork(uint160 jobId) public {
        tick(jobId);
        Job storage job = jobs[jobId];

        if(job.state == JobState.Initial){
            // Anybody could start the job once all requirements met
            if(!job.signatures.customerSigned || !job.signatures.contractorSigned){
                revert MissingPartySignature();
            }
            if(job.reward.target > job.reward.balance || job.deadlineFine.target > job.deadlineFine.balance){
                revert UnsufficentFunds();
            }
            // Transition to Work state
            emit stateTransition(jobId, msg.sender, job.state, JobState.Work);
            job.state = JobState.Work;
        }else if(job.state == JobState.Review && msg.sender == job.customer){
            // Customer could transition from review to Work
            emit stateTransition(jobId, msg.sender, job.state, JobState.Work);
            job.state = JobState.Work;
        }
    }

    /* Necessary condition for admin to change state based on dispute results */
    function _thereCouldBeQuorum(Job storage job) internal view returns(bool){
        uint8 successCount = 0;
        uint160[] memory currentDisputes = job.disputes[job.disputes.length-1];
        // Count dispute jobs who made their decision
        for(uint8 i=0; i<currentDisputes.length; i++){
            if(state(currentDisputes[i]) == JobState.Success){
                successCount += 1;
            }
        }
        if(currentDisputes.length > 0 && successCount > currentDisputes.length / 2){
            // There are some dispute jobs out there and more then half of them made their decision
            // So its possible that global decision about job could be made.
            return true;
        }
        return false;
    }

    function gotoSuccess(uint160 jobId) public {
        tick(jobId);
        Job storage job = jobs[jobId];

        if(msg.sender == job.customer){
            if(job.state == JobState.Work || job.state == JobState.Review){
                // Customer could move from Work or Review to Success in any time
                _success(jobId);
            }
        } else if(msg.sender == job.contractor){
            if(job.state == JobState.Work && !job.reviewEnabled && job.hashes.result != bytes32(0x0)){
                // Only if review is disabled Contractor could unconditionally move from Work to Success
                _success(jobId);
            }
        } else if(msg.sender == admin){
            // Admin could move to Success based on disput results
            // On the blockchain we are storing hashes of dispute results (not results itself),
            // so the transition is unconditional, but if one have access to dispute jobs' metadata 
            // then they could validate admin's decision.

            // Lets confirm there is a dispute running and there is a quorum in place (neccessary condition for admin to take action)
            if(job.disputeEnabled && job.state == JobState.Work && _thereCouldBeQuorum(job)){
                _success(jobId);
            }
        }
    }

    function gotoReview(uint160 jobId) public {
        tick(jobId);
        Job storage job = jobs[jobId];

        if(job.state == JobState.Work){
            // Its only possible to go to Review from Work
            if(job.reviewEnabled && msg.sender == job.contractor && job.hashes.result != bytes32(0x0)){
                // Only Contractor and only if enabled, could transition to Review
                emit stateTransition(jobId, msg.sender, job.state, JobState.Review);
                // Reset timer each time we're entering Review state
                job.timers.review = job.timers.reviewInitial;
                job.state = JobState.Review;
            }
        }
    }


    function startDispute(uint160 jobId, uint8 jobsAmount, TimersConfig calldata timersConfig) public payable onlyContractor(jobId){
        tick(jobId);
        Job storage job = jobs[jobId];

        if(job.state != JobState.Work){
            revert UnauthorizedState();
        }

        // Only Contractor and only if enabled, could init dispute resolution
        if(!job.disputeEnabled){
            revert DisputesDisabled();
        }

        //Amount should be uneven
        if(jobsAmount%2 == 0){
            revert EvenJobsAmount();
        }

        // Time allowed for the dispute should be less then time left for the work
        // to guarantee that dispute wouldn't go over the job's deadline
        if(job.timers.work < timersConfig.initial + timersConfig.work || timersConfig.initial == 0 || timersConfig.work == 0){
            revert DisputeCouldBreakJobsDeadline();
        }

        // Contractor should send enough funds to mint jobs.
        if(msg.value < jobsAmount*jobMintFee + jobsAmount){
            revert UnsufficentFunds();
        }
        // Count reward for each job
        uint reward = (msg.value-jobsAmount*jobMintFee) / jobsAmount;

        uint160[] memory newDisputes = new uint160[](jobsAmount);

        for(uint8 i=0; i<jobsAmount; i++){
            // Minting dispute jobs. The Customer is a contract (as real customer shouldn't
            // have any rights). The Contractor is also a contract 
            // Dispute job should be signed later to avoid open job status.
            uint160 disputeId = this.mintJob{value:jobMintFee}({
                _customer: payable(address(this)), 
                _contractor: payable(address(this)), 
                _reviewEnabled: false,
                _disputeEnabled: false,
                _rewardTarget: reward, 
                _deadlineFineTarget: 0,
                _metadataHash: bytes32(0),
                timersConfig: timersConfig
            });
            this.fundReward{value:reward}(disputeId);

            // Hack to set right reward funder.
            // It is needed in case of fale for funds
            // to go back directly to right address
            jobs[disputeId].reward.funder = job.contractor;
            // Sign the job right away
            this.signAsCustomer(disputeId);
            newDisputes[i] = disputeId;
        }
        job.disputes.push(newDisputes);

        emit disputeStarted(jobId);
    }

    function assignDisputeResolver(uint160 jobId, uint160 disputeIdx, address payable resolver) public onlyAdmin {
        // Admin will pick resolvers based on its internal algorithms and assign them to dispute jobs
        tick(jobId);
        Job storage job = jobs[jobId];
        
        if(job.state != JobState.Work){
            revert UnauthorizedState();
        }

        if(!job.disputeEnabled){
            revert DisputesDisabled();
        }

        if(job.disputes.length == 0 || disputeIdx >= job.disputes[job.disputes.length-1].length){
            revert DisputeNotFound();
        }
        uint160[] memory currentDisputes = job.disputes[job.disputes.length-1];
        uint160 disputeId = currentDisputes[disputeIdx];

        if(contractorSigned(disputeId)){
            revert DisputeContractorSigned();
        }

        for(uint8 i=0; i<currentDisputes.length; i++){
            if(jobs[currentDisputes[i]].contractor == resolver){
                revert OnlyOneDisputePerResolver();
            }
        }
        // Assign a resolver to the dispute
        this.contractor(disputeId, resolver);
    }

    // function proceedDispute(uint160 jobId) public {
    //     tick(jobId);
    //     Job storage job = jobs[jobId];
    //     if(job.state != JobState.Work){
    //         revert UnauthorizedState();
    //     }
    //     uint8 acceptedCount = 0;
    //     uint8 declinedCount = 0;
    //     for(uint8 i=0; i<job.disputes.length; i++){
    //         if(state(job.disputes[i]) == JobState.Success){
    //             // Resolver made a decision
    //             if(resultHash(job.disputes[i]) == CHEAT_HASH_ACCEPTED){
    //                 // The result was "Accepted"
    //                 acceptedCount += 1;
    //             }else{
    //                 declinedCount += 1;
    //             }
    //         }
    //     }
    // }
    
}
