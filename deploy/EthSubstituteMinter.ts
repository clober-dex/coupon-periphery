import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { hardhat } from 'viem/chains'
import { deployWithVerify, TOKEN_KEYS, TOKENS } from '../utils'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, network } = hre

  if (await deployments.getOrNull('EthSubstituteMinter')) {
    return
  }

  const chainId = network.config.chainId || hardhat.id

  const args = [TOKENS[chainId][TOKEN_KEYS.WETH]]
  await deployWithVerify(hre, 'EthSubstituteMinter', args)
}

deployFunction.tags = ['EthSubstituteMinter']
export default deployFunction
