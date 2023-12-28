import { getHRE, liveLog } from './misc'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { Address, encodePacked, Hex, numberToHex } from 'viem'

export const getDeployedAddress = async (name: string): Promise<Address> => {
  const hre = getHRE()
  const deployments = await hre.deployments.get(name)
  return `0x${deployments.address.startsWith('0x') ? deployments.address.slice(2) : deployments.address}`
}

export const verify = async (contractAddress: string, args: any[]) => {
  liveLog(`Verifying Contract: ${contractAddress}`)
  try {
    await getHRE().run('verify:verify', {
      address: contractAddress,
      constructorArguments: args,
    })
  } catch (e) {
    console.log(e)
  }
}

export const deployWithVerify = async (hre: HardhatRuntimeEnvironment, name: string, args?: any[]) => {
  const { deployer } = await hre.getNamedAccounts()
  const deployedAddress = (
    await hre.deployments.deploy(name, {
      from: deployer,
      args: args,
      log: true,
    })
  ).address

  await hre.run('verify:verify', {
    address: deployedAddress,
    constructorArguments: args,
  })
}

export const buildWrapped1155Metadata = async (tokenAddress: Address, epoch: number): Promise<Hex> => {
  const hre = getHRE()
  const token = await hre.viem.getContractAt('IERC20Metadata', tokenAddress)
  const tokenSymbol = await token.read.symbol()
  const epochString = epoch.toString()
  const addLength = (tokenSymbol.length + epochString.length) * 2
  const nameData = encodePacked(
    ['string', 'string', 'string', 'string'],
    [tokenSymbol, ' Bond Coupon (', epochString, ')'],
  ).padEnd(66, '0')
  const symbolData = encodePacked(['string', 'string', 'string'], [tokenSymbol, '-CP', epochString]).padEnd(66, '0')
  const decimal = await token.read.decimals()
  return encodePacked(
    ['bytes32', 'bytes32', 'bytes1'],
    [
      numberToHex(BigInt(nameData) + BigInt(30 + addLength), { size: 32 }),
      numberToHex(BigInt(symbolData) + BigInt(6 + addLength), { size: 32 }),
      numberToHex(BigInt(decimal), { size: 1 }),
    ],
  )
}

export const convertToCouponId = (tokenAddress: Address, epoch: number): bigint => {
  return (BigInt(epoch) << 160n) + BigInt(tokenAddress)
}
