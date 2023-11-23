import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { hardhat } from 'viem/chains'
import {
  CLOBER_FACTORY,
  TOKENS,
  WRAPPED1155_FACTORY,
  deployWithVerify,
  COUPON_MANAGER,
  BOND_POSITION_MANAGER,
  TOKEN_KEYS,
} from '../utils'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, network } = hre

  if (await deployments.getOrNull('DepositController')) {
    return
  }

  const chainId = network.config.chainId || hardhat.id

  const args = [
    WRAPPED1155_FACTORY[chainId],
    CLOBER_FACTORY[chainId],
    COUPON_MANAGER[chainId],
    TOKENS[chainId][TOKEN_KEYS.WETH],
    BOND_POSITION_MANAGER[chainId],
  ]
  await deployWithVerify(hre, 'DepositController', args)
}

deployFunction.tags = ['DepositController']
export default deployFunction
