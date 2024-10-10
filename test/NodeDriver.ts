import { ethers } from 'hardhat';
import { expect } from 'chai';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { EVMWriter, NetworkInitializer, NodeDriver, NodeDriverAuth, SFCLib, UnitTestSFC } from '../typechain-types';

describe('NodeDriver', () => {
  const fixture = async () => {
    const [owner, nonOwner] = await ethers.getSigners();
    const sfc: UnitTestSFC = await ethers.deployContract('UnitTestSFC');
    const nodeDriver: NodeDriver = await ethers.deployContract('NodeDriver');
    const evmWriter: EVMWriter = await ethers.deployContract('StubEvmWriter');
    const nodeDriverAuth: NodeDriverAuth = await ethers.deployContract('NodeDriverAuth');
    const sfcLib: SFCLib = await ethers.deployContract('UnitTestSFCLib');
    const initializer: NetworkInitializer = await ethers.deployContract('NetworkInitializer');

    await initializer.initializeAll(12, 0, sfc, sfcLib, nodeDriverAuth, nodeDriver, evmWriter, owner);

    return {
      owner,
      nonOwner,
      sfc,
      nodeDriver,
      evmWriter,
      nodeDriverAuth,
      sfcLib,
    };
  };

  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('Migrate', () => {
    it('Should succeed and migrate to a new address', async function () {
      const account = ethers.Wallet.createRandom();
      await this.nodeDriverAuth.migrateTo(account);
    });

    it('Should revert when not owner', async function () {
      const account = ethers.Wallet.createRandom();
      await expect(this.nodeDriverAuth.connect(this.nonOwner).migrateTo(account)).to.be.revertedWithCustomError(
        this.nodeDriverAuth,
        'NotOwner',
      );
    });
  });

  describe('Copy code', () => {
    it('Should succeed and copy code', async function () {
      const account = ethers.Wallet.createRandom();
      await this.nodeDriverAuth.copyCode(this.sfc, account);
    });

    it('Should revert when not owner', async function () {
      const address = ethers.Wallet.createRandom();
      await expect(
        this.nodeDriverAuth.connect(this.nonOwner).copyCode(this.sfc, address),
      ).to.be.revertedWithCustomError(this.nodeDriverAuth, 'NotOwner');
    });
  });

  describe('Update network version', () => {
    it('Should succeed and update network version', async function () {
      await expect(this.nodeDriverAuth.updateNetworkVersion(1))
        .to.emit(this.nodeDriver, 'UpdateNetworkVersion')
        .withArgs(1);
    });

    it('Should revert when not owner', async function () {
      await expect(this.nodeDriverAuth.connect(this.nonOwner).updateNetworkVersion(1)).to.be.revertedWithCustomError(
        this.nodeDriverAuth,
        'NotOwner',
      );
    });
  });

  describe('Advance epoch', () => {
    it('Should succeed and advance epoch', async function () {
      await expect(this.nodeDriverAuth.advanceEpochs(10)).to.emit(this.nodeDriver, 'AdvanceEpochs').withArgs(10);
    });

    it('Should revert when not owner', async function () {
      await expect(this.nodeDriverAuth.connect(this.nonOwner).advanceEpochs(10)).to.be.revertedWithCustomError(
        this.nodeDriverAuth,
        'NotOwner',
      );
    });
  });

  describe('Set storage', () => {
    it('Should revert when not backend', async function () {
      const account = ethers.Wallet.createRandom();
      const key = ethers.encodeBytes32String('testKey');
      const value = ethers.encodeBytes32String('testValue');
      await expect(this.nodeDriver.setStorage(account, key, value)).to.be.revertedWith('caller is not the backend');
    });
  });

  describe('Set backend', () => {
    it('Should revert when not backend', async function () {
      const account = ethers.Wallet.createRandom();
      await expect(this.nodeDriver.setBackend(account)).to.be.revertedWith('caller is not the backend');
    });
  });

  describe('Swap code', () => {
    it('Should revert when not backend', async function () {
      const account = ethers.Wallet.createRandom();
      const account2 = ethers.Wallet.createRandom();
      await expect(this.nodeDriver.swapCode(account, account2)).to.be.revertedWith('caller is not the backend');
    });
  });

  describe('Add genesis validator', () => {
    it('Should revert when not node', async function () {
      const account = ethers.Wallet.createRandom();
      await expect(
        this.nodeDriver.setGenesisValidator(
          account,
          1,
          account.publicKey,
          0,
          await this.sfc.currentEpoch(),
          Date.now(),
          0,
          0,
        ),
      ).to.be.revertedWith('not callable');
    });
  });

  describe('Deactivate validator', () => {
    it('Should revert when not node', async function () {
      await expect(this.nodeDriver.deactivateValidator(0, 1)).to.be.revertedWith('not callable');
    });
  });

  describe('Set genesis delegation', () => {
    it('Should revert when not node', async function () {
      const account = ethers.Wallet.createRandom();
      await expect(this.nodeDriver.setGenesisDelegation(account, 1, 100, 0, 0, 0, 0, 0, 1000)).to.be.revertedWith(
        'not callable',
      );
    });
  });

  describe('Seal epoch validators', () => {
    it('Should revert when not node', async function () {
      await expect(this.nodeDriver.sealEpochValidators([0, 1])).to.be.revertedWith('not callable');
    });
  });

  describe('Seal epoch', () => {
    it('Should revert when not node', async function () {
      await expect(this.nodeDriver.sealEpoch([0, 1], [0, 1], [0, 1], [0, 1])).to.be.revertedWith('not callable');
      await expect(this.nodeDriver.sealEpochV1([0, 1], [0, 1], [0, 1], [0, 1], 0)).to.be.revertedWith('not callable');
    });
  });
});