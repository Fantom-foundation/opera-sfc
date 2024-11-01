// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

/**
 * @title Initializable
 *
 * @dev Helper contract to support initializer functions. To use it, replace
 * the constructor with a function that has the `initializer` modifier.
 * WARNING: Unlike constructors, initializer functions must be manually
 * invoked. This applies both to deploying an Initializable contract, as well
 * as extending an Initializable contract via inheritance.
 * WARNING: When used with inheritance, manual care must be taken to not invoke
 * a parent initializer twice, or ensure that all initializers are idempotent,
 * because this is not dealt with automatically as with constructors.
 *
 * @custom:security-contact security@fantom.foundation
 */
contract Initializable {
    /**
     * @dev Indicates that the contract has been initialized.
     */
    bool private initialized;

    /**
     * @dev Indicates that the contract is in the process of being initialized.
     */
    bool private initializing;

    /**
     * @dev The contract instance has already been initialized.
     */
    error InvalidInitialization();

    /**
     * @dev Modifier to use in the initializer function of a contract.
     */
    modifier initializer() {
        if (!initializing && initialized) {
            revert InvalidInitialization();
        }

        bool isTopLevelCall = !initializing;
        if (isTopLevelCall) {
            initializing = true;
            initialized = true;
        }

        _;

        if (isTopLevelCall) {
            initializing = false;
        }
    }

    // Reserved storage space to allow for layout changes in the future.
    uint256[50] private ______gap;
}
