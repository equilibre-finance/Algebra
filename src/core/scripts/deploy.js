const hre = require("hardhat");
const fs = require('fs');
const path = require('path');

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using node you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

    let vault = process.env.VAULT;
    if( !vault ) {
        // set vault as deployer:
        vault = (await hre.ethers.getSigners())[0].address;
        console.log("No vault specified, using deployer address:", vault);
    }

  // We get the contract to deploy
    const PoolDeployerFactory = await hre.ethers.getContractFactory("AlgebraPoolDeployer");
    const poolDeployer  = await PoolDeployerFactory.deploy();
    await poolDeployer.deployed();
    const AlgebraFactory = await hre.ethers.getContractFactory("AlgebraFactory");
    const Algebra = await AlgebraFactory.deploy(poolDeployer.address, vault);

    await Algebra.deployed();

    await poolDeployer.setFactory(Algebra.address)

    console.log("AlgebraPoolDeployer to:", poolDeployer.address);
    console.log("AlgebraFactory deployed to:", Algebra.address);

    const deployDataPath = path.resolve(__dirname, '../../../deploys.json');
    let deploysData = JSON.parse(fs.readFileSync(deployDataPath, 'utf8'));

    // set contracts addresses in deploys.json by network id:
    const network = await hre.ethers.provider.getNetwork();
    const chainId = network.chainId;

    deploysData[chainId] = deploysData[chainId] || {};
    deploysData[chainId].poolDeployer = poolDeployer.address;
    deploysData[chainId].factory = Algebra.address;
    fs.writeFileSync(deployDataPath, JSON.stringify(deploysData, undefined, 4), 'utf-8');

    if( chainId !== 31337 ) {
        // wait some blocks for etherscan/blockscout to index contract:
        const ms = 1000*60*2;
        console.log(`wait ${ms/1000/60}/m for etherscan/blockscout to index contract:`);
        await new Promise(resolve => setTimeout(resolve, ms));

        // verify if not in hardhat network:
        try {
            await hre.run("verify:verify", {address: poolDeployer.address});
        } catch (e) {
            console.log(e);
        }

        try {
            await hre.run("verify:verify", {
                address: Algebra.address,
                constructorArguments: [poolDeployer.address, vault]
            });
        } catch (e) {
            console.log(e);
        }

    }

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
