pragma solidity ^0.5.0;

import "@openzeppelin/contracts/math/SafeMath.sol";

/**
 * @dev
 */
interface IReward {
    //function _calcRawValidatorEpochBaseReward(uint256 epochDuration, uint256 baseRewardPerSecond, uint256 baseRewardWeight, uint256 totalBaseRewardWeight) internal pure returns (uint256);

    //function _calcRawValidatorEpochTxReward(uint256 epochFee, uint256 txRewardWeight, uint256 totalTxRewardWeight) internal pure returns (uint256);

    // function _calcValidatorCommission(uint256 rawReward, uint256 commission) internal pure returns (uint256);

    //function _highestPayableEpoch(uint256 validatorID) internal view returns (uint256);

    function pendingRewards(address delegator, uint256 toValidatorID) public view returns (uint256);

    function stashRewards(address delegator, uint256 toValidatorID) external ;

    function claimRewards(uint256 toValidatorID) external;

    function offlinePenaltyThreshold() public view returns (uint256 blocksNum, uint256 time);

    function updateBaseRewardPerSecond(uint256 value) onlyOwner external;

    function updateOfflinePenaltyThreshold(uint256 blocksNum, uint256 time) onlyOwner external;

}