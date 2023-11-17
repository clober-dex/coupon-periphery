import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { hardhat } from 'viem/chains'
import { LIQUIDATOR_ROUTER, LOAN_POSITION_MANAGER, TOKENS, deployWithVerify } from '../utils'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, network } = hre

  if (await deployments.getOrNull('CouponLiquidator')) {
    return
  }

  const chainId = network.config.chainId || hardhat.id

  const args = [LOAN_POSITION_MANAGER[chainId], LIQUIDATOR_ROUTER[chainId], TOKENS[chainId].WETH]
  await deployWithVerify(hre, 'CouponLiquidator', args)
}

deployFunction.tags = ['CouponLiquidator']
export default deployFunction