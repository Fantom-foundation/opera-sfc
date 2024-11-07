import { ethers, upgrades } from 'hardhat';
import { expect } from 'chai';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { beforeEach } from 'mocha';

describe('SFC', () => {
  const fixture = async () => {
    const [user, owner] = await ethers.getSigners();
    const sfc = await upgrades.deployProxy(await ethers.getContractFactory('SFC'), {
      kind: 'uups',
      initializer: false,
    });

    const epoch = 10;
    const supply = 100_000;
    const nodeDriver = ethers.Wallet.createRandom();
    const constsManager = ethers.Wallet.createRandom();

    // initialize the sfc
    await sfc.initialize(epoch, supply, nodeDriver, constsManager, owner);

    return {
      owner,
      user,
      sfc,
      epoch,
      supply,
      nodeDriver,
      constsManager,
    };
  };

  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('Initialization', () => {
    it('Should succeed and initialize', async function () {
      expect(await this.sfc.currentSealedEpoch()).to.equal(this.epoch);
      expect(await this.sfc.constsAddress()).to.equal(this.constsManager);
      expect(await this.sfc.totalSupply()).to.equal(this.supply);
      expect(await this.sfc.owner()).to.equal(this.owner);
    });

    it('Should revert when already initialized', async function () {
      await expect(
        this.sfc.initialize(this.epoch, this.supply, this.nodeDriver, this.constsManager, this.owner),
      ).to.be.revertedWithCustomError(this.sfc, 'InvalidInitialization');
    });

    describe('Upgrade', () => {
      it('Should revert when not owner', async function () {
        await expect(
          upgrades.upgradeProxy(this.sfc, (await ethers.getContractFactory('SFC')).connect(this.user)),
        ).to.be.revertedWithCustomError(this.sfc, 'OwnableUnauthorizedAccount');
      });

      it('Should succeed and upgrade', async function () {
        // try updating some variable
        const newContsManager = ethers.Wallet.createRandom();
        await this.sfc.connect(this.owner).updateConstsAddress(newContsManager);

        // get the implementation address
        // the address is stored at slot keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1
        const implementation = await ethers.provider.getStorage(
          this.sfc,
          '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc',
        );

        // upgrade proxy with unit test sfc - to skip bytecode optimization and replace the implementation for real
        await upgrades.upgradeProxy(this.sfc, (await ethers.getContractFactory('UnitTestSFC')).connect(this.owner));

        // check if the variable is still the same
        expect(await this.sfc.constsAddress()).to.equal(newContsManager);

        // check that the implementation address changed
        const newImplementation = await ethers.provider.getStorage(
          this.sfc,
          '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc',
        );

        expect(newImplementation).to.not.equal(implementation);
      });
    });
  });
});
