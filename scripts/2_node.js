async function main() {
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
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
