import { ContractName, GetContractReturnType } from '@nomicfoundation/hardhat-viem/types'

import { getHRE } from './misc'

export const getDeployedContract = async <CN extends string>(
  contractName: ContractName<CN>,
): Promise<GetContractReturnType> => {
  const hre = getHRE()
  const deployments = await hre.deployments.get(contractName)

  return hre.viem.getContractAt<CN>(
    contractName,
    `0x${deployments.address.startsWith('0x') ? deployments.address.slice(2) : deployments.address}`,
  )
}
