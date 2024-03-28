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
  CLOBERV2_CONTROLLER,
  CLOBERV2_BOOK_MANAGER,
} from '../utils'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, network } = hre

  if (await deployments.getOrNull('DepositControllerV2')) {
    return
  }

  const chainId = network.config.chainId || hardhat.id

  const args = [
    WRAPPED1155_FACTORY[chainId],
    CLOBERV2_CONTROLLER[chainId],
    CLOBERV2_BOOK_MANAGER[chainId],
    COUPON_MANAGER[chainId],
    TOKENS[chainId][TOKEN_KEYS.WETH],
    BOND_POSITION_MANAGER[chainId],
  ]
  await deployWithVerify(hre, 'DepositControllerV2', args)
}

deployFunction.tags = ['DepositControllerV2']
export default deployFunction
