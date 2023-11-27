import { task } from 'hardhat/config'
import { hardhat } from 'viem/chains'
import { decodeEventLog, zeroAddress } from 'viem'
import {
  AAVE_SUBSTITUTES,
  CLOBER_FACTORY,
  COUPON_MANAGER,
  TREASURY,
  WRAPPED1155_FACTORY,
  buildWrapped1155Metadata,
  convertToCouponId,
  getDeployedAddress,
  liveLog,
  TOKEN_KEYS,
} from '../utils'

task('coupon:current-epoch').setAction(async (taskArgs, hre) => {
  const chainId = hre.network.config.chainId ?? hardhat.id
  const couponManager = await hre.viem.getContractAt('ICouponManager', COUPON_MANAGER[chainId])
  liveLog(await couponManager.read.currentEpoch())
})

task('coupon:deploy-wrapped-token')
  .addParam('asset', 'the name of the asset')
  .addParam<number>('epoch', 'the epoch number')
  .setAction(async ({ asset, epoch }, hre) => {
    if (typeof epoch === 'string') {
      epoch = parseInt(epoch)
    }
    const chainId = hre.network.config.chainId ?? hardhat.id
    const couponManager = await hre.viem.getContractAt('ICouponManager', COUPON_MANAGER[chainId])
    const wrapped1155Factory = await hre.viem.getContractAt('IWrapped1155Factory', WRAPPED1155_FACTORY[chainId])
    const token = AAVE_SUBSTITUTES[chainId][asset]
    if (epoch < (await couponManager.read.currentEpoch())) {
      throw new Error('Cannot deploy for past epoch')
    }
    const metadata = await buildWrapped1155Metadata(token, epoch)
    const couponId = convertToCouponId(token, epoch)
    const computedAddress = await wrapped1155Factory.read.getWrapped1155([couponManager.address, couponId, metadata])
    const client = await hre.viem.getPublicClient()
    const remoteBytecode = await client.getBytecode({ address: computedAddress })
    if (remoteBytecode && remoteBytecode !== '0x') {
      liveLog('Already deployed:', computedAddress)
      return
    }
    const transactionHash = await wrapped1155Factory.write.requireWrapped1155([
      couponManager.address,
      couponId,
      metadata,
    ])
    liveLog(`Deployed ${asset} for epoch ${epoch} at ${computedAddress} at ${transactionHash}`)
  })

task('coupon:create-clober-market')
  .addParam('asset', 'the name of the asset')
  .addParam<number>('epoch', 'the epoch number')
  .setAction(async ({ asset, epoch }, hre) => {
    if (typeof epoch === 'string') {
      epoch = parseInt(epoch)
    }
    const chainId = hre.network.config.chainId ?? hardhat.id
    const couponManager = await hre.viem.getContractAt('ICouponManager', COUPON_MANAGER[chainId])
    const wrapped1155Factory = await hre.viem.getContractAt('IWrapped1155Factory', WRAPPED1155_FACTORY[chainId])
    const cloberFactory = await hre.viem.getContractAt('CloberMarketFactory', CLOBER_FACTORY[chainId])
    const depositController = await hre.viem.getContractAt(
      'DepositController',
      await getDeployedAddress('DepositController'),
    )
    const borrowController = await hre.viem.getContractAt(
      'BorrowController',
      await getDeployedAddress('BorrowController'),
    )
    const token = AAVE_SUBSTITUTES[chainId][asset]
    if (epoch < (await couponManager.read.currentEpoch())) {
      throw new Error('Cannot deploy for past epoch')
    }
    const computedAddress = await wrapped1155Factory.read.getWrapped1155([
      couponManager.address,
      convertToCouponId(token, epoch),
      await buildWrapped1155Metadata(token, epoch),
    ])
    const decimals = await (await hre.viem.getContractAt('IERC20Metadata', token)).read.decimals()
    let transactionHash = await cloberFactory.write.createVolatileMarket([
      TREASURY[chainId],
      token,
      computedAddress,
      decimals < 9 ? 1n : 10n ** 9n,
      0,
      400,
      10n ** 10n,
      10n ** 15n * 1001n,
    ])

    const client = await hre.viem.getPublicClient()
    const receipt = await client.getTransactionReceipt({ hash: transactionHash })
    const event = receipt.logs
      .map((log) => {
        return decodeEventLog({
          abi: cloberFactory.abi,
          data: log.data,
          topics: log.topics,
        })
      })
      .find((e) => e.eventName === 'CreateVolatileMarket')
    if (!event || event.eventName !== 'CreateVolatileMarket') {
      throw new Error('Cannot find event')
    }

    const deployedAddress = event.args['market']
    liveLog(`Created market for ${asset}-${epoch} at ${deployedAddress} on tx ${transactionHash}`)

    transactionHash = await depositController.write.setCouponMarket([{ asset: token, epoch }, deployedAddress])
    liveLog(`Set deposit controller for ${asset}-${epoch} to ${deployedAddress} on tx ${transactionHash}`)

    transactionHash = await borrowController.write.setCouponMarket([{ asset: token, epoch }, deployedAddress])
    liveLog(`Set borrow controller for ${asset}-${epoch} to ${deployedAddress} on tx ${transactionHash}`)
  })

task('coupon:migrate-market-register')
  .addParam('asset', 'the name of the asset')
  .addParam<number>('epoch', 'the epoch number')
  .addParam('from', 'the address of the controller to migrate from')
  .addParam('to', 'the address of the controller to migrate to')
  .setAction(async ({ asset, epoch, from, to }, hre) => {
    if (typeof epoch === 'string') {
      epoch = parseInt(epoch)
    }
    const chainId = hre.network.config.chainId ?? hardhat.id
    const couponManager = await hre.viem.getContractAt('ICouponManager', COUPON_MANAGER[chainId])
    const token = AAVE_SUBSTITUTES[chainId][asset]
    if (epoch < (await couponManager.read.currentEpoch())) {
      throw new Error('Cannot deploy for past epoch')
    }
    const fromController = await hre.viem.getContractAt('Controller', from)
    const toController = await hre.viem.getContractAt('Controller', to)
    const market = await fromController.read.getCouponMarket([{ asset: token, epoch }])
    if (market === zeroAddress) {
      throw new Error('Cannot find market')
    }
    const transactionHash = await toController.write.setCouponMarket([{ asset: token, epoch }, market])
    liveLog(`Migrated ${asset}-${epoch}(${market}) on tx ${transactionHash}`)
  })
