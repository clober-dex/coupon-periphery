import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { hardhat } from 'viem/chains'
import { deployWithVerify, COUPON_MANAGER, WRAPPED1155_FACTORY, CLOBER_FACTORY } from '../utils'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, network } = hre

  // deprecated
  return
  if (await deployments.getOrNull('CouponMarketRouter')) {
    return
  }

  const chainId = network.config.chainId || hardhat.id

  const args = [
    WRAPPED1155_FACTORY[chainId],
    CLOBER_FACTORY[chainId],
    COUPON_MANAGER[chainId],
    (await deployments.get('CouponWrapper')).address,
  ]
  await deployWithVerify(hre, 'CouponMarketRouter', args)
}

deployFunction.tags = ['CouponMarketRouter']
deployFunction.dependencies = ['CouponWrapper']
export default deployFunction
