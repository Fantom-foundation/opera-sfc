async function main() {
    const [deployer] = await ethers.getSigners();
    const deployerAddress = await deployer.getAddress();
    console.log('Deployer Address: ', deployerAddress);

    const NodeDriverAuth = await ethers.getContractFactory('NodeDriverAuth');
    const NodeDriver = await ethers.getContractFactory('NodeDriver');
    const StubEvmWriter = await ethers.getContractFactory('StubEvmWriter');

    const deployedNodeDriver = await NodeDriver.deploy();
    await deployedNodeDriver.deployed();
    console.log('NodeDriver deployed to:', deployedNodeDriver.address);

    const deployedNodeDriverAuth = await NodeDriverAuth.deploy();
    await deployedNodeDriverAuth.deployed();
    console.log('NodeDriverAuth deployed to:', deployedNodeDriverAuth.address);

    const deployedStubEvmWriter = await StubEvmWriter.deploy();
    await deployedStubEvmWriter.deployed();
    console.log('StubEvmWriter deployed to:', deployedStubEvmWriter.address);

    const SFC = await ethers.getContractFactory('SFC');
    const NetworkInitializer = await ethers.getContractFactory('NetworkInitializer');

    const deployedSFC = await SFC.deploy();
    await deployedSFC.deployed();
    console.log('SFC deployed to:', deployedSFC.address);

    const deployedNetworkInitializer = await NetworkInitializer.deploy();
    await deployedNetworkInitializer.deployed();
    console.log('NetworkInitializer deployed to:', deployedNetworkInitializer.address);

    console.log('initializing NetworkInitializer...');
    await deployedNetworkInitializer.initializeAll(0, 0, deployedSFC.address, deployedNodeDriverAuth.address, deployedNodeDriver.address, deployedStubEvmWriter.address, deployerAddress);



}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });