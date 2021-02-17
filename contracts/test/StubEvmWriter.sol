// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "../sfc/NodeDriver.sol";

contract StubEvmWriter is IEVMWriter {
    function setBalance(address acc, uint256 value) external override {}

    function copyCode(address acc, address from) external override {}

    function swapCode(address acc, address with) external override {}

    function setStorage(address acc, bytes32 key, bytes32 value) external override {}
}
