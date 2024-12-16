import { ethers, upgrades } from 'hardhat';
import { expect } from 'chai';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { IEVMWriter, UnitTestConstantsManager, UnitTestNetworkInitializer } from '../typechain-types';
import { beforeEach, Context } from 'mocha';
import { BlockchainNode, ValidatorMetrics } from './helpers/BlockchainNode';

describe('SFC', () => {
  const fixture = async () => {
    const [owner, user] = await ethers.getSigners();
    const sfc = await upgrades.deployProxy(await ethers.getContractFactory('UnitTestSFC'), {
      kind: 'uups',
      initializer: false,
    });
    const nodeDriver = await upgrades.deployProxy(await ethers.getContractFactory('NodeDriver'), {
      kind: 'uups',
      initializer: false,
    });
    const nodeDriverAuth = await upgrades.deployProxy(await ethers.getContractFactory('NodeDriverAuth'), {
      kind: 'uups',
      initializer: false,
    });

    const evmWriter: IEVMWriter = await ethers.deployContract('StubEvmWriter');
    const initializer: UnitTestNetworkInitializer = await ethers.deployContract('UnitTestNetworkInitializer');

    await initializer.initializeAll(0, ethers.parseEther('100000'), sfc, nodeDriverAuth, nodeDriver, evmWriter, owner);
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

  describe('Burn native tokens', () => {
    it('Should revert when no amount sent', async function () {
      await expect(this.sfc.connect(this.user).burnNativeTokens()).to.be.revertedWithCustomError(
        this.sfc,
        'ZeroAmount',
      );
    });

    it('Should succeed and burn native tokens', async function () {
      const amount = ethers.parseEther('1.5');
      const totalSupply = await this.sfc.totalSupply();
      const tx = await this.sfc.connect(this.user).burnNativeTokens({ value: amount });
      await expect(tx).to.emit(this.sfc, 'BurntNativeTokens').withArgs(amount);
      expect(await this.sfc.totalSupply()).to.equal(totalSupply - amount);
      await expect(tx).to.changeEtherBalance(this.sfc, 0);
      await expect(tx).to.changeEtherBalance(this.user, -amount);
      await expect(tx).to.changeEtherBalance(ethers.ZeroAddress, amount);
    });
  });

  describe('Genesis validator', () => {
    beforeEach(async function () {
      const validator = ethers.Wallet.createRandom();
      await this.sfc.enableNonNodeCalls();
      await this.sfc.setGenesisValidator(validator.address, 1, validator.publicKey, Date.now());
      await this.sfc.deactivateValidator(1, 1 << 3);
      await this.sfc.disableNonNodeCalls();
    });

    it('Should succeed and set genesis validator with bad status', async function () {
      await this.sfc._syncValidator(1, false);
    });

    it('Should revert when sealEpoch not called by node', async function () {
      await expect(this.sfc.sealEpoch([1], [1], [1], [1])).to.be.revertedWithCustomError(this.sfc, 'NotDriverAuth');
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

    it('Should succeed and return period of time that stake is locked', async function () {
      expect(await this.constants.withdrawalPeriodTime()).to.equal(60 * 60 * 24 * 7);
    });

    it('Should succeed and return number of epochs that stake is locked', async function () {
      expect(await this.constants.withdrawalPeriodEpochs()).to.equal(3);
    });

    it('Should succeed and return version of the current implementation', async function () {
      expect(await this.sfc.version()).to.equal('0x040000');
    });
  });

  describe('Issue tokens', () => {
    it('Should revert when not owner', async function () {
      await expect(this.sfc.connect(this.user).issueTokens(ethers.parseEther('100'))).to.be.revertedWithCustomError(
        this.sfc,
        'OwnableUnauthorizedAccount',
      );
    });

    it('Should revert when recipient is not set', async function () {
      await expect(this.sfc.connect(this.owner).issueTokens(ethers.parseEther('100'))).to.be.revertedWithCustomError(
        this.sfc,
        'ZeroAddress',
      );
    });

    it('Should succeed and issue tokens', async function () {
      await this.constants.updateIssuedTokensRecipient(this.user);
      const supply = await this.sfc.totalSupply();
      const amount = ethers.parseEther('100');
      await this.sfc.connect(this.owner).issueTokens(amount);
      expect(await this.sfc.totalSupply()).to.equal(supply + amount);
    });
  });

  describe('Create validator', () => {
    const validatorsFixture = async () => {
      const validatorPubKey =
        '0xc000a2941866e485442aa6b17d67d77f8a6c4580bb556894cc1618473eff1e18203d8cce50b563cf4c75e408886079b8f067069442ed52e2ac9e556baa3f8fcc525f';
      const secondValidatorPubKey =
        '0xc000a2941866e485442aa6b17d67d77f8a6c4580bb556894cc1618473eff1e18203d8cce50b563cf4c75e408886079b8f067069442ed52e2ac9e556baa3f8fcc5251';
      const [validator, secondValidator] = await ethers.getSigners();
      return {
        validator,
        validatorPubKey,
        secondValidator,
        secondValidatorPubKey,
      };
    };

    beforeEach(async function () {
      Object.assign(this, await loadFixture(validatorsFixture));
    });

    it('Should succeed and create a validator and return its id', async function () {
      await this.sfc.connect(this.validator).createValidator(this.validatorPubKey, { value: ethers.parseEther('0.4') });
      expect(await this.sfc.lastValidatorID()).to.equal(1);
    });

    it('Should revert when insufficient self-stake to create a validator', async function () {
      await expect(
        this.sfc.connect(this.validator).createValidator(this.validatorPubKey, { value: ethers.parseEther('0.1') }),
      ).to.be.revertedWithCustomError(this.sfc, 'InsufficientSelfStake');
    });

    it('Should revert when public key is empty while creating a validator', async function () {
      await expect(
        this.sfc.connect(this.validator).createValidator('0x', { value: ethers.parseEther('0.4') }),
      ).to.be.revertedWithCustomError(this.sfc, 'MalformedPubkey');
    });

    it('Should succeed and create two validators and return id of last validator', async function () {
      expect(await this.sfc.lastValidatorID()).to.equal(0);
      expect(await this.sfc.getValidatorID(this.validator)).to.equal(0);
      expect(await this.sfc.getValidatorID(this.secondValidator)).to.equal(0);

      await this.sfc.connect(this.validator).createValidator(this.validatorPubKey, { value: ethers.parseEther('0.4') });
      expect(await this.sfc.getValidatorID(this.validator)).to.equal(1);
      expect(await this.sfc.lastValidatorID()).to.equal(1);

      await this.sfc
        .connect(this.secondValidator)
        .createValidator(this.secondValidatorPubKey, { value: ethers.parseEther('0.5') });
      expect(await this.sfc.getValidatorID(this.secondValidator)).to.equal(2);
      expect(await this.sfc.lastValidatorID()).to.equal(2);
    });

    it('Should succeed and return delegation', async function () {
      await this.sfc
        .connect(this.secondValidator)
        .createValidator(this.secondValidatorPubKey, { value: ethers.parseEther('0.5') });
      await this.sfc.connect(this.secondValidator).delegate(1, { value: ethers.parseEther('0.1') });
    });

    it('Should revert when staking to non-existing validator', async function () {
      await expect(
        this.sfc.connect(this.secondValidator).delegate(1, { value: ethers.parseEther('0.1') }),
      ).to.be.revertedWithCustomError(this.sfc, 'ValidatorNotExists');
    });

    it('Should succeed and stake with different delegators', async function () {
      await this.sfc.connect(this.validator).createValidator(this.validatorPubKey, { value: ethers.parseEther('0.5') });
      await this.sfc.connect(this.validator).delegate(1, { value: ethers.parseEther('0.1') });

      await this.sfc
        .connect(this.secondValidator)
        .createValidator(this.secondValidatorPubKey, { value: ethers.parseEther('0.5') });
      await this.sfc.connect(this.secondValidator).delegate(2, { value: ethers.parseEther('0.3') });
      await this.sfc.connect(this.validator).delegate(1, { value: ethers.parseEther('0.2') });
    });

    it('Should succeed and return the amount of delegated for each Delegator', async function () {
      await this.sfc.connect(this.validator).createValidator(this.validatorPubKey, { value: ethers.parseEther('0.5') });
      await this.sfc.connect(this.validator).delegate(1, { value: ethers.parseEther('0.1') });
      expect(await this.sfc.getStake(this.validator, await this.sfc.getValidatorID(this.validator))).to.equal(
        ethers.parseEther('0.6'),
      );

      await this.sfc
        .connect(this.secondValidator)
        .createValidator(this.secondValidatorPubKey, { value: ethers.parseEther('0.5') });
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
      await this.sfc.connect(this.validator).createValidator(this.validatorPubKey, { value: ethers.parseEther('0.5') });

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
        this.sfc.setGenesisValidator(validator, 1, validator.publicKey, Date.now()),
      ).to.be.revertedWithCustomError(this.sfc, 'NotDriverAuth');
    });

    it('Should revert when setGenesisDelegation is not called not node', async function () {
      const delegator = ethers.Wallet.createRandom();
      await expect(this.sfc.setGenesisDelegation(delegator, 1, 100)).to.be.revertedWithCustomError(
        this.sfc,
        'NotDriverAuth',
      );
    });
  });

  describe('Validator', () => {
    const validatorsFixture = async function (this: Context) {
      const [validator, delegator, secondDelegator, thirdDelegator] = await ethers.getSigners();
      const validatorPubKey =
        '0xc000a2941866e485442aa6b17d67d77f8a6c4580bb556894cc1618473eff1e18203d8cce50b563cf4c75e408886079b8f067069442ed52e2ac9e556baa3f8fcc525f';

      await this.sfc.connect(validator).createValidator(validatorPubKey, { value: ethers.parseEther('10') });
      await this.sfc.connect(delegator).delegate(1, { value: ethers.parseEther('11') });

      await this.sfc.connect(secondDelegator).delegate(1, { value: ethers.parseEther('8') });
      await this.sfc.connect(thirdDelegator).delegate(1, { value: ethers.parseEther('8') });

      const validatorStruct = await this.sfc.getValidator(1);

      return {
        validator,
        validatorPubKey,
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
        await this.sfc.sealEpoch([100, 101, 102], [100, 101, 102], [100, 101, 102], [100, 101, 102]);
        expect(await this.sfc.currentEpoch.call()).to.equal(2);
        expect(await this.sfc.currentSealedEpoch()).to.equal(1);
        for (let i = 0; i < 4; i++) {
          await this.sfc.sealEpoch([100, 101, 102], [100, 101, 102], [100, 101, 102], [100, 101, 102]);
        }
        expect(await this.sfc.currentEpoch.call()).to.equal(6);
        expect(await this.sfc.currentSealedEpoch()).to.equal(5);
      });

      it('Should succeed and return endBlock', async function () {
        const epochNumber = await this.sfc.currentEpoch();
        await this.sfc.enableNonNodeCalls();
        await this.sfc.sealEpoch([100, 101, 102], [100, 101, 102], [100, 101, 102], [100, 101, 102]);
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
      const pubkey =
        '0xc0040220af695ae100c370c7acff4f57e5a0c507abbbc8ac6cc2ae0ce3a81747e0cd3c6892233faae1af5d982d05b1c13a0ad4449685f0b5a6138b301cc5263f8316';
      const secondPubkey =
        '0xc00499a876465bc626061bb2f0326df1a223c14e3bcdc3fff3deb0f95f316b9d586b03f00bbc2349be3d7908de8626cfd8f7fd6f73bff49df1299f44b6855562c33d';
      await this.sfc.enableNonNodeCalls();

      expect(await this.sfc.lastValidatorID()).to.equal(0);

      await expect(
        this.sfc.connect(validator).createValidator(pubkey, { value: ethers.parseEther('0.1') }),
      ).to.be.revertedWithCustomError(this.sfc, 'InsufficientSelfStake');

      await node.handleTx(
        await this.sfc.connect(validator).createValidator(pubkey, { value: ethers.parseEther('0.3175') }),
      );

      await expect(
        this.sfc.connect(validator).createValidator(secondPubkey, { value: ethers.parseEther('0.5') }),
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

      expect(await this.sfc.pubkeyAddressToValidatorID('0x65Db23D0c4FA8Ec58151a30E54e6a6046c97cD10')).to.equal(
        firstValidatorID,
      );
      expect(await this.sfc.pubkeyAddressToValidatorID('0x1AA3196683eE97Adf5B398875828E322a34E8085')).to.equal(
        secondValidatorID,
      );

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
      const pubkey =
        '0xc000a2941866e485442aa6b17d67d77f8a6c4580bb556894cc1618473eff1e18203d8cce50b563cf4c75e408886079b8f067069442ed52e2ac9e556baa3f8fcc525f';
      const secondPubkey =
        '0xc000a2941866e485442aa6b17d67d77f8a6c4580bb556894cc1618473eff1e18203d8cce50b563cf4c75e408886079b8f067069442ed52e2ac9e556baa3f8fcc5251';
      const thirdPubkey =
        '0xc000a2941866e485442aa6b17d67d77f8a6c4580bb556894cc1618473eff1e18203d8cce50b563cf4c75e408886079b8f067069442ed52e2ac9e556baa3f8fcc5252';

      await this.sfc.enableNonNodeCalls();

      await node.handleTx(
        await this.sfc.connect(validator).createValidator(pubkey, { value: ethers.parseEther('0.3175') }),
      );

      await node.handleTx(
        await this.sfc.connect(secondValidator).createValidator(secondPubkey, { value: ethers.parseEther('0.6825') }),
      );

      await node.sealEpoch(100);

      const firstValidatorID = await this.sfc.getValidatorID(validator);
      const secondValidatorID = await this.sfc.getValidatorID(secondValidator);
      expect(firstValidatorID).to.equal(1);
      expect(secondValidatorID).to.equal(2);

      await node.handleTx(await this.sfc.connect(validator).delegate(1, { value: ethers.parseEther('0.1') }));

      await node.handleTx(
        await this.sfc.connect(thirdValidator).createValidator(thirdPubkey, { value: ethers.parseEther('0.4') }),
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
  });

  describe('Staking / Sealed Epoch functions', () => {
    const validatorsFixture = async function (this: Context) {
      const [validator, secondValidator, thirdValidator, delegator, secondDelegator] = await ethers.getSigners();
      const pubkey =
        '0xc000a2941866e485442aa6b17d67d77f8a6c4580bb556894cc1618473eff1e18203d8cce50b563cf4c75e408886079b8f067069442ed52e2ac9e556baa3f8fcc525f';
      const secondPubkey =
        '0xc000a2941866e485442aa6b17d67d77f8a6c4580bb556894cc1618473eff1e18203d8cce50b563cf4c75e408886079b8f067069442ed52e2ac9e556baa3f8fcc5251';
      const thirdPubkey =
        '0xc000a2941866e485442aa6b17d67d77f8a6c4580bb556894cc1618473eff1e18203d8cce50b563cf4c75e408886079b8f067069442ed52e2ac9e556baa3f8fcc5252';
      const blockchainNode = new BlockchainNode(this.sfc);

      await this.sfc.rebaseTime();
      await this.sfc.enableNonNodeCalls();

      await blockchainNode.handleTx(
        await this.sfc.connect(validator).createValidator(pubkey, { value: ethers.parseEther('0.4') }),
      );
      const validatorId = await this.sfc.getValidatorID(validator);
      await blockchainNode.handleTx(
        await this.sfc.connect(secondValidator).createValidator(secondPubkey, { value: ethers.parseEther('0.8') }),
      );
      const secondValidatorId = await this.sfc.getValidatorID(secondValidator);
      await blockchainNode.handleTx(
        await this.sfc.connect(thirdValidator).createValidator(thirdPubkey, { value: ethers.parseEther('0.8') }),
      );
      const thirdValidatorId = await this.sfc.getValidatorID(thirdValidator);

      await this.sfc.connect(validator).delegate(validatorId, { value: ethers.parseEther('0.4') });
      await this.sfc.connect(delegator).delegate(validatorId, { value: ethers.parseEther('0.4') });
      await this.sfc.connect(secondDelegator).delegate(secondValidatorId, { value: ethers.parseEther('0.4') });

      await blockchainNode.sealEpoch(0);

      return {
        validator,
        pubkey,
        validatorId,
        secondValidator,
        secondPubkey,
        secondValidatorId,
        thirdValidator,
        thirdPubkey,
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
      expect(await this.sfc.pendingRewards(this.validator, this.validatorId)).to.equal(23_220);
      expect(await this.sfc.pendingRewards(this.delegator, this.validatorId)).to.equal(9_180);
    });

    it('Should succeed and check if pending rewards have been increased after sealing epoch', async function () {
      await this.constants.updateBaseRewardPerSecond(1);
      await this.blockchainNode.sealEpoch(60 * 60 * 24);
      expect(await this.sfc.pendingRewards(this.validator, this.validatorId)).to.equal(23_220);
      expect(await this.sfc.pendingRewards(this.delegator, this.validatorId)).to.equal(9_180);
      await this.blockchainNode.sealEpoch(60 * 60 * 24);
      expect(await this.sfc.pendingRewards(this.validator, this.validatorId)).to.equal(46_440);
      expect(await this.sfc.pendingRewards(this.delegator, this.validatorId)).to.equal(18_360);
    });

    it('Should succeed and increase balances after claiming rewards', async function () {
      await this.constants.updateBaseRewardPerSecond(100_000_000_000_000);
      await this.blockchainNode.sealEpoch(0);
      await this.blockchainNode.sealEpoch(60 * 60 * 24);
      const delegatorPendingRewards = await this.sfc.pendingRewards(this.delegator, 1);
      expect(delegatorPendingRewards).to.equal(ethers.parseEther('0.918'));
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
      expect(delegatorPendingRewards).to.equal(9_180);
      const delegatorStake = await this.sfc.getStake(this.delegator, this.validatorId);
      await this.sfc.connect(this.delegator).restakeRewards(this.validatorId);
      const delegatorNewStake = await this.sfc.getStake(this.delegator, this.validatorId);
      expect(delegatorNewStake).to.equal(delegatorStake + delegatorPendingRewards);
    });

    it('Should succeed and return stashed rewards', async function () {
      await this.constants.updateBaseRewardPerSecond(1);

      await this.blockchainNode.sealEpoch(0);
      await this.blockchainNode.sealEpoch(60 * 60 * 24);

      expect(await this.sfc.rewardsStash(this.delegator, this.validatorId)).to.equal(0);

      await this.sfc.stashRewards(this.delegator, this.validatorId);
      expect(await this.sfc.rewardsStash(this.delegator, this.validatorId)).to.equal(9_180);
    });

    it('Should succeed and update the validator on node', async function () {
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
      const validatorsMetrics: Map<bigint, ValidatorMetrics> = new Map();
      const validatorIDs = await this.sfc.lastValidatorID();

      for (let i = 1n; i <= validatorIDs; i++) {
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
      for (let i = 1n; i <= validatorIDs; i++) {
        allValidators.push(i);
        offlineTimes.push(validatorsMetrics.get(i)!.offlineTime);
        offlineBlocks.push(validatorsMetrics.get(i)!.offlineBlocks);
        uptimes.push(validatorsMetrics.get(i)!.uptime);
        originatedTxsFees.push(validatorsMetrics.get(i)!.originatedTxsFee);
      }

      await this.sfc.advanceTime(24 * 60 * 60);
      await this.sfc.sealEpoch(offlineTimes, offlineBlocks, uptimes, originatedTxsFees);
      await this.sfc.sealEpochValidators(allValidators);
    });

    describe('Treasury', () => {
      it('Should revert when treasury is not set', async function () {
        await expect(this.sfc.resolveTreasuryFees()).to.be.revertedWithCustomError(this.sfc, 'TreasuryNotSet');
      });

      it('Should revert when no unresolved treasury fees are available', async function () {
        const treasury = ethers.Wallet.createRandom();
        await this.sfc.connect(this.owner).updateTreasuryAddress(treasury);
        await expect(this.sfc.resolveTreasuryFees()).to.be.revertedWithCustomError(
          this.sfc,
          'NoUnresolvedTreasuryFees',
        );
      });

      it('Should succeed and resolve treasury fees', async function () {
        // set treasury as failing receiver to trigger treasury fee accumulation
        const failingReceiver = await ethers.deployContract('FailingReceiver');
        await this.sfc.connect(this.owner).updateTreasuryAddress(failingReceiver);

        // set validators metrics and their fees
        const validatorsMetrics: Map<bigint, ValidatorMetrics> = new Map();
        const validatorIDs = await this.sfc.lastValidatorID();
        for (let i = 1n; i <= validatorIDs; i++) {
          validatorsMetrics.set(i, {
            offlineTime: 0,
            offlineBlocks: 0,
            uptime: 24 * 60 * 60,
            originatedTxsFee: ethers.parseEther('100'),
          });
        }

        // seal epoch to trigger fees calculation and distribution
        await this.blockchainNode.sealEpoch(24 * 60 * 60, validatorsMetrics);

        const fees =
          (validatorIDs * ethers.parseEther('100') * (await this.constants.treasuryFeeShare())) / BigInt(1e18);
        expect(await this.sfc.unresolvedTreasuryFees()).to.equal(fees);

        // update treasury to a valid receiver
        const treasury = ethers.Wallet.createRandom();
        await this.sfc.connect(this.owner).updateTreasuryAddress(treasury);

        // set sfc some balance to cover treasury fees
        // the funds cannot be sent directly as it rejects any incoming transfers
        await ethers.provider.send('hardhat_setBalance', [
          await this.sfc.getAddress(),
          ethers.toBeHex(ethers.parseEther('1000')),
        ]);

        // resolve treasury fees
        const tx = await this.sfc.resolveTreasuryFees();
        await expect(tx).to.emit(this.sfc, 'TreasuryFeesResolved').withArgs(fees);
        await expect(tx).to.changeEtherBalance(treasury, fees);
        await expect(tx).to.changeEtherBalance(this.sfc, -fees);
        expect(await this.sfc.unresolvedTreasuryFees()).to.equal(0);
      });
    });

    it('Should succeed and seal epoch on Validators', async function () {
      const validatorsMetrics: Map<bigint, ValidatorMetrics> = new Map();
      const validatorIDs = await this.sfc.lastValidatorID();

      for (let i = 1n; i <= validatorIDs; i++) {
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
      for (let i = 1n; i <= validatorIDs; i++) {
        allValidators.push(i);
        offlineTimes.push(validatorsMetrics.get(i)!.offlineTime);
        offlineBlocks.push(validatorsMetrics.get(i)!.offlineBlocks);
        uptimes.push(validatorsMetrics.get(i)!.uptime);
        originatedTxsFees.push(validatorsMetrics.get(i)!.originatedTxsFee);
      }

      await this.sfc.advanceTime(24 * 60 * 60);
      await this.sfc.sealEpoch(offlineTimes, offlineBlocks, uptimes, originatedTxsFees);
      await this.sfc.sealEpochValidators(allValidators);
    });

    describe('NodeDriver', () => {
      it('Should revert when calling setGenesisValidator if not NodeDriver', async function () {
        const key = ethers.Wallet.createRandom().publicKey;
        await expect(
          this.nodeDriverAuth.setGenesisValidator(this.delegator, 1, key, Date.now()),
        ).to.be.revertedWithCustomError(this.nodeDriverAuth, 'NotDriver');
      });

      it('Should revert when calling setGenesisDelegation if not NodeDriver', async function () {
        await expect(this.nodeDriverAuth.setGenesisDelegation(this.delegator, 1, 100)).to.be.revertedWithCustomError(
          this.nodeDriverAuth,
          'NotDriver',
        );
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
          'NotDeactivatedStatus',
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
        const validatorsMetrics: Map<bigint, ValidatorMetrics> = new Map();
        const validatorIDs = await this.sfc.lastValidatorID();

        for (let i = 1n; i <= validatorIDs; i++) {
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
        for (let i = 1n; i <= validatorIDs; i++) {
          allValidators.push(i);
          offlineTimes.push(validatorsMetrics.get(i)!.offlineTime);
          offlineBlocks.push(validatorsMetrics.get(i)!.offlineBlocks);
          uptimes.push(validatorsMetrics.get(i)!.uptime);
          originatedTxsFees.push(validatorsMetrics.get(i)!.originatedTxsFee);
        }

        await this.sfc.advanceTime(24 * 60 * 60);
        await expect(
          this.nodeDriverAuth.sealEpoch(offlineTimes, offlineBlocks, uptimes, originatedTxsFees),
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
    });

    it('Should succeed and setGenesisDelegation Validator', async function () {
      await this.sfc.setGenesisDelegation(this.delegator, this.validatorId, ethers.parseEther('1'));
      // delegator has already delegated 0.4 in fixture
      expect(await this.sfc.getStake(this.delegator, this.validatorId)).to.equal(ethers.parseEther('1.4'));
    });
  });

  describe('Rewards calculation', () => {
    const validatorsFixture = async function (this: Context) {
      const [validator, testValidator, firstDelegator, secondDelegator, thirdDelegator, account1, account2, account3] =
        await ethers.getSigners();
      const pubkey =
        '0xc000a2941866e485442aa6b17d67d77f8a6c4580bb556894cc1618473eff1e18203d8cce50b563cf4c75e408886079b8f067069442ed52e2ac9e556baa3f8fcc525f';
      const secondPubkey =
        '0xc000a2941866e485442aa6b17d67d77f8a6c4580bb556894cc1618473eff1e18203d8cce50b563cf4c75e408886079b8f067069442ed52e2ac9e556baa3f8fcc5251';
      const thirdPubkey =
        '0xc000a2941866e485442aa6b17d67d77f8a6c4580bb556894cc1618473eff1e18203d8cce50b563cf4c75e408886079b8f067069442ed52e2ac9e556baa3f8fcc5252';
      const blockchainNode = new BlockchainNode(this.sfc);

      await this.sfc.rebaseTime();
      await this.sfc.enableNonNodeCalls();
      await this.constants.updateBaseRewardPerSecond(ethers.parseEther('1'));

      await blockchainNode.handleTx(
        await this.sfc.connect(account1).createValidator(pubkey, { value: ethers.parseEther('10') }),
      );
      await blockchainNode.handleTx(
        await this.sfc.connect(account2).createValidator(secondPubkey, { value: ethers.parseEther('5') }),
      );
      await blockchainNode.handleTx(
        await this.sfc.connect(account3).createValidator(thirdPubkey, { value: ethers.parseEther('1') }),
      );

      const validatorId = await this.sfc.getValidatorID(account1);
      const secondValidatorId = await this.sfc.getValidatorID(account2);
      const thirdValidatorId = await this.sfc.getValidatorID(account3);

      await blockchainNode.sealEpoch(0);

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
        pubkey,
        secondPubkey,
        thirdPubkey,
      };
    };

    beforeEach(async function () {
      return Object.assign(this, await loadFixture(validatorsFixture.bind(this)));
    });

    describe('Rewards calculation', () => {
      it('Should succeed and calculate validators rewards', async function () {
        await this.blockchainNode.sealEpoch(1_000);

        const rewardAcc1 = (await this.sfc.pendingRewards(this.account1, this.validatorId)).toString().slice(0, -16);
        const rewardAcc2 = (await this.sfc.pendingRewards(this.account2, this.secondValidatorId))
          .toString()
          .slice(0, -16);
        const rewardAcc3 = (await this.sfc.pendingRewards(this.account3, this.thirdValidatorId))
          .toString()
          .slice(0, -16);

        expect(parseInt(rewardAcc1) + parseInt(rewardAcc2) + parseInt(rewardAcc3)).to.equal(100_000);
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

      it('Should revert when when claiming and zero rewards', async function () {
        await this.blockchainNode.sealEpoch(1_000);
        await this.sfc.connect(this.thirdDelegator).delegate(this.thirdValidatorId, { value: ethers.parseEther('10') });
        await this.blockchainNode.sealEpoch(1_000);
        await expect(
          this.sfc.connect(this.thirdDelegator).claimRewards(this.validatorId),
        ).to.be.revertedWithCustomError(this.sfc, 'ZeroRewards');
      });
    });

    it('Should revert when updating slashing refund ratio', async function () {
      await this.blockchainNode.sealEpoch(1_000);
      await expect(this.sfc.connect(this.validator).updateSlashingRefundRatio(1, 1)).to.be.revertedWithCustomError(
        this.sfc,
        'ValidatorNotSlashed',
      );
    });

    it('Should revert when syncing if validator does not exist', async function () {
      await expect(this.sfc._syncValidator(33, false)).to.be.revertedWithCustomError(this.sfc, 'ValidatorNotExists');
    });
  });

  describe('Average uptime calculation', () => {
    const validatorsFixture = async function (this: Context) {
      const [validator] = await ethers.getSigners();
      const pubkey =
        '0xc000a2941866e485442aa6b17d67d77f8a6c4580bb556894cc1618473eff1e18203d8cce50b563cf4c75e408886079b8f067069442ed52e2ac9e556baa3f8fcc525f';
      const blockchainNode = new BlockchainNode(this.sfc);

      await this.sfc.rebaseTime();
      await this.sfc.enableNonNodeCalls();

      await blockchainNode.handleTx(
        await this.sfc.connect(validator).createValidator(pubkey, { value: ethers.parseEther('10') }),
      );

      const validatorId = await this.sfc.getValidatorID(validator);

      await blockchainNode.sealEpoch(0);

      return {
        validatorId,
        blockchainNode,
      };
    };

    beforeEach(async function () {
      return Object.assign(this, await loadFixture(validatorsFixture.bind(this)));
    });

    it('Should calculate uptime correctly', async function () {
      // validator online 100% of time in the first epoch => average 100%
      await this.blockchainNode.sealEpoch(
        100,
        new Map<bigint, ValidatorMetrics>([[this.validatorId, new ValidatorMetrics(0, 0, 100, 0n)]]),
      );
      expect(await this.sfc.getEpochAverageUptime(await this.sfc.currentSealedEpoch(), this.validatorId)).to.equal(
        1000000000000000000n,
      );

      // validator online 20% of time in the second epoch => average 60%
      await this.blockchainNode.sealEpoch(
        100,
        new Map<bigint, ValidatorMetrics>([[this.validatorId, new ValidatorMetrics(0, 0, 20, 0n)]]),
      );
      expect(await this.sfc.getEpochAverageUptime(await this.sfc.currentSealedEpoch(), this.validatorId)).to.equal(
        600000000000000000n,
      );

      // validator online 30% of time in the third epoch => average 50%
      await this.blockchainNode.sealEpoch(
        100,
        new Map<bigint, ValidatorMetrics>([[this.validatorId, new ValidatorMetrics(0, 0, 30, 0n)]]),
      );
      expect(await this.sfc.getEpochAverageUptime(await this.sfc.currentSealedEpoch(), this.validatorId)).to.equal(
        500000000000000000n,
      );

      // fill the averaging window
      for (let i = 0; i < 10; i++) {
        await this.blockchainNode.sealEpoch(
          100,
          new Map<bigint, ValidatorMetrics>([[this.validatorId, new ValidatorMetrics(0, 0, 50, 0n)]]),
        );
        expect(await this.sfc.getEpochAverageUptime(await this.sfc.currentSealedEpoch(), this.validatorId)).to.equal(
          500000000000000000n,
        );
      }

      // (50 * 10 + 28) / 11 = 48
      await this.blockchainNode.sealEpoch(
        100,
        new Map<bigint, ValidatorMetrics>([[this.validatorId, new ValidatorMetrics(0, 0, 28, 0n)]]),
      );
      expect(await this.sfc.getEpochAverageUptime(await this.sfc.currentSealedEpoch(), this.validatorId)).to.equal(
        480000000000000000n,
      );
    });
  });
});
