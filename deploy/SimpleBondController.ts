import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { hardhat } from 'viem/chains'
import { BOND_POSITION_MANAGER, COUPON_MANAGER, deployWithVerify, OWNER, TOKEN_KEYS, TOKENS } from '../utils'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, network } = hre

  if (await deployments.getOrNull('SimpleBondController')) {
    return
  }

  const chainId = network.config.chainId || hardhat.id

  const args = [
    TOKENS[chainId][TOKEN_KEYS.WETH],
    BOND_POSITION_MANAGER[chainId],
    COUPON_MANAGER[chainId],
    (await deployments.get('CouponWrapper')).address,
    OWNER[chainId],
  ]
  await deployWithVerify(hre, 'SimpleBondController', args)
}

deployFunction.tags = ['SimpleBondController']
deployFunction.dependencies = ['CouponWrapper']
export default deployFunction
