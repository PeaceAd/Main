// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PredictionGame
 * @dev Simple onchain prediction game for Base blockchain.
 * Players can place predictions with ETH, and winners share the pot.
 * The game owner resolves outcomes (v1: manual oracle).
 */
contract PredictionGame {
    struct Prediction {
        address player;
        uint256 amount;
        bool predictedYes;
        bool claimed;
    }

    struct Round {
        string question;
        uint256 endTime;
        bool resolved;
        bool outcomeYes;
        uint256 totalYes;
        uint256 totalNo;
        mapping(address => Prediction) predictions;
        address[] participants;
    }

    uint256 public roundId;
    mapping(uint256 => Round) public rounds;
    address public owner;

    event RoundCreated(uint256 indexed roundId, string question, uint256 endTime);
    event PredictionPlaced(uint256 indexed roundId, address indexed player, bool predictedYes, uint256 amount);
    event RoundResolved(uint256 indexed roundId, bool outcomeYes);
    event RewardClaimed(uint256 indexed roundId, address indexed player, uint256 reward);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /// @notice Create a new prediction round
    function createRound(string memory _question, uint256 _durationSecs) external onlyOwner {
        roundId++;
        Round storage r = rounds[roundId];
        r.question = _question;
        r.endTime = block.timestamp + _durationSecs;
        emit RoundCreated(roundId, _question, r.endTime);
    }

    /// @notice Place a prediction (true = YES, false = NO)
    function placePrediction(uint256 _roundId, bool _yes) external payable {
        Round storage r = rounds[_roundId];
        require(block.timestamp < r.endTime, "Round ended");
        require(msg.value > 0, "Must stake ETH");
        require(r.predictions[msg.sender].amount == 0, "Already predicted");

        r.predictions[msg.sender] = Prediction(msg.sender, msg.value, _yes, false);
        r.participants.push(msg.sender);

        if (_yes) {
            r.totalYes += msg.value;
        } else {
            r.totalNo += msg.value;
        }

        emit PredictionPlaced(_roundId, msg.sender, _yes, msg.value);
    }

    /// @notice Resolve a round (manual outcome set by owner for now)
    function resolveRound(uint256 _roundId, bool _outcomeYes) external onlyOwner {
        Round storage r = rounds[_roundId];
        require(block.timestamp >= r.endTime, "Round still active");
        require(!r.resolved, "Already resolved");

        r.resolved = true;
        r.outcomeYes = _outcomeYes;

        emit RoundResolved(_roundId, _outcomeYes);
    }

    /// @notice Claim rewards if you won
    function claimReward(uint256 _roundId) external {
        Round storage r = rounds[_roundId];
        require(r.resolved, "Round not resolved");

        Prediction storage p = r.predictions[msg.sender];
        require(!p.claimed, "Already claimed");
        require(p.amount > 0, "No prediction");

        if (p.predictedYes == r.outcomeYes) {
            uint256 winnersPool = r.outcomeYes ? r.totalYes : r.totalNo;
            uint256 losersPool = r.outcomeYes ? r.totalNo : r.totalYes;
            uint256 reward = p.amount + (p.amount * losersPool) / winnersPool;

            p.claimed = true;
            payable(msg.sender).transfer(reward);

            emit RewardClaimed(_roundId, msg.sender, reward);
        } else {
            p.claimed = true; // loser gets nothing
        }
    }

    /// @notice Owner can withdraw any leftover funds (shouldn’t normally be needed)
    function withdraw() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }
}