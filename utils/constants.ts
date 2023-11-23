import { arbitrum, arbitrumGoerli } from 'viem/chains'
import { Address } from 'viem'

export const TESTNET_ID = 7777

export const SINGLETON_FACTORY = '0xce0042B868300000d44A59004Da54A005ffdcf9f'

export const OWNER: { [chainId: number]: Address } = {
  [arbitrum.id]: '0x1689FD73FfC888d47D201b72B0ae7A83c20fA274',
  [arbitrumGoerli.id]: '0xa0E3174f4D222C5CBf705A138C6a9369935EeD81',
  [TESTNET_ID]: '0xa0E3174f4D222C5CBf705A138C6a9369935EeD81',
}

export const ASSET_POOL: { [chainId: number]: Address } = {
  [arbitrum.id]: '0xBA4B7f0Dd297C68Ca472da58CfE1338B9E7A0D9e',
}

export const BOND_POSITION_MANAGER: { [chainId: number]: Address } = {
  [arbitrum.id]: '0x0Cf91Bc7a67B063142C029a69fF9C8ccd93476E2',
}

export const COUPON_MANAGER: { [chainId: number]: Address } = {
  [arbitrum.id]: '0x8bbcA766D175aDbffB073832262990df1c5ef748',
}

export const COUPON_ORACLE: { [chainId: number]: Address } = {
  [arbitrum.id]: '0xF8e9ab02b057978c29Ca57c7E086D46983764A13',
}

export const LOAN_POSITION_MANAGER: { [chainId: number]: Address } = {
  [arbitrum.id]: '0x03d65411684ae7B5440E11a6063881a774C733dF',
}

export const CLOBER_FACTORY: { [chainId: number]: Address } = {
  [arbitrum.id]: '0x24aC0938C010Fb520F1068e96d78E0458855111D',
}

export const WRAPPED1155_FACTORY: { [chainId: number]: Address } = {
  [arbitrum.id]: '0xfcBE16BfD991E4949244E59d9b524e6964b8BB75',
}

export const REPAY_ROUTER: { [chainId: number]: Address } = {
  [arbitrum.id]: '0xa669e7A0d4b3e4Fa48af2dE86BD4CD7126Be4e13',
}

export const LEVERAGE_ROUTER: { [chainId: number]: Address } = {
  [arbitrum.id]: '0xa669e7A0d4b3e4Fa48af2dE86BD4CD7126Be4e13',
}

export const LIQUIDATOR_ROUTER: { [chainId: number]: Address } = {
  [arbitrum.id]: '0xa669e7A0d4b3e4Fa48af2dE86BD4CD7126Be4e13',
}

export const TOKEN_KEYS = {
  WETH: 'WETH',
  wstETH: 'wstETH',
  USDC: 'USDC',
  USDCe: 'USDC.e',
  DAI: 'DAI',
  USDT: 'USDT',
  WBTC: 'WBTC',
}

export type TokenKeys = (typeof TOKEN_KEYS)[keyof typeof TOKEN_KEYS]

export const TOKENS: { [chainId: number]: { [name: TokenKeys]: Address } } = {
  [arbitrum.id]: {
    [TOKEN_KEYS.WETH]: '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1',
    [TOKEN_KEYS.wstETH]: '0x5979D7b546E38E414F7E9822514be443A4800529',
    [TOKEN_KEYS.USDC]: '0xaf88d065e77c8cC2239327C5EDb3A432268e5831',
    [TOKEN_KEYS.USDCe]: '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8',
    [TOKEN_KEYS.DAI]: '0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1',
    [TOKEN_KEYS.USDT]: '0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9',
    [TOKEN_KEYS.WBTC]: '0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f',
  },
  [arbitrumGoerli.id]: {
    [TOKEN_KEYS.WETH]: '0x4284186b053ACdBA28E8B26E99475d891533086a',
    [TOKEN_KEYS.USDC]: '0xd513E4537510C75E24f941f159B7CAFA74E7B3B9',
    [TOKEN_KEYS.DAI]: '0xe73C6dA65337ef99dBBc014C7858973Eba40a10b',
    [TOKEN_KEYS.USDT]: '0x8dA9412AbB78db20d0B496573D9066C474eA21B8',
    [TOKEN_KEYS.WBTC]: '0x1377b75237a9ee83aC0C76dE258E68e875d96334',
  },
}

export const AAVE_SUBSTITUTES: { [chainId: number]: { [name: TokenKeys]: Address } } = {
  [arbitrum.id]: {
    [TOKEN_KEYS.WETH]: '0xAb6c37355D6C06fcF73Ab0E049d9Cf922f297573',
    [TOKEN_KEYS.USDC]: '0x7Ed1145045c8B754506d375Cdf90734550d1077e',
    [TOKEN_KEYS.wstETH]: '0x4e0e151940ad5790ac087DA335F1104A5C4f6f71',
    [TOKEN_KEYS.DAI]: '0x43FE2BE829a00ba065FAF5B1170c3b0f1328eb37',
    [TOKEN_KEYS.USDCe]: '0x322d24b60795e3D4f0DD85F54FAbcd63A85dFF82',
    [TOKEN_KEYS.USDT]: '0x26185cC53695240f9298e1e81Fd95612aA19D68b',
    [TOKEN_KEYS.WBTC]: '0xCf94152a31BBC050603Ae3186b394269E4f0A8Fe',
  },
  [arbitrumGoerli.id]: {
    [TOKEN_KEYS.WETH]: '0x37FD1b14Ba333889bC6683D7ADec9c1aE11F3227',
    [TOKEN_KEYS.USDC]: '0x6E11A012910819E0855a2505B48A5C1562BE9981',
    [TOKEN_KEYS.DAI]: '0xE426dE788f08DA8BB002D0565dD3072eC028e07D',
    [TOKEN_KEYS.USDT]: '0xaa1C9E35D766D2093899ce0DE82dA3268EFB02a3',
    [TOKEN_KEYS.WBTC]: '0xcc7eEb01352C410dC27acd3A4249E26338a6146C',
  },
}
