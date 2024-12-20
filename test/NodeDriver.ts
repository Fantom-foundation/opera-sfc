import { ethers, upgrades } from 'hardhat';
import { expect } from 'chai';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { IEVMWriter, NetworkInitializer } from '../typechain-types';

describe('NodeDriver', () => {
  const fixture = async () => {
    const [owner, nonOwner] = await ethers.getSigners();
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

    const initializer: NetworkInitializer = await ethers.deployContract('NetworkInitializer');
    const evmWriter: IEVMWriter = await ethers.deployContract('StubEvmWriter');

    await initializer.initializeAll(12, 0, sfc, nodeDriverAuth, nodeDriver, evmWriter, owner);

    return {
      owner,
      nonOwner,
      sfc,
      nodeDriver,
      evmWriter,
      nodeDriverAuth,
    };
  };

  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
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
      ).to.be.revertedWithCustomError(this.nodeDriverAuth, 'OwnableUnauthorizedAccount');
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
        'OwnableUnauthorizedAccount',
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
        'OwnableUnauthorizedAccount',
      );
    });
  });

  describe('Set storage', () => {
    it('Should revert when not backend', async function () {
      const account = ethers.Wallet.createRandom();
      const key = ethers.encodeBytes32String('testKey');
      const value = ethers.encodeBytes32String('testValue');
      await expect(this.nodeDriver.setStorage(account, key, value)).to.be.revertedWithCustomError(
        this.nodeDriver,
        'NotBackend',
      );
    });
  });

  describe('Swap code', () => {
    it('Should revert when not backend', async function () {
      const account = ethers.Wallet.createRandom();
      const account2 = ethers.Wallet.createRandom();
      await expect(this.nodeDriver.swapCode(account, account2)).to.be.revertedWithCustomError(
        this.nodeDriver,
        'NotBackend',
      );
    });
  });

  describe('Add genesis validator', () => {
    it('Should revert when not node', async function () {
      const account = ethers.Wallet.createRandom();
      await expect(
        this.nodeDriver.setGenesisValidator(account, 1, account.publicKey, Date.now()),
      ).to.be.revertedWithCustomError(this.nodeDriver, 'NotNode');
    });
  });

  describe('Deactivate validator', () => {
    it('Should revert when not node', async function () {
      await expect(this.nodeDriver.deactivateValidator(0, 1)).to.be.revertedWithCustomError(this.nodeDriver, 'NotNode');
    });
  });

  describe('Set genesis delegation', () => {
    it('Should revert when not node', async function () {
      const account = ethers.Wallet.createRandom();
      await expect(this.nodeDriver.setGenesisDelegation(account, 1, 100)).to.be.revertedWithCustomError(
        this.nodeDriver,
        'NotNode',
      );
    });
  });

  describe('Seal epoch validators', () => {
    it('Should revert when not node', async function () {
      await expect(this.nodeDriver.sealEpochValidators([0, 1])).to.be.revertedWithCustomError(
        this.nodeDriver,
        'NotNode',
      );
    });
  });

  describe('Seal epoch', () => {
    it('Should revert when not node', async function () {
      await expect(this.nodeDriver.sealEpoch([0, 1], [0, 1], [0, 1], [0, 1])).to.be.revertedWithCustomError(
        this.nodeDriver,
        'NotNode',
      );
    });
  });
});
