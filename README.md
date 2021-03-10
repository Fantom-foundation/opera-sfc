# Special Fee Contract

The SFC (Special Fee Contract) maintains a list of validation stakers and delegators.
It distributes the rewards, based on information written into contract by Lachesis node.

The essential:
- SFC contract only maintains the list of delegators and stakers, and doesn’t calculate reward weights or validators groups. The reward weights and validators group are written into SFC contract storage by consensus (i.e. golang code) for performance reasons. SFC calculates the rewards, depending on epoch snapshots written by consensus.
- Calculation of reward is O(1) for each epoch. Staker/delegator may specify a range of epochs he claims reward for, but not lower than `prev reward epoch + 1` and not higher than `last sealed epoch snapshot`.
- Each delegation is a separate object. Delegator claims rewards for each delegation independently of other delegations and stakers. Staker has a counter of delegated tokens to it.
- Staker/delegator cannot withdraw his stake any time. He must deactivate the stake (prepare to withdraw) in advance of N days.
- If validator is confirmed to be a cheater, then only a flag is written into SFC storage by consensus. SFC checks this flag and doesn't withdraw stake/delegation during `withdraw` operation if flag is set.
- Validation staker is allowed to increase his stake, but not decrease (only allowed to withdraw the whole stake).

# Compile

1. Install solc 0.5.12
2. `solc -o $PWD/build --optimize --optimize-runs=2000 --abi --bin-runtime --allow-paths $PWD/contracts --overwrite $PWD/contracts/sfc/Staker.sol` # compilation. don't forget --bin-runtime flag, if contract is pre-deployed!
3. `cat build/TestStakers.bin-runtime` # paste this into GetTestContractBinV1 in go-lachesis repo
4. `cat build/TestStakers.abi` # use this ABI to call contract methods

# Test

1. Install nodejs 10.5.0
2. `npm install -g truffle@v5.1.4` # install truffle v5.1.4
3. `npm update`
4. `npm test`

If everything is allright, it should output something along this:
```
Compiling your contracts...
===========================
> Compiling ./contracts/common/Decimal.sol
> Compiling ./contracts/common/Initializable.sol
> Compiling ./contracts/common/ReentrancyGuard.sol
> Compiling ./contracts/ownership/Ownable.sol
> Compiling ./contracts/sfc/LegacySfcWrapper.sol
> Compiling ./contracts/sfc/Migrations.sol
> Compiling ./contracts/sfc/NetworkInitializer.sol
> Compiling ./contracts/sfc/NodeDriver.sol
> Compiling ./contracts/sfc/SFC.sol
> Compiling ./contracts/sfc/StakerConstants.sol
> Compiling ./contracts/test/StubEvmWriter.sol
> Compiling ./contracts/test/UnitTestSFC.sol
> Compiling ./contracts/version/Version.sol
> Compiling @openzeppelin/contracts/math/SafeMath.sol



  Contract: SFC
    Test minSelfStake from StakersConstants
      ✓ Check minSelfStake (86ms)

  Contract: SFC
    Genesis Validator
      ✓ Set Genesis Validator with bad Status (51ms)
      ✓ should reject sealEpoch if not called by Node (52ms)
      ✓ should reject SealEpochValidators if not called by Node (51ms)

  Contract: SFC
    Basic functions
      Constants
        ✓ Returns current Epoch
        ✓ Returns minimum amount to stake for a Validator
        ✓ Returns the maximum ratio of delegations a validator can have
        ✓ Returns commission fee in percentage a validator will get from a delegation
        ✓ Returns commission fee in percentage a validator will get from a contract
        ✓ Returns the ratio of the reward rate at base rate (without lockup)
        ✓ Returns the minimum duration of a stake/delegation lockup
        ✓ Returns the maximum duration of a stake/delegation lockup
        ✓ Returns the period of time that stake is locked
        ✓ Returns the number of epochs that stake is locked
        ✓ Returns the version of the current implementation
        ✓ Should create a Validator and return the ID (87ms)
        ✓ Should create two Validators and return the correct last validator ID (170ms)
        ✓ Should return Delegation (115ms)
        ✓ Should reject if amount is insufficient for self-stake (50ms)
        ✓ Returns current Epoch
        ✓ Should return current Sealed Epoch
        ✓ Should return Now()
      Initialize
        ✓ Should have been initialized with firstValidator
      Ownable
        ✓ Should return the owner of the contract
        ✓ Should return true if the caller is the owner of the contract
        ✓ Should return address(0) if owner leaves the contract without owner (67ms)
        ✓ Should transfer ownership to the new owner (56ms)
        ✓ Should not be able to transfer ownership if not owner
        ✓ Should not be able to transfer ownership to address(0)
      Events emitters
        ✓ Should call updateNetworkRules
        ✓ Should call updateOfflinePenaltyThreshold

  Contract: SFC
    Prevent Genesis Call if not node
      ✓ Should not be possible add a Genesis Validator if called not by node (46ms)
      ✓ Should not be possible add a Genesis Delegation if called not by node
    Create validators
      ✓ Should create Validators (193ms)
      ✓ Should return the right ValidatorID by calling getValidatorID (285ms)
      ✓ Should not be able to stake if Validator not created yet (318ms)
      ✓ Should stake with different delegators (417ms)
      ✓ Should return the amount of delegated for each Delegator (665ms)
      ✓ Should return the total of received Stake (261ms)
      ✓ Should return the total of received Stake (218ms)

  Contract: SFC
    Returns Validator
      ✓ Should returns Validator' status 
      ✓ Should returns Validator' Deactivated Time
      ✓ Should returns Validator' Deactivated Epoch
      ✓ Should returns Validator's Received Stake
      ✓ Should returns Validator's Created Epoch
      ✓ Should returns Validator's Created Time
      ✓ Should returns Validator's Auth (address)
    EpochSnapshot
      ✓ Returns stashedRewardsUntilEpoch (257ms)
    Methods tests
      ✓ checking createValidator function (370ms)
      ✓ checking sealing epoch (416ms)

  Contract: SFC
    Staking / Sealed Epoch functions
      ✓ Should return claimed Rewards until Epoch (440ms)
      ✓ Check pending Rewards of delegators (277ms)
      ✓ Check if pending Rewards have been increased after sealing Epoch (451ms)
      ✓ Should increase balances after claiming Rewards (408ms)
      ✓ Should increase stake after restaking Rewards (479ms)
      ✓ Should increase locked stake after restaking Rewards (580ms)
      ✓ Should return stashed Rewards (399ms)
      ✓ Should update the validator on node (50ms)
      ✓ Should not be able to deactivate validator if not Node (61ms)
      ✓ Should seal Epochs (139ms)
      ✓ Should seal Epoch on Validators (194ms)
    Stake lockup
      ✓ Check pending Rewards of delegators (281ms)
      ✓ Check if pending Rewards have been increased after sealing Epoch (441ms)
      ✓ Should increase balances after claiming Rewards (413ms)
      ✓ Should return stashed Rewards (479ms)
      ✓ Should return pending rewards after unlocking and re-locking (3494ms)

  Contract: SFC
    Staking / Sealed Epoch functions
      ✓ Should setGenesisDelegation Validator (67ms)


  67 passing (45s)
```
