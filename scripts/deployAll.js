const execSync = require('child_process').execSync;
const path = require('path');

const network = process.argv[2];

execSync(`cd src${path.sep}core && npx hardhat run --network ${network} scripts${path.sep}deploy.js`, {stdio: 'inherit'});

//execSync(`cd src${path.sep}periphery && npx hardhat run --network ${network} scripts${path.sep}deploy.js`, {stdio: 'inherit'});

//execSync(`cd src${path.sep}tokenomics && npx hardhat run --network ${network} scripts${path.sep}deploy.js`, {stdio: 'inherit'});
