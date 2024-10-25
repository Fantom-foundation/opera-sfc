// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IEvmWriter} from "../interfaces/IEvmWriter.sol";

contract StubEvmWriter is IEvmWriter {
    function setBalance(address acc, uint256 value) external {}

    function copyCode(address acc, address from) external {}

    function swapCode(address acc, address where) external {}

    function setStorage(address acc, bytes32 key, bytes32 value) external {}

    function incNonce(address acc, uint256 diff) external {}
}
