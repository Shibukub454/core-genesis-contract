pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;
import "./System.sol";
import "./lib/BytesToTypes.sol";
import "./lib/Memory.sol";
import "./lib/BytesLib.sol";
import "./lib/RLPDecode.sol";
import "./interface/IParamSubscriber.sol";

/// This is the smart contract to manage governance votes
contract GovHub is System, IParamSubscriber {
  using RLPDecode for *;

  uint256 public constant PROPOSAL_MAX_OPERATIONS = 1;
  uint256 public constant VOTING_PERIOD = 201600;
  bytes public constant INIT_MEMBERS = hex"f83f9491fb7d8a73d2752830ea189737ea0e007f999b949448bfbc530e7c54c332b0fae07312fba7078b878994de60b7d0e6b758ca5dd8c61d377a2c5f1af51ec1";

  uint256 public proposalMaxOperations;
  uint256 public votingPeriod;

  mapping(address => uint256) public members;
  address[] public memberSet;

  mapping(uint256 => Proposal) public proposals;
  mapping(address => uint256) public latestProposalIds;
  uint256 public proposalCount;

  event paramChange(string key, bytes value);
  event receiveDeposit(address indexed from, uint256 amount);
  event VoteCast(address voter, uint256 proposalId, bool support);
  event ProposalCreated(
    uint256 id,
    address proposer,
    address[] targets,
    uint256[] values,
    string[] signatures,
    bytes[] calldatas,
    uint256 startBlock,
    uint256 endBlock,
    uint256 totalVotes,
    string description
  );
  event ProposalCanceled(uint256 id);
  event ProposalExecuted(uint256 id);
  event ExecuteTransaction(address indexed target, uint256 value, string signature, bytes data);

  event MemberAdded(address indexed member);
  event MemberDeleted(address indexed member);

  struct Proposal {
    uint256 id;
    address proposer;
    address[] targets;
    uint256[] values;
    string[] signatures;
    bytes[] calldatas;
    uint256 startBlock;
    uint256 endBlock;
    uint256 forVotes;
    uint256 againstVotes;
    uint256 totalVotes;
    bool canceled;
    bool executed;
    mapping(address => Receipt) receipts;
  }

  struct Receipt {
    bool hasVoted;
    bool support;
  }

  enum ProposalState {
    Pending,
    Active,
    Canceled,
    Defeated,
    Succeeded,
    Executed
  }

  modifier onlyMember() {
    require(members[msg.sender] != 0, "only member is allowed to call the method");
    _;
  }

  function init() external onlyNotInit {
    proposalMaxOperations = PROPOSAL_MAX_OPERATIONS;
    votingPeriod = VOTING_PERIOD;
    RLPDecode.RLPItem[] memory items = INIT_MEMBERS.toRLPItem().toList();
    uint256 itemSize = items.length;
    for (uint256 i = 0; i < itemSize; i++) {
      address addr = items[i].toAddress();
      memberSet.push(addr);
      members[addr] = memberSet.length;
    }
    alreadyInit = true;
  }

  /// Make a new proposal
  /// @param targets List of addresses to interact with
  /// @param values List of values (CORE amount) to send
  /// @param signatures List of signatures
  /// @param calldatas List of calldata
  /// @param description Description of the proposal
  /// @return The proposal id
  function propose(
    address[] memory targets,
    uint256[] memory values,
    string[] memory signatures,
    bytes[] memory calldatas,
    string memory description
  ) public onlyInit onlyMember returns (uint256) {
    require(
      targets.length == values.length && targets.length == signatures.length && targets.length == calldatas.length,
      "proposal function information arity mismatch"
    );
    require(targets.length != 0, "must provide actions");
    require(targets.length <= proposalMaxOperations, "too many actions");

    uint256 latestProposalId = latestProposalIds[msg.sender];
    if (latestProposalId != 0) {
      ProposalState proposersLatestProposalState = state(latestProposalId);
      require(
        proposersLatestProposalState != ProposalState.Active,
        "one live proposal per proposer, found an already active proposal"
      );
      require(
        proposersLatestProposalState != ProposalState.Pending,
        "one live proposal per proposer, found an already pending proposal"
      );
    }

    uint256 startBlock = block.number + 1;
    uint256 endBlock = startBlock + votingPeriod;

    proposalCount++;
    Proposal memory newProposal = Proposal({
      id: proposalCount,
      proposer: msg.sender,
      targets: targets,
      values: values,
      signatures: signatures,
      calldatas: calldatas,
      startBlock: startBlock,
      endBlock: endBlock,
      forVotes: 0,
      againstVotes: 0,
      totalVotes: memberSet.length,
      canceled: false,
      executed: false
    });

    proposals[newProposal.id] = newProposal;
    latestProposalIds[newProposal.proposer] = newProposal.id;

    emit ProposalCreated(
      newProposal.id,
      msg.sender,
      targets,
      values,
      signatures,
      calldatas,
      startBlock,
      endBlock,
      memberSet.length,
      description
    );
    return newProposal.id;
  }

  /// Cast vote on a proposal
  /// @param proposalId The proposal Id
  /// @param support Support or not
  function castVote(uint256 proposalId, bool support) public onlyInit onlyMember {
    require(state(proposalId) == ProposalState.Active, "voting is closed");
    Proposal storage proposal = proposals[proposalId];
    Receipt storage receipt = proposal.receipts[msg.sender];
    require(!receipt.hasVoted, "voter already voted");
    if (support) {
      proposal.forVotes += 1;
    } else {
      proposal.againstVotes += 1;
    }

    receipt.hasVoted = true;
    receipt.support = support;
    emit VoteCast(msg.sender, proposalId, support);
  }

  /// Cancel the proposal, can only be done by the proposer
  /// @param proposalId The proposal Id
  function cancel(uint256 proposalId) public onlyInit {
    ProposalState state = state(proposalId);
    require(state == ProposalState.Pending || state == ProposalState.Active, "cannot cancel finished proposal");

    Proposal storage proposal = proposals[proposalId];
    require(msg.sender == proposal.proposer, "only cancel by proposer");

    proposal.canceled = true;
    emit ProposalCanceled(proposalId);
  }

  /// Execute the proposal
  /// @param proposalId The proposal Id
  function execute(uint256 proposalId) public payable onlyInit {
    require(state(proposalId) == ProposalState.Succeeded, "proposal can only be executed if it is succeeded");
    Proposal storage proposal = proposals[proposalId];
    proposal.executed = true;
    uint256 targetSize = proposal.targets.length;
    for (uint256 i = 0; i < targetSize; i++) {
      bytes memory callData;
      if (bytes(proposal.signatures[i]).length == 0) {
        callData = proposal.calldatas[i];
      } else {
        callData = abi.encodePacked(bytes4(keccak256(bytes(proposal.signatures[i]))), proposal.calldatas[i]);
      }

      (bool success, bytes memory returnData) = proposal.targets[i].call.value(proposal.values[i])(callData);
      require(success, "Transaction execution reverted.");
      emit ExecuteTransaction(proposal.targets[i], proposal.values[i], proposal.signatures[i], proposal.calldatas[i]);
    }
    emit ProposalExecuted(proposalId);
  }

  /// Check the proposal state
  /// @param proposalId The proposal Id
  /// @return The state of the proposal
  function state(uint256 proposalId) public view returns (ProposalState) {
    require(proposalCount >= proposalId && proposalId != 0, "state: invalid proposal id");
    Proposal storage proposal = proposals[proposalId];
    if (proposal.canceled) {
      return ProposalState.Canceled;
    } else if (block.number <= proposal.startBlock) {
      return ProposalState.Pending;
    } else if (block.number <= proposal.endBlock) {
      return ProposalState.Active;
    } else if (proposal.forVotes <= proposal.againstVotes || proposal.forVotes <= proposal.totalVotes / 2) {
      return ProposalState.Defeated;
    } else if (proposal.executed) {
      return ProposalState.Executed;
    } else {
      return ProposalState.Succeeded;
    }
  }

  receive() external payable {
    if (msg.value != 0) {
      emit receiveDeposit(msg.sender, msg.value);
    }
  }

  /// Add a member
  /// @param member The new member address
  function addMember(address member) external onlyInit onlyGov {
    require(members[member] == 0, "member already exists");
    memberSet.push(member);
    members[member] = memberSet.length;
    emit MemberAdded(member);
  }

  /// Remove a member
  /// @param member The address of the member to remove
  function removeMember(address member) external onlyInit onlyGov {
    uint256 index = members[member];
    require(index != 0, "member does not exist");
    if (index != memberSet.length) {
      address addr = memberSet[memberSet.length - 1];
      memberSet[index - 1] = addr;
      members[addr] = index;
    }
    memberSet.pop();
    delete members[member];
    emit MemberDeleted(member);
  }

  /// Get all members
  /// @return List of member addresses
  function getMembers() external view returns (address[] memory) {
    return memberSet;
  }

  /// Update parameters through governance vote
  /// @param key The name of the parameter
  /// @param value the new value set to the parameter
  function updateParam(string calldata key, bytes calldata value) external override onlyInit onlyGov {
    if (Memory.compareStrings(key, "proposalMaxOperations")) {
      require(value.length == 32, "length of proposalMaxOperations mismatch");
      uint256 newProposalMaxOperations = BytesToTypes.bytesToUint256(32, value);
      require(newProposalMaxOperations != 0, "the proposalMaxOperations out of range");
      proposalMaxOperations = newProposalMaxOperations;
    } else if (Memory.compareStrings(key, "votingPeriod")) {
      require(value.length == 32, "length of votingPeriod mismatch");
      uint256 newVotingPeriod = BytesToTypes.bytesToUint256(32, value);
      require(newVotingPeriod >= 28800, "the votingPeriod out of range");
      votingPeriod = newVotingPeriod;
    } else {
      require(false, "unknown param");
    }
    emit paramChange(key, value);
  }
}
