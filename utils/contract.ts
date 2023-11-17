import { getHRE } from './misc'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { Address } from 'viem'

export const getDeployedAddress = async (name: string): Promise<Address> => {
  const hre = getHRE()
  const deployments = await hre.deployments.get(name)
  return `0x${deployments.address.startsWith('0x') ? deployments.address.slice(2) : deployments.address}`
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
