pragma solidity ^0.5.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "../common/Decimal.sol";

contract StakersConstants {
    using SafeMath for uint256;

    uint256 internal constant OK_STATUS = 0;
    uint256 internal constant WITHDRAWN_BIT = 1;
    uint256 internal constant OFFLINE_BIT = 1 << 3;
    uint256 internal constant DOUBLESIGN_BIT = 1 << 7;
    uint256 internal constant CHEATER_MASK = DOUBLESIGN_BIT;

    /**
     * @dev Minimum amount of stake for a validator, i.e., 3175000 FTM
     */
    function minSelfStake() public pure returns (uint256) {
        // 3175000 FTM
        return 3175000 * 1e18;
    }

    /**
     * @dev Maximum ratio of delegations a validator can have, say, 15 times of self-stake
     */
    function maxDelegatedRatio() public pure returns (uint256) {
        // 1600%
        return 16 * Decimal.unit();
    }

    /**
     * @dev The commission fee in percentage a validator will get from a delegation, e.g., 15%
     */
    function validatorCommission() public pure returns (uint256) {
        // 15%
        return (15 * Decimal.unit()) / 100;
    }

    /**
     * @dev The commission fee in percentage a validator will get from a contract, e.g., 30%
     */
    function contractCommission() public pure returns (uint256) {
        // 30%
        return (30 * Decimal.unit()) / 100;
    }

    /**
     * @dev The ratio of the reward rate at base rate (no lock), e.g., 30%
     */
    function unlockedRewardRatio() public pure returns (uint256) {
        // 30%
        return (30 * Decimal.unit()) / 100;
    }

    /**
     * @dev The minimum duration of a stake/delegation lockup, e.g. 2 weeks
     */
    function minLockupDuration() public pure returns (uint256) {
        return 86400 * 14;
    }

    /**
     * @dev The maximum duration of a stake/delegation lockup, e.g. 1 year
     */
    function maxLockupDuration() public pure returns (uint256) {
        return 86400 * 365;
    }

    /**
     * @dev the period of time that stake is locked
     */
    function stakeLockPeriodTime() public pure returns (uint256) {
        // 7 days
        return 60 * 60 * 24 * 7;
    }

    /**
     * @dev the number of epochs that stake is locked
     */
    function unstakePeriodEpochs() public pure returns (uint256) {
        return 3;
    }

    function unstakePeriodTime() public pure returns (uint256) {
        // 7 days
        return 60 * 60 * 24 * 7;
    }

    /**
     * @dev number of epochs to lock a delegation
     */
    function delegationLockPeriodEpochs() public pure returns (uint256) {
        return 3;
    }
}
