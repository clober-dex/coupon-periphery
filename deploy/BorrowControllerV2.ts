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
  CLOBERV2_CONTROLLER,
  CLOBERV2_BOOK_MANAGER,
} from '../utils'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, network } = hre

  if (await deployments.getOrNull('BorrowControllerV2')) {
    return
  }

  const chainId = network.config.chainId || hardhat.id

  const args = [
    WRAPPED1155_FACTORY[chainId],
    CLOBERV2_CONTROLLER[chainId],
    CLOBERV2_BOOK_MANAGER[chainId],
    COUPON_MANAGER[chainId],
    TOKENS[chainId][TOKEN_KEYS.WETH],
    LOAN_POSITION_MANAGER[chainId],
    ROUTER[chainId],
  ]
  await deployWithVerify(hre, 'BorrowControllerV2', args)
}

deployFunction.tags = ['BorrowControllerV2']
export default deployFunction
