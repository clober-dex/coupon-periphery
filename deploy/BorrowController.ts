import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { hardhat } from 'viem/chains'
import {
  CLOBER_FACTORY,
  COUPON_MANAGER,
  LOAN_POSITION_MANAGER,
  TOKENS,
  WRAPPED1155_FACTORY,
  deployWithVerify,
  TOKEN_KEYS,
  ROUTER,
} from '../utils'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, network } = hre

  // deprecated
  return

  if (await deployments.getOrNull('BorrowController')) {
    return
  }

  const chainId = network.config.chainId || hardhat.id

  const args = [
    WRAPPED1155_FACTORY[chainId],
    CLOBER_FACTORY[chainId],
    COUPON_MANAGER[chainId],
    TOKENS[chainId][TOKEN_KEYS.WETH],
    LOAN_POSITION_MANAGER[chainId],
    ROUTER[chainId],
  ]
  await deployWithVerify(hre, 'BorrowController', args)
}

deployFunction.tags = ['BorrowController']
export default deployFunction
