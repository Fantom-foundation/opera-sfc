pragma solidity ^0.5.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "../common/Decimal.sol";
import "../adapters/GovernanceToSFC.sol";

contract NetworkParameters is GovernanceToSFC {
    using SafeMath for uint256;

    uint256 private minStakeAmnt;
    uint256 private maxDelegation;
    uint256 private validatorCommissionFee;
    uint256 private contractCommissionFee;
    uint256 private unlockedReward;
    uint256 private minLockup;
    uint256 private maxLockup;
    uint256 private withdrawalPeriodEpochValue;
    uint256 private withdrawalPeriodTimeValue;

/** 
    event UpdatedMinSelfStake(uint256 minSelfStake);
    event UpdatedMaxDelegationRatio(uint256 maxDelegationRatio);
    event UpdatedValidatorCommission(uint256 validatorCommission);
    event UpdatedContractCommission(uint256 contractCommission);
    event UpdatedUnlockedRewardRatio(uint256 unlockedRewardRatio);
    event UpdatedMinLockupDuration(uint256 minLockupDuration);
    event UpdatedMaxLockupDuration(uint256 maxLockupDuration);
    event UpdatedWithdrawalPeriodEpoch(uint256 Value);
    event UpdatedWithdrawalPeriodTime(uint256 withValuedrawalPeriodTime);
*/
    /**
     * @dev Initializes the contract setting the default governance contract.
     
    function initialize(address _governance) internal initializer {
        governance = Governance(_governance);
        //emit GovernanceUpdated(address(0), _governance);
    }*/

    function _onlyGovernance(address _sender) internal view {
        require(
            (_sender == address(governance) || _sender == owner()),
            "SFC: this function is controlled by the owner and governance contract"
        );
    }

    function setMaxDelegation(uint256 _maxDelegationRatio) external {
        _onlyGovernance(msg.sender);
        maxDelegation = _maxDelegationRatio;
        //emit UpdatedMaxDelegationRatio(_maxDelegationRatio);
    }

    function setMinSelfStake(uint256 _minSelfStake) external {
        _onlyGovernance(msg.sender);
        minStakeAmnt = _minSelfStake;
        //emit UpdatedMinSelfStake(_minSelfStake);
    }

    function setValidatorCommission(uint256 _validatorCommission) external {
        _onlyGovernance(msg.sender);
        validatorCommissionFee = _validatorCommission;
        //emit UpdatedValidatorCommission(_validatorCommission);
    }

    function setContractCommission(uint256 _contractCommission) external {
        _onlyGovernance(msg.sender);
        contractCommissionFee = _contractCommission;
        //emit UpdatedContractCommission(_contractCommission);
    }

    function setUnlockedRewardRatio(uint256 _unlockedReward) external {
        _onlyGovernance(msg.sender);
        unlockedReward = _unlockedReward;
        //emit UpdatedUnlockedRewardRatio(_unlockedReward);
    }

    function setMinLockupDuration(uint256 _minLockupDuration) external {
        _onlyGovernance(msg.sender);
        minLockup = _minLockupDuration;
        //emit UpdatedMinLockupDuration(_minLockupDuration);
    }

    function setMaxLockupDuration(uint256 _maxLockupDuration) external {
        _onlyGovernance(msg.sender);
        maxLockup = _maxLockupDuration;
        //emit UpdatedMaxLockupDuration(_maxLockupDuration);
    }

    function setWithdrawalPeriodEpoch(uint256 _withdrawalPeriodEpochs)
        external
    {
        _onlyGovernance(msg.sender);
        withdrawalPeriodEpochValue = _withdrawalPeriodEpochs;
        //emit UpdatedWithdrawalPeriodEpoch(_withdrawalPeriodEpochs);
    }

    function setWithdrawalPeriodTime(uint256 _withdrawalPeriodTime) external {
        _onlyGovernance(msg.sender);
        withdrawalPeriodTimeValue = _withdrawalPeriodTime;
        //emit UpdatedWithdrawalPeriodTime(_withdrawalPeriodTime);
    }

    /**
     * @dev Minimum amount of stake for a validator, i.e., 500000 FTM
     */
    function minSelfStake() public view returns (uint256) {
        return minStakeAmnt * Decimal.unit();
    }

    function maxDelegatedRatio() public view returns (uint256) {
        return maxDelegation * Decimal.unit();
    }

    /**
     * @dev The commission fee in percentage a validator will get from a delegation, e.g., 15%
     */
    function validatorCommission() public view returns (uint256) {
        return (validatorCommissionFee * Decimal.unit()) / 100;
    }

    /**
     * @dev The commission fee in percentage a validator will get from a contract, e.g., 30%
     */
    function contractCommission() public view returns (uint256) {
        return (contractCommissionFee * Decimal.unit()) / 100;
    }

    /**
     * @dev The ratio of the reward rate at base rate (no lock), e.g., 30%
     */
    function unlockedRewardRatio() public view returns (uint256) {
        return (unlockedReward * Decimal.unit()) / 100;
    }

    /**
     * @dev The minimum duration of a stake/delegation lockup, e.g. 2 weeks
     */
    function minLockupDuration() public view returns (uint256) {
        return minLockup * 14;
    }

    /**
     * @dev The maximum duration of a stake/delegation lockup, e.g. 1 year
     */
    function maxLockupDuration() public view returns (uint256) {
        return maxLockup * 365;
    }

    /**
     * @dev the number of epochs that stake is locked
     */
    function withdrawalPeriodEpochs() public view returns (uint256) {
        return withdrawalPeriodEpochValue;
    }

    function withdrawalPeriodTime() public view returns (uint256) {
        return withdrawalPeriodTimeValue;
    }
}
