pragma solidity ^0.5.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "../ownership/Ownable.sol";
import "../common/Decimal.sol";

contract ConstantsManager is Ownable {
    using SafeMath for uint256;

    // Minimum amount of stake for a validator, i.e., 500000 FTM
    uint256 public minSelfStake;
    // Maximum ratio of delegations a validator can have, say, 15 times of self-stake
    uint256 public maxDelegatedRatio;
    // The commission fee in percentage a validator will get from a delegation, e.g., 15%
    uint256 public validatorCommission;
    // The percentage of fees to burn, e.g., 20%
    uint256 public burntFeeShare;
    // The percentage of fees to transfer to treasury address, e.g., 10%
    uint256 public treasuryFeeShare;
    // The ratio of the reward rate at base rate (no lock), e.g., 30%
    uint256 public unlockedRewardRatio;
    // The minimum duration of a stake/delegation lockup, e.g. 2 weeks
    uint256 public minLockupDuration;
    // The maximum duration of a stake/delegation lockup, e.g. 1 year
    uint256 public maxLockupDuration;
    // the number of epochs that undelegated stake is locked for
    uint256 public withdrawalPeriodEpochs;
    // the number of seconds that undelegated stake is locked for
    uint256 public withdrawalPeriodTime;

    uint256 public baseRewardPerSecond;
    uint256 public offlinePenaltyThresholdBlocksNum;
    uint256 public offlinePenaltyThresholdTime;
    uint256 public targetGasPowerPerSecond;
    uint256 public gasPriceBalancingCounterweight;

    address public secondaryOwner;

    event SecondaryOwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function initialize() external initializer {
        Ownable.initialize(msg.sender);
    }

    modifier onlyAnyOwner() {
        require(isOwner() || msg.sender == secondaryOwner, "Ownable: caller is not the owner");
        _;
    }

    function setSecondaryOwner(address v) onlyOwner external {
        emit SecondaryOwnershipTransferred(secondaryOwner, v);
        secondaryOwner = v;
    }

    function updateMinSelfStake(uint256 v) onlyAnyOwner external {
        require(v >= 100000 * 1e18, "too small value");
        require(v <= 10000000 * 1e18, "too large value");
        minSelfStake = v;
    }

    function updateMaxDelegatedRatio(uint256 v) onlyAnyOwner external {
        require(v >= Decimal.unit(), "too small value");
        require(v <= 31 * Decimal.unit(), "too large value");
        maxDelegatedRatio = v;
    }

    function updateValidatorCommission(uint256 v) onlyAnyOwner external {
        require(v <= Decimal.unit() / 2, "too large value");
        validatorCommission = v;
    }

    function updateBurntFeeShare(uint256 v) onlyAnyOwner external {
        require(v <= Decimal.unit() / 2, "too large value");
        burntFeeShare = v;
    }

    function updateTreasuryFeeShare(uint256 v) onlyAnyOwner external {
        require(v <= Decimal.unit() / 2, "too large value");
        treasuryFeeShare = v;
    }

    function updateUnlockedRewardRatio(uint256 v) onlyAnyOwner external {
        require(v >= (5 * Decimal.unit()) / 100, "too small value");
        require(v <= Decimal.unit() / 2, "too large value");
        unlockedRewardRatio = v;
    }

    function updateMinLockupDuration(uint256 v) onlyOwner external {
        require(v >= 86400, "too small value");
        require(v <= 86400 * 30, "too large value");
        minLockupDuration = v;
    }

    function updateMaxLockupDuration(uint256 v) onlyOwner external {
        require(v >= 86400 * 30, "too small value");
        require(v <= 86400 * 1460, "too large value");
        maxLockupDuration = v;
    }

    function updateWithdrawalPeriodEpochs(uint256 v) onlyAnyOwner external {
        require(v >= 2, "too small value");
        require(v <= 100, "too large value");
        withdrawalPeriodEpochs = v;
    }

    function updateWithdrawalPeriodTime(uint256 v) onlyAnyOwner external {
        require(v >= 86400, "too small value");
        require(v <= 30 * 86400, "too large value");
        withdrawalPeriodTime = v;
    }

    function updateBaseRewardPerSecond(uint256 v) onlyAnyOwner external {
        require(v >= 0.5 * 1e18, "too small value");
        require(v <= 32 * 1e18, "too large value");
        baseRewardPerSecond = v;
    }

    function updateOfflinePenaltyThresholdTime(uint256 v) onlyAnyOwner external {
        require(v >= 86400, "too small value");
        require(v <= 10 * 86400, "too large value");
        offlinePenaltyThresholdTime = v;
    }

    function updateOfflinePenaltyThresholdBlocksNum(uint256 v) onlyAnyOwner external {
        require(v >= 100, "too small value");
        require(v <= 1000000, "too large value");
        offlinePenaltyThresholdBlocksNum = v;
    }

    function updateTargetGasPowerPerSecond(uint256 v) onlyOwner external {
        require(v >= 1000000, "too small value");
        require(v <= 500000000, "too large value");
        targetGasPowerPerSecond = v;
    }

    function updateGasPriceBalancingCounterweight(uint256 v) onlyOwner external {
        require(v >= 100, "too small value");
        require(v <= 10 * 86400, "too large value");
        gasPriceBalancingCounterweight = v;
    }
}
