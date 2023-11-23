import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { hardhat } from 'viem/chains'
import { deployWithVerify, COUPON_MANAGER, WRAPPED1155_FACTORY } from '../utils'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, network } = hre

  if (await deployments.getOrNull('CouponWrapper')) {
    return
  }

  const chainId = network.config.chainId || hardhat.id

  const args = [COUPON_MANAGER[chainId], WRAPPED1155_FACTORY[chainId]]
  await deployWithVerify(hre, 'CouponWrapper', args)
}

deployFunction.tags = ['CouponWrapper']
export default deployFunction
