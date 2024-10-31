import { ethers } from 'hardhat';
import { expect } from 'chai';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import {
  IEVMWriter,
  NodeDriver,
  NodeDriverAuth,
  UnitTestSFC,
  UnitTestConstantsManager,
  UnitTestNetworkInitializer,
} from '../typechain-types';
import { beforeEach, Context } from 'mocha';
import { BlockchainNode, ValidatorMetrics } from './helpers/BlockchainNode';

describe('SFC', () => {
  const fixture = async () => {
    const [owner, user] = await ethers.getSigners();
    const sfc: UnitTestSFC = await ethers.deployContract('UnitTestSFC');
    const nodeDriver: NodeDriver = await ethers.deployContract('NodeDriver');
    const evmWriter: IEVMWriter = await ethers.deployContract('StubEvmWriter');
    const nodeDriverAuth: NodeDriverAuth = await ethers.deployContract('NodeDriverAuth');
    const initializer: UnitTestNetworkInitializer = await ethers.deployContract('UnitTestNetworkInitializer');

    await initializer.initializeAll(0, 0, sfc, nodeDriverAuth, nodeDriver, evmWriter, owner);
    const constants: UnitTestConstantsManager = await ethers.getContractAt(
      'UnitTestConstantsManager',
      await sfc.constsAddress(),
    );
    await sfc.rebaseTime();

    return {
      owner,
      user,
      sfc,
      evmWriter,
      nodeDriver,
      nodeDriverAuth,
      constants,
    };
  };

  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  it('Should revert when amount sent', async function () {
    await expect(
      this.owner.sendTransaction({
        to: this.sfc,
        value: 1,
      }),
    ).to.revertedWithCustomError(this.sfc, 'TransfersNotAllowed');
  });

  describe('Genesis validator', () => {
    beforeEach(async function () {
      const validator = ethers.Wallet.createRandom();
      await this.sfc.enableNonNodeCalls();
      await this.sfc.setGenesisValidator(
        validator.address,
        1,
        validator.publicKey,
        1 << 3,
        await this.sfc.currentEpoch(),
        Date.now(),
        0,
        0,
      );
      await this.sfc.disableNonNodeCalls();
    });

    it('Should succeed and set genesis validator with bad status', async function () {
      await this.sfc._syncValidator(1, false);
    });

    it('Should revert when sealEpoch not called by node', async function () {
      await expect(this.sfc.sealEpoch([1], [1], [1], [1], 0)).to.be.revertedWithCustomError(this.sfc, 'NotDriverAuth');
    });

    it('Should revert when SealEpochValidators not called by node', async function () {
      await expect(this.sfc.sealEpochValidators([1])).to.be.revertedWithCustomError(this.sfc, 'NotDriverAuth');
    });
  });

  describe('Constants', () => {
    it('Should succeed and return now()', async function () {
      const block = await ethers.provider.getBlock('latest');
      expect(block).to.not.be.equal(null);
      expect(await this.sfc.getBlockTime()).to.be.within(block!.timestamp - 100, block!.timestamp + 100);
    });

    it('Should succeed and return getTime()', async function () {
      const block = await ethers.provider.getBlock('latest');
      expect(block).to.not.be.equal(null);
      expect(await this.sfc.getTime()).to.be.within(block!.timestamp - 100, block!.timestamp + 100);
    });

    it('Should succeed and return current epoch', async function () {
      expect(await this.sfc.currentEpoch()).to.equal(1);
    });

    it('Should succeed and return current sealed epoch', async function () {
      expect(await this.sfc.currentSealedEpoch()).to.equal(0);
    });

    it('Should succeed and return minimum amount to stake for validator', async function () {
      expect(await this.constants.minSelfStake()).to.equal(ethers.parseEther('0.3175'));
    });

    it('Should succeed and return maximum ratio of delegations a validator can have', async function () {
      expect(await this.constants.maxDelegatedRatio()).to.equal(ethers.parseEther('16'));
    });

    it('Should succeed and return commission fee in percentage a validator will get from a delegation', async function () {
      expect(await this.constants.validatorCommission()).to.equal(ethers.parseEther('0.15'));
    });

    it('Should succeed and return burnt fee share', async function () {
      expect(await this.constants.burntFeeShare()).to.equal(ethers.parseEther('0.2'));
    });

    it('Should succeed and return treasury fee share', async function () {
      expect(await this.constants.treasuryFeeShare()).to.equal(ethers.parseEther('0.1'));
    });

    it('Should succeed and return ratio of the reward rate at base rate (without lockup)', async function () {
      expect(await this.constants.unlockedRewardRatio()).to.equal(ethers.parseEther('0.3'));
    });

    it('Should succeed and return minimum duration of a stake/delegation lockup', async function () {
      expect(await this.constants.minLockupDuration()).to.equal(86400 * 14);
    });

    it('Should succeed and return maximum duration of a stake/delegation lockup', async function () {
      expect(await this.constants.maxLockupDuration()).to.equal(86400 * 365);
    });

    it('Should succeed and return period of time that stake is locked', async function () {
      expect(await this.constants.withdrawalPeriodTime()).to.equal(60 * 60 * 24 * 7);
    });

    it('Should succeed and return number of epochs that stake is locked', async function () {
      expect(await this.constants.withdrawalPeriodEpochs()).to.equal(3);
    });

    it('Should succeed and return version of the current implementation', async function () {
      expect(await this.sfc.version()).to.equal(ethers.hexlify(ethers.toUtf8Bytes('305')));
    });
  });

  describe('Create validator', () => {
    const validatorsFixture = async () => {
      const [validator, secondValidator] = await ethers.getSigners();
      return {
        validator,
        secondValidator,
      };
    };

    beforeEach(async function () {
      Object.assign(this, await loadFixture(validatorsFixture));
    });

    it('Should succeed and create a validator and return its id', async function () {
      await this.sfc
        .connect(this.validator)
        .createValidator(ethers.Wallet.createRandom().publicKey, { value: ethers.parseEther('0.4') });
      expect(await this.sfc.lastValidatorID()).to.equal(1);
    });

    it('Should revert when insufficient self-stake to create a validator', async function () {
      await expect(
        this.sfc
          .connect(this.validator)
          .createValidator(ethers.Wallet.createRandom().publicKey, { value: ethers.parseEther('0.1') }),
      ).to.be.revertedWithCustomError(this.sfc, 'InsufficientSelfStake');
    });

    it('Should revert when public key is empty while creating a validator', async function () {
      await expect(
        this.sfc.connect(this.validator).createValidator('0x', { value: ethers.parseEther('0.4') }),
      ).to.be.revertedWithCustomError(this.sfc, 'EmptyPubkey');
    });

    it('Should succeed and create two validators and return id of last validator', async function () {
      expect(await this.sfc.lastValidatorID()).to.equal(0);
      expect(await this.sfc.getValidatorID(this.validator)).to.equal(0);
      expect(await this.sfc.getValidatorID(this.secondValidator)).to.equal(0);

      await this.sfc
        .connect(this.validator)
        .createValidator(ethers.Wallet.createRandom().publicKey, { value: ethers.parseEther('0.4') });
      expect(await this.sfc.getValidatorID(this.validator)).to.equal(1);
      expect(await this.sfc.lastValidatorID()).to.equal(1);

      await this.sfc
        .connect(this.secondValidator)
        .createValidator(ethers.Wallet.createRandom().publicKey, { value: ethers.parseEther('0.5') });
      expect(await this.sfc.getValidatorID(this.secondValidator)).to.equal(2);
      expect(await this.sfc.lastValidatorID()).to.equal(2);
    });

    it('Should succeed and return delegation', async function () {
      await this.sfc
        .connect(this.secondValidator)
        .createValidator(ethers.Wallet.createRandom().publicKey, { value: ethers.parseEther('0.5') });
      await this.sfc.connect(this.secondValidator).delegate(1, { value: ethers.parseEther('0.1') });
    });

    it('Should revert when staking to non-existing validator', async function () {
      await expect(
        this.sfc.connect(this.secondValidator).delegate(1, { value: ethers.parseEther('0.1') }),
      ).to.be.revertedWithCustomError(this.sfc, 'ValidatorNotExists');
    });

    it('Should succeed and stake with different delegators', async function () {
      await this.sfc
        .connect(this.validator)
        .createValidator(ethers.Wallet.createRandom().publicKey, { value: ethers.parseEther('0.5') });
      await this.sfc.connect(this.validator).delegate(1, { value: ethers.parseEther('0.1') });

      await this.sfc
        .connect(this.secondValidator)
        .createValidator(ethers.Wallet.createRandom().publicKey, { value: ethers.parseEther('0.5') });
      await this.sfc.connect(this.secondValidator).delegate(2, { value: ethers.parseEther('0.3') });
      await this.sfc.connect(this.validator).delegate(1, { value: ethers.parseEther('0.2') });
    });

    it('Should succeed and return the amount of delegated for each Delegator', async function () {
      await this.sfc
        .connect(this.validator)
        .createValidator(ethers.Wallet.createRandom().publicKey, { value: ethers.parseEther('0.5') });
      await this.sfc.connect(this.validator).delegate(1, { value: ethers.parseEther('0.1') });
      expect(await this.sfc.getStake(this.validator, await this.sfc.getValidatorID(this.validator))).to.equal(
        ethers.parseEther('0.6'),
      );

      await this.sfc
        .connect(this.secondValidator)
        .createValidator(ethers.Wallet.createRandom().publicKey, { value: ethers.parseEther('0.5') });
      await this.sfc.connect(this.secondValidator).delegate(2, { value: ethers.parseEther('0.3') });
      expect(
        await this.sfc.getStake(this.secondValidator, await this.sfc.getValidatorID(this.secondValidator)),
      ).to.equal(ethers.parseEther('0.8'));

      await this.sfc.connect(this.validator).delegate(2, { value: ethers.parseEther('0.1') });
      expect(await this.sfc.getStake(this.validator, await this.sfc.getValidatorID(this.secondValidator))).to.equal(
        ethers.parseEther('0.1'),
      );
    });

    it('Should succeed and return the total of received Stake', async function () {
      await this.sfc
        .connect(this.validator)
        .createValidator(ethers.Wallet.createRandom().publicKey, { value: ethers.parseEther('0.5') });

      await this.sfc.connect(this.validator).delegate(1, { value: ethers.parseEther('0.1') });
      await this.sfc.connect(this.secondValidator).delegate(1, { value: ethers.parseEther('0.2') });

      const validator = await this.sfc.getValidator(1);
      expect(validator.receivedStake).to.equal(ethers.parseEther('0.8'));
    });
  });

  describe('Ownable', () => {
    it('Should succeed and return the owner of the contract', async function () {
      expect(await this.sfc.owner()).to.equal(this.owner);
    });

    it('Should succeed and return true if the caller is the owner of the contract', async function () {
      expect(await this.sfc.isOwner()).to.equal(true);
      expect(await this.sfc.connect(this.user).isOwner()).to.equal(false);
    });

    it('Should succeed and return address(0) if owner leaves the contract without owner', async function () {
      expect(await this.sfc.owner()).to.equal(this.owner);
      await this.sfc.renounceOwnership();
      expect(await this.sfc.owner()).to.equal(ethers.ZeroAddress);
    });

    it('Should succeed and transfer ownership to the new owner', async function () {
      expect(await this.sfc.owner()).to.equal(this.owner);
      await this.sfc.transferOwnership(this.user);
      expect(await this.sfc.owner()).to.equal(this.user);
    });

    it('Should revert when transferring ownership if not owner', async function () {
      await expect(this.sfc.connect(this.user).transferOwnership(ethers.ZeroAddress)).to.be.revertedWithCustomError(
        this.nodeDriverAuth,
        'OwnableUnauthorizedAccount',
      );
    });

    it('Should revert when transferring ownership to zero address', async function () {
      await expect(this.sfc.transferOwnership(ethers.ZeroAddress))
        .to.be.revertedWithCustomError(this.nodeDriverAuth, 'OwnableInvalidOwner')
        .withArgs(ethers.ZeroAddress);
    });
  });

  describe('Events emitter', () => {
    it('Should succeed and call updateNetworkRules', async function () {
      await this.nodeDriverAuth.updateNetworkRules(
        '0x7b22446167223a7b224d6178506172656e7473223a357d2c2245636f6e6f6d79223a7b22426c6f636b4d6973736564536c61636b223a377d2c22426c6f636b73223a7b22426c6f636b476173486172644c696d6974223a313030307d7d',
      );
    });

    it('Should succeed and call updateOfflinePenaltyThreshold', async function () {
      await this.constants.updateOfflinePenaltyThresholdTime(86_400);
      await this.constants.updateOfflinePenaltyThresholdBlocksNum(1_000);
    });
  });

  describe('Prevent Genesis Call if not node', () => {
    it('Should revert when setGenesisValidator is not called not node', async function () {
      const validator = ethers.Wallet.createRandom();
      await expect(
        this.sfc.setGenesisValidator(
          validator,
          1,
          validator.publicKey,
          0,
          await this.sfc.currentEpoch(),
          Date.now(),
          0,
          0,
        ),
      ).to.be.revertedWithCustomError(this.sfc, 'NotDriverAuth');
    });

    it('Should revert when setGenesisDelegation is not called not node', async function () {
      const delegator = ethers.Wallet.createRandom();
      await expect(this.sfc.setGenesisDelegation(delegator, 1, 100, 0, 0, 0, 0, 0, 1000)).to.be.revertedWithCustomError(
        this.sfc,
        'NotDriverAuth',
      );
    });
  });

  describe('Validator', () => {
    const validatorsFixture = async function (this: Context) {
      const [validator, delegator, secondDelegator, thirdDelegator] = await ethers.getSigners();

      await this.sfc
        .connect(validator)
        .createValidator(ethers.Wallet.createRandom().publicKey, { value: ethers.parseEther('10') });
      await this.sfc.connect(delegator).delegate(1, { value: ethers.parseEther('11') });

      await this.sfc.connect(secondDelegator).delegate(1, { value: ethers.parseEther('8') });
      await this.sfc.connect(thirdDelegator).delegate(1, { value: ethers.parseEther('8') });

      const validatorStruct = await this.sfc.getValidator(1);

      return {
        validator,
        validatorStruct,
        delegator,
        secondDelegator,
        thirdDelegator,
      };
    };

    beforeEach(async function () {
      return Object.assign(this, await loadFixture(validatorsFixture.bind(this)));
    });

    describe('Returns Validator', () => {
      it('Should succeed and return validator status', async function () {
        expect(this.validatorStruct.status).to.equal(0);
      });

      it('Should succeed and return validator deactivated time', async function () {
        expect(this.validatorStruct.deactivatedTime).to.equal(0);
      });

      it('Should succeed and return validator deactivated Epoch', async function () {
        expect(this.validatorStruct.deactivatedEpoch).to.equal(0);
      });

      it('Should succeed and return validator Received Stake', async function () {
        expect(this.validatorStruct.receivedStake).to.equal(ethers.parseEther('37'));
      });

      it('Should succeed and return validator Created Epoch', async function () {
        expect(this.validatorStruct.createdEpoch).to.equal(1);
      });

      it('Should succeed and return validator Created Time', async function () {
        const block = await ethers.provider.getBlock('latest');
        expect(block).to.not.equal(null);
        expect(this.validatorStruct.createdTime).to.be.within(block!.timestamp - 5, block!.timestamp + 5);
      });

      it('Should succeed and return validator Auth (address)', async function () {
        expect(this.validatorStruct.auth).to.equal(this.validator.address);
      });
    });

    describe('EpochSnapshot', () => {
      it('Should succeed and return stashedRewardsUntilEpoch', async function () {
        expect(await this.sfc.currentEpoch.call()).to.equal(1);
        expect(await this.sfc.currentSealedEpoch()).to.equal(0);
        await this.sfc.enableNonNodeCalls();
        await this.sfc.sealEpoch([100, 101, 102], [100, 101, 102], [100, 101, 102], [100, 101, 102], 0);
        expect(await this.sfc.currentEpoch.call()).to.equal(2);
        expect(await this.sfc.currentSealedEpoch()).to.equal(1);
        for (let i = 0; i < 4; i++) {
          await this.sfc.sealEpoch([100, 101, 102], [100, 101, 102], [100, 101, 102], [100, 101, 102], 0);
        }
        expect(await this.sfc.currentEpoch.call()).to.equal(6);
        expect(await this.sfc.currentSealedEpoch()).to.equal(5);
      });

      it('Should succeed and return endBlock', async function () {
        const epochNumber = await this.sfc.currentEpoch();
        await this.sfc.enableNonNodeCalls();
        await this.sfc.sealEpoch([100, 101, 102], [100, 101, 102], [100, 101, 102], [100, 101, 102], 0);
        const lastBlock = await ethers.provider.getBlockNumber();
        // endBlock is on second position
        expect((await this.sfc.getEpochSnapshot(epochNumber))[1]).to.equal(lastBlock);
        expect(await this.sfc.getEpochEndBlock(epochNumber)).to.equal(lastBlock);
      });
    });
  });

  describe('Methods tests', () => {
    it('Should succeed and check createValidator function', async function () {
      const node = new BlockchainNode(this.sfc);
      const [validator, secondValidator] = await ethers.getSigners();
      const pubkey = ethers.Wallet.createRandom().publicKey;
      const secondPubkey = ethers.Wallet.createRandom().publicKey;
      await this.sfc.enableNonNodeCalls();

      expect(await this.sfc.lastValidatorID()).to.equal(0);

      await expect(
        this.sfc
          .connect(validator)
          .createValidator(ethers.Wallet.createRandom().publicKey, { value: ethers.parseEther('0.1') }),
      ).to.be.revertedWithCustomError(this.sfc, 'InsufficientSelfStake');

      await node.handleTx(
        await this.sfc.connect(validator).createValidator(pubkey, { value: ethers.parseEther('0.3175') }),
      );

      await expect(
        this.sfc
          .connect(validator)
          .createValidator(ethers.Wallet.createRandom().publicKey, { value: ethers.parseEther('0.5') }),
      ).to.be.revertedWithCustomError(this.sfc, 'ValidatorExists');

      await node.handleTx(
        await this.sfc.connect(secondValidator).createValidator(secondPubkey, { value: ethers.parseEther('0.5') }),
      );

      expect(await this.sfc.lastValidatorID()).to.equal(2);
      expect(await this.sfc.totalStake()).to.equal(ethers.parseEther('0.8175'));

      const firstValidatorID = await this.sfc.getValidatorID(validator);
      const secondValidatorID = await this.sfc.getValidatorID(secondValidator);
      expect(firstValidatorID).to.equal(1);
      expect(secondValidatorID).to.equal(2);

      expect(await this.sfc.getValidatorPubkey(firstValidatorID)).to.equal(pubkey);
      expect(await this.sfc.getValidatorPubkey(secondValidatorID)).to.equal(secondPubkey);

      const firstValidatorObj = await this.sfc.getValidator(firstValidatorID);
      const secondValidatorObj = await this.sfc.getValidator(secondValidatorID);

      // check first validator object
      expect(firstValidatorObj.receivedStake).to.equal(ethers.parseEther('0.3175'));
      expect(firstValidatorObj.createdEpoch).to.equal(1);
      expect(firstValidatorObj.auth).to.equal(validator.address);
      expect(firstValidatorObj.status).to.equal(0);
      expect(firstValidatorObj.deactivatedTime).to.equal(0);
      expect(firstValidatorObj.deactivatedEpoch).to.equal(0);

      // check second validator object
      expect(secondValidatorObj.receivedStake).to.equal(ethers.parseEther('0.5'));
      expect(secondValidatorObj.createdEpoch).to.equal(1);
      expect(secondValidatorObj.auth).to.equal(secondValidator.address);
      expect(secondValidatorObj.status).to.equal(0);
      expect(secondValidatorObj.deactivatedTime).to.equal(0);
      expect(secondValidatorObj.deactivatedEpoch).to.equal(0);

      // // check created delegations
      expect(await this.sfc.getStake(validator, firstValidatorID)).to.equal(ethers.parseEther('0.3175'));
      expect(await this.sfc.getStake(secondValidator, secondValidatorID)).to.equal(ethers.parseEther('0.5'));

      // check fired node-related logs
      expect(node.nextValidatorWeights.size).to.equal(2);
      expect(node.nextValidatorWeights.get(firstValidatorID)).to.equal(ethers.parseEther('0.3175'));
      expect(node.nextValidatorWeights.get(secondValidatorID)).to.equal(ethers.parseEther('0.5'));
    });

    it('Should succeed and check sealing epoch', async function () {
      const node = new BlockchainNode(this.sfc);
      const [validator, secondValidator, thirdValidator] = await ethers.getSigners();
      await this.sfc.enableNonNodeCalls();

      await node.handleTx(
        await this.sfc
          .connect(validator)
          .createValidator(ethers.Wallet.createRandom().publicKey, { value: ethers.parseEther('0.3175') }),
      );

      await node.handleTx(
        await this.sfc
          .connect(secondValidator)
          .createValidator(ethers.Wallet.createRandom().publicKey, { value: ethers.parseEther('0.6825') }),
      );

      await node.sealEpoch(100);

      const firstValidatorID = await this.sfc.getValidatorID(validator);
      const secondValidatorID = await this.sfc.getValidatorID(secondValidator);
      expect(firstValidatorID).to.equal(1);
      expect(secondValidatorID).to.equal(2);

      await node.handleTx(await this.sfc.connect(validator).delegate(1, { value: ethers.parseEther('0.1') }));

      await node.handleTx(
        await this.sfc
          .connect(thirdValidator)
          .createValidator(ethers.Wallet.createRandom().publicKey, { value: ethers.parseEther('0.4') }),
      );
      const thirdValidatorID = await this.sfc.getValidatorID(thirdValidator);

      // check fired node-related logs
      expect(node.validatorWeights.size).to.equal(2);
      expect(node.validatorWeights.get(firstValidatorID)).to.equal(ethers.parseEther('0.3175'));
      expect(node.validatorWeights.get(secondValidatorID)).to.equal(ethers.parseEther('0.6825'));
      expect(node.nextValidatorWeights.size).to.equal(3);
      expect(node.nextValidatorWeights.get(firstValidatorID)).to.equal(ethers.parseEther('0.4175'));
      expect(node.nextValidatorWeights.get(secondValidatorID)).to.equal(ethers.parseEther('0.6825'));
      expect(node.nextValidatorWeights.get(thirdValidatorID)).to.equal(ethers.parseEther('0.4'));
    });

    it('Should succeed and balance gas price', async function () {
      const [validator] = await ethers.getSigners();
      await this.sfc.enableNonNodeCalls();

      await this.constants.updateGasPriceBalancingCounterweight(24 * 60 * 60);
      await this.sfc.rebaseTime();

      await this.sfc
        .connect(validator)
        .createValidator(ethers.Wallet.createRandom().publicKey, { value: ethers.parseEther('1') });

      await this.constants.updateTargetGasPowerPerSecond(1000);
      await this.sfc.sealEpoch([1], [1], [1], [1], 1_000);
      await this.sfc.sealEpochValidators([1]);

      expect(await this.sfc.minGasPrice()).to.equal(95_000_000_000);

      await this.sfc.advanceTime(1);
      await this.sfc.sealEpoch([1], [1], [1], [1], 1_000);
      await this.sfc.sealEpochValidators([1]);
      expect(await this.sfc.minGasPrice()).to.equal(94_999_998_901);

      await this.sfc.advanceTime(2);
      await this.sfc.sealEpoch([1], [1], [1], [1], 2_000);
      await this.sfc.sealEpochValidators([1]);
      expect(await this.sfc.minGasPrice()).to.equal(94_999_997_802);

      await this.sfc.advanceTime(1_000);
      await this.sfc.sealEpoch([1], [1], [1], [1], 1_000_000);
      await this.sfc.sealEpochValidators([1]);
      expect(await this.sfc.minGasPrice()).to.equal(94_999_996_715);

      await this.sfc.advanceTime(1_000);
      await this.sfc.sealEpoch([1], [1], [1], [1], 666_666);
      await this.sfc.sealEpochValidators([1]);
      expect(await this.sfc.minGasPrice()).to.equal(94_637_676_437);

      await this.sfc.advanceTime(1_000);
      await this.sfc.sealEpoch([1], [1], [1], [1], 1_500_000);
      await this.sfc.sealEpochValidators([1]);
      expect(await this.sfc.minGasPrice()).to.equal(95_179_080_284);

      await this.sfc.advanceTime(1);
      await this.sfc.sealEpoch([1], [1], [1], [1], 666);
      await this.sfc.sealEpochValidators([1]);
      expect(await this.sfc.minGasPrice()).to.equal(95_178_711_617);

      await this.sfc.advanceTime(1);
      await this.sfc.sealEpoch([1], [1], [1], [1], 1_500);
      await this.sfc.sealEpochValidators([1]);
      expect(await this.sfc.minGasPrice()).to.equal(95_179_260_762);

      await this.sfc.advanceTime(1_000);
      await this.sfc.sealEpoch([1], [1], [1], [1], 10_000_000_000);
      await this.sfc.sealEpochValidators([1]);
      expect(await this.sfc.minGasPrice()).to.equal(99_938_223_800);

      await this.sfc.advanceTime(10_000);
      await this.sfc.sealEpoch([1], [1], [1], [1], 0);
      await this.sfc.sealEpochValidators([1]);
      expect(await this.sfc.minGasPrice()).to.equal(94_941_312_610);

      await this.sfc.advanceTime(100);
      await this.sfc.sealEpoch([1], [1], [1], [1], 200_000);
      await this.sfc.sealEpochValidators([1]);
      expect(await this.sfc.minGasPrice()).to.equal(95_051_069_157);

      await this.sfc.advanceTime(100);
      await this.sfc.sealEpoch([1], [1], [1], [1], 50_000);
      await this.sfc.sealEpochValidators([1]);
      expect(await this.sfc.minGasPrice()).to.equal(94_996_125_793);
    });
  });

  describe('Staking / Sealed Epoch functions', () => {
    const validatorsFixture = async function (this: Context) {
      const [validator, secondValidator, thirdValidator, delegator, secondDelegator] = await ethers.getSigners();
      const blockchainNode = new BlockchainNode(this.sfc);

      await this.sfc.rebaseTime();
      await this.sfc.enableNonNodeCalls();

      await blockchainNode.handleTx(
        await this.sfc
          .connect(validator)
          .createValidator(ethers.Wallet.createRandom().publicKey, { value: ethers.parseEther('0.4') }),
      );
      const validatorId = await this.sfc.getValidatorID(validator);
      await blockchainNode.handleTx(
        await this.sfc
          .connect(secondValidator)
          .createValidator(ethers.Wallet.createRandom().publicKey, { value: ethers.parseEther('0.8') }),
      );
      const secondValidatorId = await this.sfc.getValidatorID(secondValidator);
      await blockchainNode.handleTx(
        await this.sfc
          .connect(thirdValidator)
          .createValidator(ethers.Wallet.createRandom().publicKey, { value: ethers.parseEther('0.8') }),
      );
      const thirdValidatorId = await this.sfc.getValidatorID(thirdValidator);

      await this.sfc.connect(validator).delegate(validatorId, { value: ethers.parseEther('0.4') });
      await this.sfc.connect(delegator).delegate(validatorId, { value: ethers.parseEther('0.4') });
      await this.sfc.connect(secondDelegator).delegate(secondValidatorId, { value: ethers.parseEther('0.4') });

      await blockchainNode.sealEpoch(0);

      return {
        validator,
        validatorId,
        secondValidator,
        secondValidatorId,
        thirdValidator,
        thirdValidatorId,
        delegator,
        secondDelegator,
        blockchainNode,
      };
    };

    beforeEach(async function () {
      return Object.assign(this, await loadFixture(validatorsFixture.bind(this)));
    });

    it('Should succeed and return claimed Rewards until Epoch', async function () {
      await this.constants.updateBaseRewardPerSecond(1);
      await this.blockchainNode.sealEpoch(60 * 60 * 24);
      await this.blockchainNode.sealEpoch(60 * 60 * 24);
      expect(await this.sfc.stashedRewardsUntilEpoch(this.delegator, this.validatorId)).to.equal(0);
      await this.sfc.connect(this.delegator).claimRewards(this.validatorId);
      expect(await this.sfc.stashedRewardsUntilEpoch(this.delegator, this.validatorId)).to.equal(
        await this.sfc.currentSealedEpoch(),
      );
    });

    it('Should succeed and check pending rewards of delegators', async function () {
      await this.constants.updateBaseRewardPerSecond(1);
      expect(await this.sfc.pendingRewards(this.validator, this.validatorId)).to.equal(0);
      expect(await this.sfc.pendingRewards(this.delegator, this.validatorId)).to.equal(0);
      await this.blockchainNode.sealEpoch(60 * 60 * 24);
      expect(await this.sfc.pendingRewards(this.validator, this.validatorId)).to.equal(6_966);
      expect(await this.sfc.pendingRewards(this.delegator, this.validatorId)).to.equal(2_754);
    });

    it('Should succeed and check if pending rewards have been increased after sealing epoch', async function () {
      await this.constants.updateBaseRewardPerSecond(1);
      await this.blockchainNode.sealEpoch(60 * 60 * 24);
      expect(await this.sfc.pendingRewards(this.validator, this.validatorId)).to.equal(6_966);
      expect(await this.sfc.pendingRewards(this.delegator, this.validatorId)).to.equal(2_754);
      await this.blockchainNode.sealEpoch(60 * 60 * 24);
      expect(await this.sfc.pendingRewards(this.validator, this.validatorId)).to.equal(13_932);
      expect(await this.sfc.pendingRewards(this.delegator, this.validatorId)).to.equal(5_508);
    });

    it('Should succeed and increase balances after claiming rewards', async function () {
      await this.constants.updateBaseRewardPerSecond(100_000_000_000_000);
      await this.blockchainNode.sealEpoch(0);
      await this.blockchainNode.sealEpoch(60 * 60 * 24);
      const delegatorPendingRewards = await this.sfc.pendingRewards(this.delegator, 1);
      expect(delegatorPendingRewards).to.equal(ethers.parseEther('0.2754'));
      const delegatorBalance = await ethers.provider.getBalance(this.delegator.address);
      await this.sfc.connect(this.delegator).claimRewards(this.validatorId);
      const delegatorNewBalance = await ethers.provider.getBalance(this.delegator.address);
      expect(delegatorBalance + delegatorPendingRewards).to.be.above(delegatorNewBalance);
      expect(delegatorBalance + delegatorPendingRewards).to.be.below(delegatorNewBalance + ethers.parseEther('0.01'));
    });

    it('Should succeed and increase stake after restaking rewards', async function () {
      await this.constants.updateBaseRewardPerSecond(1);
      await this.blockchainNode.sealEpoch(0);
      await this.blockchainNode.sealEpoch(60 * 60 * 24);
      const delegatorPendingRewards = await this.sfc.pendingRewards(this.delegator, 1);
      expect(delegatorPendingRewards).to.equal(2754);
      const delegatorStake = await this.sfc.getStake(this.delegator, this.validatorId);
      const delegatorLockupInfo = await this.sfc.getLockupInfo(this.delegator, this.validatorId);
      await this.sfc.connect(this.delegator).restakeRewards(this.validatorId);
      const delegatorNewStake = await this.sfc.getStake(this.delegator, this.validatorId);
      const delegatorNewLockupInfo = await this.sfc.getLockupInfo(this.delegator, this.validatorId);
      expect(delegatorNewStake).to.equal(delegatorStake + delegatorPendingRewards);
      expect(delegatorNewLockupInfo.lockedStake).to.equal(delegatorLockupInfo.lockedStake);
    });

    it('Should succeed and increase locked stake after restaking rewards', async function () {
      await this.sfc.connect(this.validator).lockStake(1, 86_400 * 219 + 10, ethers.parseEther('0.2'));
      await this.sfc.connect(this.delegator).lockStake(1, 86_400 * 219, ethers.parseEther('0.2'));

      await this.constants.updateBaseRewardPerSecond(1);
      await this.blockchainNode.sealEpoch(0);
      await this.blockchainNode.sealEpoch(60 * 60 * 24);

      const firstDelegatorPendingRewards = await this.sfc.pendingRewards(this.delegator, 1);
      expect(firstDelegatorPendingRewards).to.equal(4681);
      const firstDelegatorPendingLockupRewards = 3304n;
      const firstDelegatorStake = await this.sfc.getStake(this.delegator, 1);
      const firstDelegatorLockupInfo = await this.sfc.getLockupInfo(this.delegator, 1);

      await this.sfc.connect(this.delegator).restakeRewards(this.validatorId);

      const delegatorStake = await this.sfc.getStake(this.delegator, this.validatorId);
      const delegatorLockupInfo = await this.sfc.getLockupInfo(this.delegator, this.validatorId);
      expect(delegatorStake).to.equal(firstDelegatorStake + firstDelegatorPendingRewards);
      expect(delegatorLockupInfo.lockedStake).to.equal(
        firstDelegatorLockupInfo.lockedStake + firstDelegatorPendingLockupRewards,
      );
    });

    it('Should succeed and return stashed rewards', async function () {
      await this.constants.updateBaseRewardPerSecond(1);

      await this.blockchainNode.sealEpoch(0);
      await this.blockchainNode.sealEpoch(60 * 60 * 24);

      expect(await this.sfc.rewardsStash(this.delegator, this.validatorId)).to.equal(0);

      await this.sfc.stashRewards(this.delegator, this.validatorId);
      expect(await this.sfc.rewardsStash(this.delegator, this.validatorId)).to.equal(2_754);
    });

    it('Should succeed andupdate the validator on node', async function () {
      await this.constants.updateOfflinePenaltyThresholdTime(10000);
      await this.constants.updateOfflinePenaltyThresholdBlocksNum(500);

      expect(await this.constants.offlinePenaltyThresholdTime()).to.equal(10_000);
      expect(await this.constants.offlinePenaltyThresholdBlocksNum()).to.equal(500);
    });

    it('Should revert when deactivating validator if not Node', async function () {
      await this.sfc.disableNonNodeCalls();
      await expect(this.sfc.deactivateValidator(this.validatorId, 0)).to.be.revertedWithCustomError(
        this.sfc,
        'NotDriverAuth',
      );
    });

    it('Should succeed and seal epochs', async function () {
      const validatorsMetrics: Map<number, ValidatorMetrics> = new Map();
      const validatorIDs = await this.sfc.lastValidatorID();

      for (let i = 0; i < validatorIDs; i++) {
        validatorsMetrics.set(i, {
          offlineTime: 0,
          offlineBlocks: 0,
          uptime: 24 * 60 * 60,
          originatedTxsFee: ethers.parseEther('100'),
        });
      }

      const allValidators = [];
      const offlineTimes = [];
      const offlineBlocks = [];
      const uptimes = [];
      const originatedTxsFees = [];
      for (let i = 0; i < validatorIDs; i++) {
        allValidators.push(i + 1);
        offlineTimes.push(validatorsMetrics.get(i)!.offlineTime);
        offlineBlocks.push(validatorsMetrics.get(i)!.offlineBlocks);
        uptimes.push(validatorsMetrics.get(i)!.uptime);
        originatedTxsFees.push(validatorsMetrics.get(i)!.originatedTxsFee);
      }

      await this.sfc.advanceTime(24 * 60 * 60);
      await this.sfc.sealEpoch(offlineTimes, offlineBlocks, uptimes, originatedTxsFees, 0);
      await this.sfc.sealEpochValidators(allValidators);
    });

    it('Should succeed and seal epoch on Validators', async function () {
      const validatorsMetrics: Map<number, ValidatorMetrics> = new Map();
      const validatorIDs = await this.sfc.lastValidatorID();

      for (let i = 0; i < validatorIDs; i++) {
        validatorsMetrics.set(i, {
          offlineTime: 0,
          offlineBlocks: 0,
          uptime: 24 * 60 * 60,
          originatedTxsFee: ethers.parseEther('0'),
        });
      }

      const allValidators = [];
      const offlineTimes = [];
      const offlineBlocks = [];
      const uptimes = [];
      const originatedTxsFees = [];
      for (let i = 0; i < validatorIDs; i++) {
        allValidators.push(i + 1);
        offlineTimes.push(validatorsMetrics.get(i)!.offlineTime);
        offlineBlocks.push(validatorsMetrics.get(i)!.offlineBlocks);
        uptimes.push(validatorsMetrics.get(i)!.uptime);
        originatedTxsFees.push(validatorsMetrics.get(i)!.originatedTxsFee);
      }

      await this.sfc.advanceTime(24 * 60 * 60);
      await this.sfc.sealEpoch(offlineTimes, offlineBlocks, uptimes, originatedTxsFees, 0);
      await this.sfc.sealEpochValidators(allValidators);
    });

    describe('Stake lockup', () => {
      beforeEach('lock stakes', async function () {
        // Lock 75% of stake for 60% of a maximum lockup period
        // Should receive (0.3 * 0.25 + (0.3 + 0.7 * 0.6) * 0.75) / 0.3 = 2.05 times more rewards
        await this.sfc.connect(this.validator).lockStake(this.validatorId, 86_400 * 219, ethers.parseEther('0.6'));
        // Lock 25% of stake for 20% of a maximum lockup period
        // Should receive (0.3 * 0.75 + (0.3 + 0.7 * 0.2) * 0.25) / 0.3 = 1.1166 times more rewards
        await this.sfc.connect(this.delegator).lockStake(this.validatorId, 86_400 * 73, ethers.parseEther('0.1'));
      });

      // note: copied from the non-lockup tests
      it('Should succeed and check pending rewards of delegators', async function () {
        await this.constants.updateBaseRewardPerSecond(1);

        expect(await this.sfc.pendingRewards(this.validator, this.validatorId)).to.equal(0);
        expect(await this.sfc.pendingRewards(this.delegator, this.validatorId)).to.equal(0);

        await this.blockchainNode.sealEpoch(60 * 60 * 24);

        expect(await this.sfc.pendingRewards(this.validator, this.validatorId)).to.equal(14_279);
        expect(await this.sfc.pendingRewards(this.delegator, this.validatorId)).to.equal(3_074);
      });

      // note: copied from the non-lockup tests
      it('Should succeed and check if pending rewards have been increased after sealing epoch', async function () {
        await this.constants.updateBaseRewardPerSecond(1);

        await this.blockchainNode.sealEpoch(60 * 60 * 24);
        expect(await this.sfc.pendingRewards(this.validator, this.validatorId)).to.equal(14_279);
        expect(await this.sfc.pendingRewards(this.delegator, this.validatorId)).to.equal(3_074);

        await this.blockchainNode.sealEpoch(60 * 60 * 24);
        expect(await this.sfc.pendingRewards(this.validator, this.validatorId)).to.equal(28_558);
        expect(await this.sfc.pendingRewards(this.delegator, this.validatorId)).to.equal(6_150);
      });

      // note: copied from the non-lockup tests
      it('Should succeed and increase balances after claiming rewards', async function () {
        await this.constants.updateBaseRewardPerSecond(1);

        await this.blockchainNode.sealEpoch(0);
        await this.blockchainNode.sealEpoch(60 * 60 * 24);

        const firstDelegatorPendingRewards = await this.sfc.pendingRewards(this.delegator, this.validatorId);
        const firstDelegatorBalance = await ethers.provider.getBalance(this.delegator);

        await this.sfc.connect(this.delegator).claimRewards(this.validatorId);

        expect(firstDelegatorBalance + firstDelegatorPendingRewards).to.be.above(
          await ethers.provider.getBalance(this.delegator),
        );
      });

      // note: copied from the non-lockup tests
      it('Should succeed and return stashed rewards', async function () {
        await this.constants.updateBaseRewardPerSecond(1);

        await this.blockchainNode.sealEpoch(0);
        await this.blockchainNode.sealEpoch(60 * 60 * 24);

        expect(await this.sfc.rewardsStash(this.delegator, this.validatorId)).to.equal(0);

        await this.sfc.stashRewards(this.delegator, this.validatorId);
        expect(await this.sfc.rewardsStash(this.delegator, 1)).to.equal(3_074);
      });

      it('Should succeed and return pending rewards after unlocking and re-locking', async function () {
        await this.constants.updateBaseRewardPerSecond(1);

        for (let i = 0; i < 2; i++) {
          const epoch = await this.sfc.currentSealedEpoch();
          // delegator 1 is still locked
          // delegator 1 should receive more rewards than delegator 2
          // validator 1 should receive more rewards than validator 2
          await this.blockchainNode.sealEpoch(86_400 * 73);

          expect(await this.sfc.pendingRewards(this.delegator, 1)).to.equal(224496);
          expect(await this.sfc.pendingRewards(this.secondDelegator, 2)).to.equal(201042);
          expect(await this.sfc.pendingRewards(this.validator, 1)).to.equal(1042461);
          expect(await this.sfc.pendingRewards(this.secondValidator, 2)).to.equal(508518);

          expect(await this.sfc.highestLockupEpoch(this.delegator, 1)).to.equal(epoch + 1n);
          expect(await this.sfc.highestLockupEpoch(this.secondDelegator, 2)).to.equal(0);
          expect(await this.sfc.highestLockupEpoch(this.validator, 1)).to.equal(epoch + 1n);
          expect(await this.sfc.highestLockupEpoch(this.secondValidator, 2)).to.equal(0);

          // delegator 1 isn't locked already
          // delegator 1 should receive the same reward as delegator 2
          // validator 1 should receive more rewards than validator 2
          await this.blockchainNode.sealEpoch(86_400);

          expect(await this.sfc.pendingRewards(this.delegator, 1)).to.equal(224496 + 2754);
          expect(await this.sfc.pendingRewards(this.secondDelegator, 2)).to.equal(201042 + 2754);
          expect(await this.sfc.pendingRewards(this.validator, 1)).to.equal(1042461 + 14279);
          expect(await this.sfc.pendingRewards(this.secondValidator, 2)).to.equal(508518 + 6966);
          expect(await this.sfc.highestLockupEpoch(this.delegator, 1)).to.equal(epoch + 1n);
          expect(await this.sfc.highestLockupEpoch(this.validator, 1)).to.equal(epoch + 2n);

          // validator 1 is still locked
          // delegator 1 should receive the same reward as delegator 2
          // validator 1 should receive more rewards than validator 2
          await this.blockchainNode.sealEpoch(86_400 * 145);

          expect(await this.sfc.pendingRewards(this.delegator, 1)).to.equal(224496 + 2754 + 399330);
          expect(await this.sfc.pendingRewards(this.secondDelegator, 2)).to.equal(201042 + 2754 + 399330);
          expect(await this.sfc.pendingRewards(this.validator, 1)).to.equal(1042461 + 14279 + 2070643);
          expect(await this.sfc.pendingRewards(this.secondValidator, 2)).to.equal(508518 + 6966 + 1010070);
          expect(await this.sfc.highestLockupEpoch(this.delegator, 1)).to.equal(epoch + 1n);
          expect(await this.sfc.highestLockupEpoch(this.validator, 1)).to.equal(epoch + 3n);

          // validator 1 isn't locked already
          // delegator 1 should receive the same reward as delegator 2
          // validator 1 should receive the same reward as validator 2
          await this.blockchainNode.sealEpoch(86_400);

          expect(await this.sfc.pendingRewards(this.delegator, 1)).to.equal(224496 + 2754 + 399330 + 2754);
          expect(await this.sfc.pendingRewards(this.secondDelegator, 2)).to.equal(201042 + 2754 + 399330 + 2754);
          expect(await this.sfc.pendingRewards(this.validator, 1)).to.equal(1042461 + 14279 + 2070643 + 6966);
          expect(await this.sfc.pendingRewards(this.secondValidator, 2)).to.equal(508518 + 6966 + 1010070 + 6966);
          expect(await this.sfc.highestLockupEpoch(this.delegator, 1)).to.equal(epoch + 1n);
          expect(await this.sfc.highestLockupEpoch(this.validator, 1)).to.equal(epoch + 3n);

          // re-lock both validator and delegator
          await this.sfc.connect(this.validator).lockStake(this.validatorId, 86400 * 219, ethers.parseEther('0.6'));
          await this.sfc.connect(this.delegator).lockStake(this.validatorId, 86400 * 73, ethers.parseEther('0.1'));
          // // check rewards didn't change after re-locking
          expect(await this.sfc.pendingRewards(this.delegator, 1)).to.equal(224496 + 2754 + 399330 + 2754);
          expect(await this.sfc.pendingRewards(this.secondDelegator, 2)).to.equal(201042 + 2754 + 399330 + 2754);
          expect(await this.sfc.pendingRewards(this.validator, 1)).to.equal(1042461 + 14279 + 2070643 + 6966);
          expect(await this.sfc.pendingRewards(this.secondValidator, 2)).to.equal(508518 + 6966 + 1010070 + 6966);
          expect(await this.sfc.highestLockupEpoch(this.delegator, 1)).to.equal(0);
          expect(await this.sfc.highestLockupEpoch(this.validator, 1)).to.equal(0);
          // claim rewards to reset pending rewards
          await this.sfc.connect(this.delegator).claimRewards(1);
          await this.sfc.connect(this.secondDelegator).claimRewards(2);
          await this.sfc.connect(this.validator).claimRewards(1);
          await this.sfc.connect(this.secondValidator).claimRewards(2);
        }
      });
    });

    describe('NodeDriver', () => {
      it('Should revert when calling setGenesisValidator if not NodeDriver', async function () {
        const key = ethers.Wallet.createRandom().publicKey;
        await expect(
          this.nodeDriverAuth.setGenesisValidator(
            this.delegator,
            1,
            key,
            1 << 3,
            await this.sfc.currentEpoch(),
            Date.now(),
            0,
            0,
          ),
        ).to.be.revertedWithCustomError(this.nodeDriverAuth, 'NotDriver');
      });

      it('Should revert when calling setGenesisDelegation if not NodeDriver', async function () {
        await expect(
          this.nodeDriverAuth.setGenesisDelegation(this.delegator, 1, 100, 0, 0, 0, 0, 0, 1000),
        ).to.be.revertedWithCustomError(this.nodeDriverAuth, 'NotDriver');
      });

      it('Should revert when calling deactivateValidator if not NodeDriver', async function () {
        await expect(this.nodeDriverAuth.deactivateValidator(1, 0)).to.be.revertedWithCustomError(
          this.nodeDriverAuth,
          'NotDriver',
        );
      });

      it('Should revert when calling deactivateValidator with wrong status', async function () {
        await expect(this.sfc.deactivateValidator(1, 0)).to.be.revertedWithCustomError(
          this.sfc,
          'WrongValidatorStatus',
        );
      });

      it('Should succeed and deactivate validator', async function () {
        await this.sfc.deactivateValidator(1, 1);
      });

      it('Should revert when calling sealEpoch if not NodeDriver', async function () {
        await expect(this.nodeDriverAuth.sealEpochValidators([1])).to.be.revertedWithCustomError(
          this.nodeDriverAuth,
          'NotDriver',
        );
      });

      it('Should revert when calling sealEpoch if not NodeDriver', async function () {
        const validatorsMetrics: Map<number, ValidatorMetrics> = new Map();
        const validatorIDs = await this.sfc.lastValidatorID();

        for (let i = 0; i < validatorIDs; i++) {
          validatorsMetrics.set(i, {
            offlineTime: 0,
            offlineBlocks: 0,
            uptime: 24 * 60 * 60,
            originatedTxsFee: ethers.parseEther('0'),
          });
        }

        const allValidators = [];
        const offlineTimes = [];
        const offlineBlocks = [];
        const uptimes = [];
        const originatedTxsFees = [];
        for (let i = 0; i < validatorIDs; i++) {
          allValidators.push(i + 1);
          offlineTimes.push(validatorsMetrics.get(i)!.offlineTime);
          offlineBlocks.push(validatorsMetrics.get(i)!.offlineBlocks);
          uptimes.push(validatorsMetrics.get(i)!.uptime);
          originatedTxsFees.push(validatorsMetrics.get(i)!.originatedTxsFee);
        }

        await this.sfc.advanceTime(24 * 60 * 60);
        await expect(
          this.nodeDriverAuth.sealEpoch(offlineTimes, offlineBlocks, uptimes, originatedTxsFees, 0),
        ).to.be.revertedWithCustomError(this.nodeDriverAuth, 'NotDriver');
      });
    });

    describe('Epoch getters', () => {
      it('Should succeed and return EpochvalidatorIds', async function () {
        const currentSealedEpoch = await this.sfc.currentSealedEpoch();
        await this.sfc.getEpochValidatorIDs(currentSealedEpoch);
      });

      it('Should succeed and return the epoch received stake', async function () {
        const currentSealedEpoch = await this.sfc.currentSealedEpoch();
        await this.sfc.getEpochReceivedStake(currentSealedEpoch, 1);
      });

      it('Should succeed and return the epoch accumulated reward per token', async function () {
        const currentSealedEpoch = await this.sfc.currentSealedEpoch();
        await this.sfc.getEpochAccumulatedRewardPerToken(currentSealedEpoch, 1);
      });

      it('Should succeed and return the epoch accumulated uptime', async function () {
        const currentSealedEpoch = await this.sfc.currentSealedEpoch();
        await this.sfc.getEpochAccumulatedUptime(currentSealedEpoch, 1);
      });

      it('Should succeed and return epoch accumulated originated txs fee', async function () {
        const currentSealedEpoch = await this.sfc.currentSealedEpoch();
        await this.sfc.getEpochAccumulatedOriginatedTxsFee(currentSealedEpoch, 1);
      });

      it('Should succeed and return the epoch offline time', async function () {
        const currentSealedEpoch = await this.sfc.currentSealedEpoch();
        await this.sfc.getEpochOfflineTime(currentSealedEpoch, 1);
      });

      it('Should succeed and return  epoch offline blocks', async function () {
        const currentSealedEpoch = await this.sfc.currentSealedEpoch();
        await this.sfc.getEpochOfflineBlocks(currentSealedEpoch, 1);
      });
    });

    describe('Epoch getters', () => {
      it('Should revert when trying to unlock stake if not lockedup', async function () {
        await expect(this.sfc.unlockStake(1, 10)).to.be.revertedWithCustomError(this.sfc, 'NotLockedUp');
      });

      it('Should revert when trying to unlock stake if amount is 0', async function () {
        await expect(this.sfc.unlockStake(1, 0)).to.be.revertedWithCustomError(this.sfc, 'ZeroAmount');
      });

      it('Should succeed and return slashed status', async function () {
        expect(await this.sfc.isSlashed(1)).to.equal(false);
      });

      it('Should revert when delegating to an unexisting validator', async function () {
        await expect(this.sfc.delegate(4)).to.be.revertedWithCustomError(this.sfc, 'ValidatorNotExists');
      });

      it('Should revert when delegating to an unexisting validator (2)', async function () {
        await expect(this.sfc.delegate(4, { value: ethers.parseEther('1') })).to.be.revertedWithCustomError(
          this.sfc,
          'ValidatorNotExists',
        );
      });
    });

    describe('SFC Rewards getters / Features', () => {
      it('Should succeed and return stashed rewards', async function () {
        expect(await this.sfc.rewardsStash(this.delegator, 1)).to.equal(0);
      });

      it('Should succeed and return locked stake', async function () {
        expect(await this.sfc.getLockedStake(this.delegator, 1)).to.equal(0);
      });

      it('Should succeed and return locked stake (2)', async function () {
        expect(await this.sfc.getLockedStake(this.delegator, 2)).to.equal(0);
      });
    });

    it('Should succeed and setGenesisDelegation Validator', async function () {
      await this.sfc.setGenesisDelegation(this.delegator, this.validatorId, ethers.parseEther('1'), 0, 0, 0, 0, 0, 100);
      // delegator has already delegated 0.4 in fixture
      expect(await this.sfc.getStake(this.delegator, this.validatorId)).to.equal(ethers.parseEther('1.4'));
    });
  });

  describe('Rewards calculation', () => {
    const validatorsFixture = async function (this: Context) {
      const [validator, testValidator, firstDelegator, secondDelegator, thirdDelegator, account1, account2, account3] =
        await ethers.getSigners();
      const blockchainNode = new BlockchainNode(this.sfc);

      await this.sfc.rebaseTime();
      await this.sfc.enableNonNodeCalls();
      await this.constants.updateBaseRewardPerSecond(ethers.parseEther('1'));

      await blockchainNode.handleTx(
        await this.sfc
          .connect(account1)
          .createValidator(ethers.Wallet.createRandom().publicKey, { value: ethers.parseEther('10') }),
      );
      await blockchainNode.handleTx(
        await this.sfc
          .connect(account2)
          .createValidator(ethers.Wallet.createRandom().publicKey, { value: ethers.parseEther('5') }),
      );
      await blockchainNode.handleTx(
        await this.sfc
          .connect(account3)
          .createValidator(ethers.Wallet.createRandom().publicKey, { value: ethers.parseEther('1') }),
      );

      const validatorId = await this.sfc.getValidatorID(account1);
      const secondValidatorId = await this.sfc.getValidatorID(account2);
      const thirdValidatorId = await this.sfc.getValidatorID(account3);

      return {
        validator,
        validatorId,
        testValidator,
        secondValidatorId,
        firstDelegator,
        thirdValidatorId,
        secondDelegator,
        thirdDelegator,
        blockchainNode,
        account1,
        account2,
        account3,
      };
    };

    beforeEach(async function () {
      return Object.assign(this, await loadFixture(validatorsFixture.bind(this)));
    });

    describe('Rewards calculation without lockup', () => {
      beforeEach(async function () {
        await this.sfc
          .connect(this.account3)
          .lockStake(this.thirdValidatorId, 60 * 60 * 24 * 364, ethers.parseEther('1'));
        await this.blockchainNode.sealEpoch(0);
      });

      it('Should succeed and calculation of validators rewards should be equal to 30%', async function () {
        await this.blockchainNode.sealEpoch(1_000);

        const rewardAcc1 = (await this.sfc.pendingRewards(this.account1, this.validatorId)).toString().slice(0, -16);
        const rewardAcc2 = (await this.sfc.pendingRewards(this.account2, this.secondValidatorId))
          .toString()
          .slice(0, -16);
        const rewardAcc3 = (await this.sfc.pendingRewards(this.account3, this.thirdValidatorId))
          .toString()
          .slice(0, -16);

        expect(parseInt(rewardAcc1) + parseInt(rewardAcc2) + parseInt(rewardAcc3)).to.equal(34_363);
      });

      it('Should revert when withdrawing nonexistent request', async function () {
        await expect(this.sfc.withdraw(this.validatorId, 0)).to.be.revertedWithCustomError(
          this.sfc,
          'RequestNotExists',
        );
      });

      it('Should revert when undelegating 0 amount', async function () {
        await this.blockchainNode.sealEpoch(1_000);
        await expect(this.sfc.undelegate(this.validatorId, 0, 0)).to.be.revertedWithCustomError(this.sfc, 'ZeroAmount');
      });

      it('Should revert when undelegating if not enough unlocked stake', async function () {
        await this.blockchainNode.sealEpoch(1_000);
        await expect(this.sfc.undelegate(this.validatorId, 0, 10)).to.be.revertedWithCustomError(
          this.sfc,
          'NotEnoughUnlockedStake',
        );
      });

      it('Should revert when unlocking if not enough unlocked stake', async function () {
        await this.blockchainNode.sealEpoch(1_000);
        await this.sfc.connect(this.thirdDelegator).delegate(this.validatorId, { value: ethers.parseEther('1') });
        await expect(
          this.sfc.connect(this.thirdDelegator).unlockStake(this.validatorId, 10),
        ).to.be.revertedWithCustomError(this.sfc, 'NotLockedUp');
      });

      it('Should succeed and return the unlocked stake', async function () {
        await this.blockchainNode.sealEpoch(1_000);
        await this.sfc.connect(this.thirdDelegator).delegate(this.thirdValidatorId, { value: ethers.parseEther('1') });
        const unlockedStake = await this.sfc.getUnlockedStake(this.thirdDelegator, this.thirdValidatorId);
        expect(unlockedStake).to.equal(ethers.parseEther('1'));
      });

      it('Should revert when when claiming and zero rewards', async function () {
        await this.blockchainNode.sealEpoch(1_000);
        await this.sfc.connect(this.thirdDelegator).delegate(this.thirdValidatorId, { value: ethers.parseEther('10') });
        await this.blockchainNode.sealEpoch(1_000);
        await expect(
          this.sfc.connect(this.thirdDelegator).claimRewards(this.validatorId),
        ).to.be.revertedWithCustomError(this.sfc, 'ZeroRewards');
      });
    });

    describe('Rewards calculation with lockup', () => {
      beforeEach(async function () {
        await this.sfc
          .connect(this.account3)
          .lockStake(this.thirdValidatorId, 60 * 60 * 24 * (365 - 31), ethers.parseEther('1'));
        await this.blockchainNode.sealEpoch(0);
      });

      it('Should revert when when locking 0 amount', async function () {
        await this.blockchainNode.sealEpoch(1_000);
        await expect(
          this.sfc
            .connect(this.thirdDelegator)
            .lockStake(this.validatorId, 2 * 60 * 60 * 24 * 365, ethers.parseEther('0')),
        ).to.be.revertedWithCustomError(this.sfc, 'ZeroAmount');
      });

      it('Should revert when locking for more than a year', async function () {
        await this.blockchainNode.sealEpoch(1_000);
        await this.sfc.connect(this.thirdDelegator).delegate(this.thirdValidatorId, { value: ethers.parseEther('10') });
        await expect(
          this.sfc
            .connect(this.thirdDelegator)
            .lockStake(this.thirdValidatorId, 2 * 60 * 60 * 24 * 365, ethers.parseEther('1')),
        ).to.be.revertedWithCustomError(this.sfc, 'IncorrectDuration');
      });

      it('Should revert when locking for more than a validator lockup period', async function () {
        await this.blockchainNode.sealEpoch(1_000);
        await this.sfc.connect(this.thirdDelegator).delegate(this.thirdValidatorId, { value: ethers.parseEther('10') });
        await expect(
          this.sfc
            .connect(this.thirdDelegator)
            .lockStake(this.thirdValidatorId, 60 * 60 * 24 * 364, ethers.parseEther('1')),
        ).to.be.revertedWithCustomError(this.sfc, 'ValidatorLockupTooShort');
        await this.sfc
          .connect(this.thirdDelegator)
          .lockStake(this.thirdValidatorId, 60 * 60 * 24 * 363, ethers.parseEther('1'));
      });

      it('Should succeed and lock for 1 month', async function () {
        await this.blockchainNode.sealEpoch(1_000);
        await this.sfc.connect(this.thirdDelegator).delegate(this.thirdValidatorId, { value: ethers.parseEther('10') });
        await this.sfc
          .connect(this.thirdDelegator)
          .lockStake(this.thirdValidatorId, 60 * 60 * 24 * 14, ethers.parseEther('1'));
        await this.blockchainNode.sealEpoch(60 * 60 * 24 * 14);
      });

      it('Should revert when unlocking not locked FTM', async function () {
        await this.blockchainNode.sealEpoch(1_000);
        await this.sfc.connect(this.thirdDelegator).delegate(this.thirdValidatorId, { value: ethers.parseEther('10') });
        await this.sfc
          .connect(this.thirdDelegator)
          .lockStake(this.thirdValidatorId, 60 * 60 * 24 * 14, ethers.parseEther('1'));
        await this.blockchainNode.sealEpoch(60 * 60 * 24 * 14);
        await expect(
          this.sfc.unlockStake(this.thirdValidatorId, ethers.parseEther('10')),
        ).to.be.revertedWithCustomError(this.sfc, 'NotLockedUp');
      });

      it('Should revert when unlocking more than locked stake', async function () {
        await this.blockchainNode.sealEpoch(1_000);
        await this.sfc.connect(this.thirdDelegator).delegate(this.thirdValidatorId, { value: ethers.parseEther('10') });
        await this.sfc
          .connect(this.thirdDelegator)
          .lockStake(this.thirdValidatorId, 60 * 60 * 24 * 14, ethers.parseEther('1'));
        await this.blockchainNode.sealEpoch(60 * 60 * 24 * 14);
        await expect(
          this.sfc.connect(this.thirdDelegator).unlockStake(this.thirdValidatorId, ethers.parseEther('10')),
        ).to.be.revertedWithCustomError(this.sfc, 'NotEnoughLockedStake');
      });

      it('Should succeed and scale unlocking penalty', async function () {
        await this.blockchainNode.sealEpoch(1_000);
        await this.sfc.connect(this.thirdDelegator).delegate(this.thirdValidatorId, { value: ethers.parseEther('10') });
        await this.sfc
          .connect(this.thirdDelegator)
          .lockStake(this.thirdValidatorId, 60 * 60 * 24 * 60, ethers.parseEther('1'));
        await this.blockchainNode.sealEpoch(1);

        expect(
          await this.sfc
            .connect(this.thirdDelegator)
            .unlockStake.staticCall(this.thirdValidatorId, ethers.parseEther('1')),
        ).to.equal(ethers.parseEther('0.001280160336239103'));
        expect(
          await this.sfc
            .connect(this.thirdDelegator)
            .unlockStake.staticCall(this.thirdValidatorId, ethers.parseEther('0.5')),
        ).to.equal(ethers.parseEther('0.000640080168119551'));
        expect(
          await this.sfc
            .connect(this.thirdDelegator)
            .unlockStake.staticCall(this.thirdValidatorId, ethers.parseEther('0.01')),
        ).to.equal(ethers.parseEther('0.000012801603362390'));

        await this.sfc.connect(this.thirdDelegator).unlockStake(this.thirdValidatorId, ethers.parseEther('0.5'));

        await expect(
          this.sfc.connect(this.thirdDelegator).unlockStake(this.thirdValidatorId, ethers.parseEther('0.51')),
        ).to.be.revertedWithCustomError(this.sfc, 'NotEnoughLockedStake');
        expect(
          await this.sfc
            .connect(this.thirdDelegator)
            .unlockStake.staticCall(this.thirdValidatorId, ethers.parseEther('0.5')),
        ).to.equal(ethers.parseEther('0.000640080168119552'));
        expect(
          await this.sfc
            .connect(this.thirdDelegator)
            .unlockStake.staticCall(this.thirdValidatorId, ethers.parseEther('0.01')),
        ).to.equal(ethers.parseEther('0.000012801603362390'));
      });

      it('Should succeed and scale unlocking penalty with limiting to reasonable value', async function () {
        await this.blockchainNode.sealEpoch(1_000);
        await this.sfc.connect(this.thirdDelegator).delegate(this.thirdValidatorId, { value: ethers.parseEther('10') });
        await this.sfc
          .connect(this.thirdDelegator)
          .lockStake(this.thirdValidatorId, 60 * 60 * 24 * 14, ethers.parseEther('1'));
        await this.blockchainNode.sealEpoch(100);

        expect(
          await this.sfc
            .connect(this.thirdDelegator)
            .unlockStake.staticCall(this.thirdValidatorId, ethers.parseEther('1')),
        ).to.equal(ethers.parseEther('0.000380540964546690'));
        expect(
          await this.sfc
            .connect(this.thirdDelegator)
            .unlockStake.staticCall(this.thirdValidatorId, ethers.parseEther('0.5')),
        ).to.equal(ethers.parseEther('0.000190270482273344'));
        expect(
          await this.sfc
            .connect(this.thirdDelegator)
            .unlockStake.staticCall(this.thirdValidatorId, ethers.parseEther('0.01')),
        ).to.equal(ethers.parseEther('0.000003805409645466'));

        await this.sfc.connect(this.thirdDelegator).unlockStake(this.thirdValidatorId, ethers.parseEther('0.5'));

        await expect(
          this.sfc.connect(this.thirdDelegator).unlockStake(this.thirdValidatorId, ethers.parseEther('0.51')),
        ).to.be.revertedWithCustomError(this.sfc, 'NotEnoughLockedStake');
        expect(
          await this.sfc
            .connect(this.thirdDelegator)
            .unlockStake.staticCall(this.thirdValidatorId, ethers.parseEther('0.5')),
        ).to.equal(ethers.parseEther('0.000190270482273344'));
        expect(
          await this.sfc
            .connect(this.thirdDelegator)
            .unlockStake.staticCall(this.thirdValidatorId, ethers.parseEther('0.01')),
        ).to.equal(ethers.parseEther('0.000003805409645466'));

        await this.sfc
          .connect(this.thirdDelegator)
          .relockStake(this.thirdValidatorId, 60 * 60 * 24 * 14, ethers.parseEther('1'));

        await expect(
          this.sfc.connect(this.thirdDelegator).unlockStake(this.thirdValidatorId, ethers.parseEther('1.51')),
        ).to.be.revertedWithCustomError(this.sfc, 'NotEnoughLockedStake');
        expect(
          await this.sfc
            .connect(this.thirdDelegator)
            .unlockStake.staticCall(this.thirdValidatorId, ethers.parseEther('1.5')),
        ).to.equal(ethers.parseEther('0.000190270482273344'));
        expect(
          await this.sfc
            .connect(this.thirdDelegator)
            .unlockStake.staticCall(this.thirdValidatorId, ethers.parseEther('0.5')),
        ).to.equal(ethers.parseEther('0.000063423494091114')); // 3 times smaller
      });

      it('Should succeed and unlock after period ended and stash rewards', async function () {
        await this.blockchainNode.sealEpoch(1_000);
        await this.sfc.connect(this.thirdDelegator).delegate(this.thirdValidatorId, { value: ethers.parseEther('10') });

        let unlockedStake = await this.sfc
          .connect(this.thirdDelegator)
          .getUnlockedStake(this.thirdDelegator, this.thirdValidatorId);
        let pendingRewards = await this.sfc
          .connect(this.thirdDelegator)
          .pendingRewards(this.thirdDelegator, this.thirdValidatorId);

        expect(unlockedStake).to.equal(ethers.parseEther('10'));
        expect(pendingRewards).to.equal(0);
        await this.sfc
          .connect(this.thirdDelegator)
          .lockStake(this.thirdValidatorId, 60 * 60 * 24 * 14, ethers.parseEther('1'));

        unlockedStake = await this.sfc.getUnlockedStake(this.thirdDelegator, this.thirdValidatorId);
        pendingRewards = await this.sfc.pendingRewards(this.thirdDelegator, this.thirdValidatorId);

        expect(unlockedStake).to.equal(ethers.parseEther('9'));
        expect(pendingRewards).to.equal(0);
        await this.blockchainNode.sealEpoch(60 * 60 * 24 * 14);

        unlockedStake = await this.sfc
          .connect(this.thirdDelegator)
          .getUnlockedStake(this.thirdDelegator, this.thirdValidatorId);
        pendingRewards = await this.sfc
          .connect(this.thirdDelegator)
          .pendingRewards(this.thirdDelegator, this.thirdValidatorId);

        expect(unlockedStake).to.equal(ethers.parseEther('9'));
        expect(pendingRewards).to.equal(ethers.parseEther('17682.303362391033619905'));

        await this.blockchainNode.sealEpoch(60 * 60 * 24 * 14);
        pendingRewards = await this.sfc.pendingRewards(this.thirdDelegator, this.thirdValidatorId);

        unlockedStake = await this.sfc.getUnlockedStake(this.thirdDelegator, this.thirdValidatorId);
        expect(unlockedStake).to.equal(ethers.parseEther('10'));
        expect(pendingRewards).to.equal(ethers.parseEther('136316.149516237187466057'));

        await this.sfc.connect(this.thirdDelegator).stashRewards(this.thirdDelegator, this.thirdValidatorId);
      });

      it('Should revert when updating slashing refund ratio', async function () {
        await this.blockchainNode.sealEpoch(1_000);

        await expect(
          this.sfc.connect(this.validator).updateSlashingRefundRatio(this.thirdValidatorId, 1),
        ).to.be.revertedWithCustomError(this.sfc, 'ValidatorNotSlashed');

        await this.blockchainNode.sealEpoch(60 * 60 * 24 * 14);
      });

      it('Should revert when syncing if validator does not exist', async function () {
        await expect(this.sfc._syncValidator(33, false)).to.be.revertedWithCustomError(this.sfc, 'ValidatorNotExists');
      });
    });
  });

  // calc rewards in ether with a round down
  const calcRewardsJs = (
    lockDuration: number,
    lockedAmount: number,
    stakedAmount: number,
    totalStakedAmount: number,
    rawReward: number,
  ) => {
    const rewards = { extra: 0, base: 0, unlocked: 0, penalty: 0, sum: 0 };
    // note: calculation for commission isn't accurate
    const commissionFull = Math.floor((rawReward * 15) / 100);
    // let commissionFullLocked = Math.floor(commissionFull * lockedAmount / stakedAmount);
    // let commissionFullUnlocked = commissionFull - commissionFullLocked;
    // if (isValidator) {
    //     rewards.extra = Math.floor(commissionFullLocked * 0.7 * lockDuration / (86400 * 365));
    //     rewards.base = Math.floor(commissionFullLocked * 0.3);
    //     rewards.unlocked = Math.floor(commissionFullUnlocked * 0.3);
    // }
    const delegatorRewards = rawReward - commissionFull;
    const accRate = Math.floor(delegatorRewards / totalStakedAmount);
    rewards.extra += Math.floor((accRate * lockedAmount * 0.7 * lockDuration) / (86400 * 365));
    rewards.base += Math.floor(accRate * lockedAmount * 0.3);
    rewards.unlocked += Math.floor(accRate * (stakedAmount - lockedAmount) * 0.3);
    rewards.penalty = Math.floor(rewards.extra + rewards.base / 2);
    rewards.sum = rewards.extra + rewards.base + rewards.unlocked;
    return rewards;
  };

  describe('Test fluid relocks', () => {
    const validatorsFixture = async function (this: Context) {
      const [
        validator,
        secondValidator,
        firstDelegator,
        secondDelegator,
        thirdDelegator,
        account1,
        account2,
        account3,
      ] = await ethers.getSigners();
      const blockchainNode = new BlockchainNode(this.sfc);

      await this.sfc.rebaseTime();
      await this.sfc.enableNonNodeCalls();
      await this.constants.updateBaseRewardPerSecond(1);

      await blockchainNode.handleTx(
        await this.sfc
          .connect(validator)
          .createValidator(ethers.Wallet.createRandom().publicKey, { value: ethers.parseEther('10') }),
      );
      const validatorId = await this.sfc.getValidatorID(validator);

      await this.sfc.connect(firstDelegator).delegate(validatorId, { value: ethers.parseEther('10') });
      await this.sfc.connect(validator).lockStake(validatorId, 60 * 60 * 24 * 365, ethers.parseEther('5'));

      await blockchainNode.sealEpoch(0);

      return {
        validator,
        validatorId,
        secondValidator,
        firstDelegator,
        secondDelegator,
        thirdDelegator,
        blockchainNode,
        account1,
        account2,
        account3,
      };
    };

    beforeEach(async function () {
      return Object.assign(this, await loadFixture(validatorsFixture.bind(this)));
    });

    // orig lock    T1 -------------t1----> T2
    // relock       T3---------------------T2------>T3
    it('Should succeed and re-lock happy path, lock, re-lock, no premature unlocks', async function () {
      await this.blockchainNode.sealEpoch(60 * 60 * 24);
      const rewardBeforeLock = calcRewardsJs(0, 0, 10, 20, 86400);

      await this.sfc
        .connect(this.firstDelegator)
        .lockStake(this.validatorId, 60 * 60 * 24 * 14, ethers.parseEther('5'));

      await this.blockchainNode.sealEpoch(60 * 60 * 24 * 7);
      const rewardBeforeRelock = calcRewardsJs(86400 * 14, 5, 10, 20, 86400 * 7);
      await this.sfc
        .connect(this.firstDelegator)
        .relockStake(this.validatorId, 60 * 60 * 24 * 14, ethers.parseEther('5'));

      await this.blockchainNode.sealEpoch(60 * 60 * 24 * 14);
      const rewardAfterUnlock = calcRewardsJs(86400 * 14, 10, 10, 20, 86400 * 14);

      const expectedReward = rewardBeforeLock.sum + rewardBeforeRelock.sum + rewardAfterUnlock.sum;
      expect(await this.sfc.pendingRewards(this.firstDelegator, this.validatorId)).to.equal(expectedReward);
    });

    it('Should succeed and re-lock happy path, lock, re-lock no amount added, no premature unlocks', async function () {
      await this.blockchainNode.sealEpoch(60 * 60 * 24);
      const rewardBeforeLock = calcRewardsJs(0, 0, 10, 20, 86400);

      await this.sfc
        .connect(this.firstDelegator)
        .lockStake(this.validatorId, 60 * 60 * 24 * 14, ethers.parseEther('5'));

      await this.blockchainNode.sealEpoch(60 * 60 * 24 * 7);
      const rewardBeforeRelock = calcRewardsJs(86400 * 14, 5, 10, 20, 86400 * 7);
      await this.sfc
        .connect(this.firstDelegator)
        .relockStake(this.validatorId, 60 * 60 * 24 * 14, ethers.parseEther('0'));

      await this.blockchainNode.sealEpoch(60 * 60 * 24 * 14);
      const rewardAfterUnlock = calcRewardsJs(86400 * 14, 5, 10, 20, 86400 * 14);

      const expectedReward = rewardBeforeLock.sum + rewardBeforeRelock.sum + rewardAfterUnlock.sum;
      expect(await this.sfc.pendingRewards(this.firstDelegator, this.validatorId)).to.equal(expectedReward);
    });

    it('Should succeed and re-lock happy path, lock, re-lock, unlock at T1', async function () {
      await this.blockchainNode.sealEpoch(60 * 60 * 24);
      const rewardBeforeLock = calcRewardsJs(0, 0, 10, 20, 86400);

      await this.sfc
        .connect(this.firstDelegator)
        .lockStake(this.validatorId, 60 * 60 * 24 * 14, ethers.parseEther('5'));

      await this.blockchainNode.sealEpoch(60 * 60 * 24 * 7);
      const rewardBeforeRelock = calcRewardsJs(86400 * 14, 5, 10, 20, 86400 * 7);
      await this.sfc
        .connect(this.firstDelegator)
        .relockStake(this.validatorId, 60 * 60 * 24 * 14, ethers.parseEther('5'));

      await this.blockchainNode.sealEpoch(60 * 60 * 24 * 2);
      const rewardAfterUnlock = calcRewardsJs(86400 * 14, 10, 10, 20, 86400 * 2);
      const expectedPenalty = rewardBeforeRelock.penalty + rewardAfterUnlock.penalty;

      expect(
        await this.sfc.connect(this.firstDelegator).unlockStake.staticCall(this.validatorId, ethers.parseEther('10')),
      ).to.equal(expectedPenalty);

      const expectedReward = rewardBeforeLock.sum + rewardBeforeRelock.sum + rewardAfterUnlock.sum;
      expect(await this.sfc.pendingRewards(this.firstDelegator, this.validatorId)).to.equal(expectedReward);
    });

    it('Should succeed and re-lock happy path, lock, re-lock, unlock at T2', async function () {
      await this.blockchainNode.sealEpoch(60 * 60 * 24);
      const rewardBeforeLock = calcRewardsJs(0, 0, 10, 20, 86400);

      await this.sfc
        .connect(this.firstDelegator)
        .lockStake(this.validatorId, 60 * 60 * 24 * 14, ethers.parseEther('5'));

      await this.blockchainNode.sealEpoch(60 * 60 * 24 * 7);
      const rewardBeforeRelock = calcRewardsJs(86400 * 14, 5, 10, 20, 86400 * 7);
      await this.sfc
        .connect(this.firstDelegator)
        .relockStake(this.validatorId, 60 * 60 * 24 * 14, ethers.parseEther('5'));

      await this.blockchainNode.sealEpoch(60 * 60 * 24 * 12);
      const rewardAfterUnlock = calcRewardsJs(86400 * 14, 10, 10, 20, 86400 * 12);
      const expectedPenalty = rewardAfterUnlock.penalty;
      expect(
        await this.sfc.connect(this.firstDelegator).unlockStake.staticCall(this.validatorId, ethers.parseEther('10')),
      ).to.equal(expectedPenalty);

      const expectedReward = rewardBeforeLock.sum + rewardBeforeRelock.sum + rewardAfterUnlock.sum;
      expect(await this.sfc.pendingRewards(this.firstDelegator, this.validatorId)).to.equal(expectedReward);
    });

    it('Should revert when re-locking if re-lock limit is exceeded', async function () {
      await this.blockchainNode.sealEpoch(60 * 60 * 24);

      await this.sfc
        .connect(this.firstDelegator)
        .lockStake(this.validatorId, 60 * 60 * 24 * 20, ethers.parseEther('5'));
      await this.blockchainNode.sealEpoch(60 * 60 * 24);

      // 1
      await this.sfc
        .connect(this.firstDelegator)
        .relockStake(this.validatorId, 60 * 60 * 24 * 20, ethers.parseEther('0'));
      await this.blockchainNode.sealEpoch(60 * 60 * 24);

      // 2
      await this.sfc
        .connect(this.firstDelegator)
        .relockStake(this.validatorId, 60 * 60 * 24 * 20, ethers.parseEther('0'));
      await this.blockchainNode.sealEpoch(60 * 60 * 24);

      // 3
      await this.sfc
        .connect(this.firstDelegator)
        .relockStake(this.validatorId, 60 * 60 * 24 * 20, ethers.parseEther('0'));
      await this.blockchainNode.sealEpoch(60 * 60 * 24);
      await expect(
        this.sfc.connect(this.firstDelegator).relockStake(this.validatorId, 60 * 60 * 24 * 20, ethers.parseEther('0')),
      ).to.be.revertedWithCustomError(this.sfc, 'TooFrequentReLocks');

      // 4
      await this.sfc.advanceTime(60 * 60 * 24 * 14);
      await this.sfc
        .connect(this.firstDelegator)
        .relockStake(this.validatorId, 60 * 60 * 24 * 20, ethers.parseEther('0'));
      await this.blockchainNode.sealEpoch(60 * 60 * 24);
      await expect(
        this.sfc.connect(this.firstDelegator).relockStake(this.validatorId, 60 * 60 * 24 * 20, ethers.parseEther('0')),
      ).to.be.revertedWithCustomError(this.sfc, 'TooFrequentReLocks');

      for (let i = 5; i <= 40; i++) {
        // 5-40
        await this.sfc.advanceTime(60 * 60 * 24 * 14);
        await this.sfc
          .connect(this.firstDelegator)
          .relockStake(this.validatorId, 60 * 60 * 24 * 20, ethers.parseEther('0'));
        await this.blockchainNode.sealEpoch(60 * 60 * 24);
        // ensure validator's lockup period doesn't end too early
        await this.sfc
          .connect(this.validator)
          .relockStake(this.validatorId, 60 * 60 * 24 * 365, ethers.parseEther('0'));
      }
    });

    it('Should succeed and partial unlock at T1, unlock amount < original lock amount', async function () {
      await this.blockchainNode.sealEpoch(60 * 60 * 24);
      const rewardBeforeLock = calcRewardsJs(0, 0, 10, 20, 86400);

      await this.sfc
        .connect(this.firstDelegator)
        .lockStake(this.validatorId, 60 * 60 * 24 * 14, ethers.parseEther('5'));

      await this.blockchainNode.sealEpoch(60 * 60 * 24 * 7);
      const rewardBeforeRelock = calcRewardsJs(86400 * 14, 5, 10, 20, 86400 * 7);
      await this.sfc
        .connect(this.firstDelegator)
        .relockStake(this.validatorId, 60 * 60 * 24 * 14, ethers.parseEther('5'));

      await this.blockchainNode.sealEpoch(60 * 60 * 24 * 2);
      const rewardAfterUnlock = calcRewardsJs(86400 * 14, 10, 10, 20, 86400 * 2);
      const penaltyShareBeforeRelock = Math.floor((rewardBeforeRelock.penalty * 2) / 10);
      const penaltyShareAfterUnlock = Math.floor((rewardAfterUnlock.penalty * 2) / 10);
      let expectedPenalty = penaltyShareBeforeRelock + penaltyShareAfterUnlock;

      expect(
        await this.sfc.connect(this.firstDelegator).unlockStake.staticCall(this.validatorId, ethers.parseEther('2')),
      ).to.equal(expectedPenalty);
      let expectedReward = rewardBeforeLock.sum + rewardBeforeRelock.sum + rewardAfterUnlock.sum;
      expect(await this.sfc.pendingRewards(this.firstDelegator, this.validatorId)).to.equal(expectedReward);

      await this.sfc.advanceTime(60 * 60 * 24 * 5 - 1);

      expect(
        await this.sfc.connect(this.firstDelegator).unlockStake.staticCall(this.validatorId, ethers.parseEther('2')),
      ).to.equal(expectedPenalty);
      expectedReward = rewardBeforeLock.sum + rewardBeforeRelock.sum + rewardAfterUnlock.sum;
      expect(await this.sfc.pendingRewards(this.firstDelegator, this.validatorId)).to.equal(expectedReward);

      await this.sfc.advanceTime(2);

      expectedPenalty = penaltyShareAfterUnlock;
      expect(
        await this.sfc.connect(this.firstDelegator).unlockStake.staticCall(this.validatorId, ethers.parseEther('2')),
      ).to.equal(expectedPenalty);
      expectedReward = rewardBeforeLock.sum + rewardBeforeRelock.sum + rewardAfterUnlock.sum;
      expect(await this.sfc.pendingRewards(this.firstDelegator, this.validatorId)).to.equal(expectedReward);
    });
  });
});
