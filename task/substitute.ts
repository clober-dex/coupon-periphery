import { task } from 'hardhat/config'
import { AAVE_V3_POOL, OWNER, SINGLETON_FACTORY, TOKEN_KEYS, TOKENS, TREASURY, verify } from '../utils'
import { hardhat } from 'viem/chains'
import AaveTokenSubstitute from '../artifacts/contracts/AaveTokenSubstitute.sol/AaveTokenSubstitute.json'
import SimpleTokenSubstitute from '../artifacts/contracts/SimpleTokenSubstitute.sol/SimpleTokenSubstitute.json'
import { encodeDeployData, Hex, getCreate2Address } from 'viem'

task('substitute:aave:deploy')
  .addParam('asset', 'name of the asset')
  .setAction(async ({ asset }, hre) => {
    const singletonFactory = await hre.viem.getContractAt('ISingletonFactory', SINGLETON_FACTORY)
    const chainId = hre.network.config.chainId ?? hardhat.id
    const emptyAaveSubstitute = await hre.viem.getContractAt('AaveTokenSubstitute', '0x')
    const aaveV3Pool = AAVE_V3_POOL[chainId]
    const treasury = TREASURY[chainId]
    if (!aaveV3Pool || !treasury) {
      throw new Error('missing aaveV3Pool or treasury')
    }
    const constructorArgs = [
      TOKENS[chainId][TOKEN_KEYS.WETH],
      TOKENS[chainId][asset],
      aaveV3Pool,
      treasury,
      OWNER[chainId],
    ]
    const deployData = encodeDeployData({
      abi: emptyAaveSubstitute.abi,
      args: [TOKENS[chainId][TOKEN_KEYS.WETH], TOKENS[chainId][asset], aaveV3Pool, treasury, OWNER[chainId]],
      bytecode: AaveTokenSubstitute.bytecode as Hex,
    })
    const computedAddress = getCreate2Address({ from: singletonFactory.address, bytecode: deployData, salt: '0x' })
    const client = await hre.viem.getPublicClient()
    const remoteBytecode = await client.getBytecode({ address: computedAddress })
    if (remoteBytecode && remoteBytecode !== '0x') {
      console.log(`${asset} Substitute Contract already deployed:`, computedAddress)
    } else {
      const transactionHash = await singletonFactory.write.deploy([deployData, '0x'])
      console.log(`Deployed ${asset} AaveTokenSubstitute(${computedAddress}) at tx`, transactionHash)
    }
    await verify(computedAddress, constructorArgs)
  })

task('substitute:simple:deploy')
  .addParam('asset', 'name of the asset')
  .setAction(async ({ asset }, hre) => {
    const singletonFactory = await hre.viem.getContractAt('ISingletonFactory', SINGLETON_FACTORY)
    const chainId = hre.network.config.chainId ?? hardhat.id
    const emptySimpleSubstitute = await hre.viem.getContractAt('SimpleTokenSubstitute', '0x')
    const treasury = TREASURY[chainId]
    if (!treasury) {
      throw new Error('missing treasury')
    }
    const constructorArgs = [TOKENS[chainId][TOKEN_KEYS.WETH], TOKENS[chainId][asset], treasury, OWNER[chainId]]
    const deployData = encodeDeployData({
      abi: emptySimpleSubstitute.abi,
      args: [TOKENS[chainId][TOKEN_KEYS.WETH], TOKENS[chainId][asset], treasury, OWNER[chainId]],
      bytecode: SimpleTokenSubstitute.bytecode as Hex,
    })
    const computedAddress = getCreate2Address({ from: singletonFactory.address, bytecode: deployData, salt: '0x' })
    const client = await hre.viem.getPublicClient()
    const remoteBytecode = await client.getBytecode({ address: computedAddress })
    if (remoteBytecode && remoteBytecode !== '0x') {
      console.log(`${asset} Substitute Contract already deployed:`, computedAddress)
    } else {
      const transactionHash = await singletonFactory.write.deploy([deployData, '0x'])
      console.log(`Deployed ${asset} SimpleTokenSubstitute(${computedAddress}) at tx`, transactionHash)
    }
    await verify(computedAddress, constructorArgs)
  })

task('substitute:set-treasury')
  .addParam('address', 'address of the substitute')
  .setAction(async ({ address }, hre) => {
    const treasury = TREASURY[hre.network.config.chainId ?? hardhat.id]
    if (!treasury) {
      throw new Error('missing treasury')
    }
    const substitute = await hre.viem.getContractAt('ISubstitute', address)
    const transactionHash = await substitute.write.setTreasury([treasury])
    console.log('Set treasury at tx', transactionHash)
  })

task('substitute:claim')
  .addParam('address', 'address of the substitute')
  .setAction(async ({ address }, hre) => {
    const substitute = await hre.viem.getContractAt('ISubstitute', address)
    const transactionHash = await substitute.write.claim()
    console.log('Claimed at tx', transactionHash)
  })
