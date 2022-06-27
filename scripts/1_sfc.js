async function main() {
  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();
  console.log('Deployer Address: ', deployerAddress);

  const SFC = await ethers.getContractFactory('SFC');
  const NetworkInitializer = await ethers.getContractFactory(
    'NetworkInitializer'
  );

  const deployedNetworkInitializer = await NetworkInitializer.deploy();
  await deployedNetworkInitializer.deployed();
  console.log(
    'NetworkInitializer deployed to:',
    deployedNetworkInitializer.address
  );

  const deployedSFC = await SFC.deploy();
  await deployedSFC.deployed();
  console.log('SFC deployed to:', deployedSFC.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
