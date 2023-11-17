import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { hardhat } from 'viem/chains'
import {
  CLOBER_FACTORY,
  LEVERAGE_ROUTER,
  TOKENS,
  WRAPPED1155_FACTORY,
  deployWithVerify,
  COUPON_MANAGER,
  LOAN_POSITION_MANAGER,
} from '../utils'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, network } = hre

  if (await deployments.getOrNull('LeverageAdapter')) {
    return
  }

  const chainId = network.config.chainId || hardhat.id

  const args = [
    WRAPPED1155_FACTORY[chainId],
    CLOBER_FACTORY[chainId],
    COUPON_MANAGER[chainId],
    TOKENS[chainId].WETH,
    LOAN_POSITION_MANAGER[chainId],
    LEVERAGE_ROUTER[chainId],
  ]
  await deployWithVerify(hre, 'LeverageAdapter', args)
}

deployFunction.tags = ['LeverageAdapter']
export default deployFunction
