pragma solidity ^0.5.0;

import "@openzeppelin/contracts/math/SafeMath.sol";

interface ILockable {
    using SafeMath for uint256;

    function lock(uint256 duration) external payable;

    function unlock() external payable;

}