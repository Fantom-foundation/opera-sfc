pragma solidity ^0.5.0;

import "../sfc/NodeDriver.sol";

contract StubEvmWriter is EVMWriter {
    function setBalance(address acc, uint256 value) external {}

    function copyCode(address acc, address from) external {}

    function swapCode(address acc, address with) external {}

    function setStorage(address acc, bytes32 key, bytes32 value) external {}

    function incNonce(address acc, uint256 diff) external {}
}
