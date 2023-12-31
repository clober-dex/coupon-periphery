// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IWETH9} from "../../../contracts/external/weth/IWETH9.sol";
import {IPool} from "../../../contracts/external/aave-v3/IPool.sol";
import {ISubstitute} from "../../../contracts/interfaces/ISubstitute.sol";
import {IAaveTokenSubstitute} from "../../../contracts/interfaces/IAaveTokenSubstitute.sol";
import {ICouponManager} from "../../../contracts/interfaces/ICouponManager.sol";
import {CouponKey, CouponKeyLibrary} from "../../../contracts/libraries/CouponKey.sol";
import {Coupon, CouponLibrary} from "../../../contracts/libraries/Coupon.sol";
import {Epoch, EpochLibrary} from "../../../contracts/libraries/Epoch.sol";
import {AaveTokenSubstitute} from "../../../contracts/AaveTokenSubstitute.sol";
import {Constants} from "../Constants.sol";
import {IAToken} from "../../../contracts/external/aave-v3/IAToken.sol";
import {DataTypes} from "../../../contracts/external/aave-v3/DataTypes.sol";
import {ReserveConfiguration} from "../../../contracts/external/aave-v3/ReserveConfiguration.sol";
import {WadRayMath} from "../../../contracts/libraries/WadRayMath.sol";
import {ForkUtils, ERC20Utils, Utils} from "../Utils.sol";

contract AaveTokenSubstituteUnitTest is Test, ERC1155Holder {
    using ERC20Utils for IERC20;
    using WadRayMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    AaveTokenSubstitute public aaveTokenSubstitute;
    IERC20 public usdc;
    IERC20 public aUsdc;

    function setUp() public {
        ForkUtils.fork(vm, Constants.FORK_BLOCK_NUMBER);

        usdc = IERC20(Constants.USDC);

        vm.startPrank(Constants.USDC_MINTER);
        (bool success,) = Constants.USDC.call(
            abi.encodePacked(
                bytes4(keccak256("mint(address,uint256)")), abi.encode(address(this), usdc.amount(23_000_000))
            )
        );
        require(success);
        vm.stopPrank();

        vm.startPrank(Constants.USDC_WHALE);
        usdc.transfer(address(this), usdc.amount(10_000_000));
        vm.stopPrank();

        aaveTokenSubstitute = new AaveTokenSubstitute(
            Constants.WETH, Constants.USDC, Constants.AAVE_V3_POOL, Constants.TREASURY, address(this)
        );

        aUsdc = IERC20(aaveTokenSubstitute.aToken());

        usdc.approve(Constants.AAVE_V3_POOL, usdc.amount(500_000));
        IPool(Constants.AAVE_V3_POOL).supply(Constants.USDC, usdc.amount(500_000), address(this), 0);
    }

    function testMint() public {
        uint256 amount = usdc.amount(1_000);

        uint256 beforeTokenBalance = usdc.balanceOf(address(this));
        uint256 beforeATokenBalance = aUsdc.balanceOf(address(aaveTokenSubstitute));
        uint256 beforeSubstituteBalance = aaveTokenSubstitute.balanceOf(address(this));

        IERC20(usdc).approve(address(aaveTokenSubstitute), amount);
        aaveTokenSubstitute.mint(amount, address(this));

        assertEq(beforeTokenBalance, usdc.balanceOf(address(this)) + amount, "USDC_BALANCE");
        assertEq(beforeATokenBalance + amount, aUsdc.balanceOf(address(aaveTokenSubstitute)), "AUSDC_BALANCE");
        assertEq(beforeSubstituteBalance + amount, aaveTokenSubstitute.balanceOf(address(this)), "WAUSDC_BALANCE");
    }

    function testMintByAToken() public {
        uint256 amount = usdc.amount(1_000);

        uint256 beforeTokenBalance = usdc.balanceOf(address(this));
        uint256 beforeATokenBalance = aUsdc.balanceOf(address(this));
        uint256 beforeSubstituteBalance = aaveTokenSubstitute.balanceOf(address(this));

        IERC20(aUsdc).approve(address(aaveTokenSubstitute), amount);
        aaveTokenSubstitute.mintByAToken(amount, address(this));

        assertEq(beforeTokenBalance, usdc.balanceOf(address(this)), "USDC_BALANCE");
        assertApproxEqAbs(beforeATokenBalance, aUsdc.balanceOf(address(this)) + amount, 1, "AUSDC_BALANCE");
        assertEq(beforeSubstituteBalance + amount, aaveTokenSubstitute.balanceOf(address(this)), "WAUSDC_BALANCE");
    }

    function testMintOverSupplyCap() public {
        uint256 amount = usdc.amount(32_000_000);

        DataTypes.ReserveConfigurationMap memory configuration =
            IPool(Constants.AAVE_V3_POOL).getReserveData(Constants.USDC).configuration;
        DataTypes.ReserveData memory reserveData = IPool(Constants.AAVE_V3_POOL).getReserveData(Constants.USDC);
        uint256 supplyCap = configuration.getSupplyCap() * (10 ** IERC20Metadata(Constants.USDC).decimals())
            - (IAToken(aaveTokenSubstitute.aToken()).scaledTotalSupply() + uint256(reserveData.accruedToTreasury)).rayMul(
                reserveData.liquidityIndex + aaveTokenSubstitute.SUPPLY_BUFFER()
            );

        uint256 beforeTokenBalance = usdc.balanceOf(address(aaveTokenSubstitute));
        uint256 beforeSubstituteBalance = aaveTokenSubstitute.balanceOf(address(this));

        IERC20(usdc).approve(address(aaveTokenSubstitute), amount);
        aaveTokenSubstitute.mint(amount, address(this));

        assertEq(beforeTokenBalance + amount - supplyCap, usdc.balanceOf(address(aaveTokenSubstitute)), "USDC_BALANCE");
        assertLe(supplyCap, aUsdc.balanceOf(address(aaveTokenSubstitute)), "AUSDC_BALANCE");
        assertEq(beforeSubstituteBalance + amount, aaveTokenSubstitute.balanceOf(address(this)), "WAUSDC_BALANCE");
    }

    function testMintableAmount() public {
        assertEq(aaveTokenSubstitute.mintableAmount(), type(uint256).max, "MINTABLE_AMOUNT");
    }

    function testBurnableAmount() public {
        assertEq(aaveTokenSubstitute.burnableAmount(), type(uint256).max, "BURNABLE_AMOUNT");
    }

    function testBurn() public {
        uint256 amount = usdc.amount(1_000);
        IERC20(usdc).approve(address(aaveTokenSubstitute), amount);
        aaveTokenSubstitute.mint(amount, address(this));

        uint256 beforeTokenBalance = usdc.balanceOf(address(this));
        uint256 beforeATokenBalance = aUsdc.balanceOf(address(this));
        uint256 beforeSubstituteBalance = aaveTokenSubstitute.balanceOf(address(this));

        aaveTokenSubstitute.burn(amount, address(this));

        assertEq(beforeTokenBalance + amount, usdc.balanceOf(address(this)), "USDC_BALANCE");
        assertEq(beforeATokenBalance, aUsdc.balanceOf(address(this)), "AUSDC_BALANCE");
        assertEq(beforeSubstituteBalance, aaveTokenSubstitute.balanceOf(address(this)) + amount, "WAUSDC_BALANCE");
    }

    function testBurnETH() public {
        aaveTokenSubstitute = new AaveTokenSubstitute(
            Constants.WETH, Constants.WETH, Constants.AAVE_V3_POOL, Constants.TREASURY, address(this)
        );
        uint256 amount = 10 ether;
        vm.deal(address(this), amount);
        IWETH9(Constants.WETH).deposit{value: amount}();
        IWETH9(Constants.WETH).approve(address(aaveTokenSubstitute), amount);
        aaveTokenSubstitute.mint(amount, address(this));

        vm.expectRevert(abi.encodeWithSelector(ISubstitute.ValueTransferFailed.selector));
        aaveTokenSubstitute.burn(amount, address(this));

        uint256 beforeTokenBalance = Constants.USER1.balance;
        uint256 beforeATokenBalance = aUsdc.balanceOf(Constants.USER1);
        uint256 beforeSubstituteBalance = aaveTokenSubstitute.balanceOf(address(this));

        aaveTokenSubstitute.burn(amount, Constants.USER1);

        assertEq(beforeTokenBalance + amount, Constants.USER1.balance, "ETH_BALANCE");
        assertEq(beforeATokenBalance, aUsdc.balanceOf(Constants.USER1), "AETH_BALANCE");
        assertEq(beforeSubstituteBalance, aaveTokenSubstitute.balanceOf(address(this)) + amount, "WAETH_BALANCE");
    }

    function testBurnWhenSupplyOverSupplyCap() public {
        uint256 amount = usdc.amount(32_000_000);
        uint256 withdrawAmount = usdc.amount(20_000_000);

        IERC20(usdc).approve(address(aaveTokenSubstitute), amount);
        aaveTokenSubstitute.mint(amount, address(this));

        uint256 beforeTokenBalance = usdc.balanceOf(address(this));
        uint256 beforeATokenBalance = aUsdc.balanceOf(address(this));
        uint256 beforeSubstituteBalance = aaveTokenSubstitute.balanceOf(address(this));

        aaveTokenSubstitute.burn(withdrawAmount, address(this));

        assertEq(beforeTokenBalance + withdrawAmount, usdc.balanceOf(address(this)), "USDC_BALANCE");
        assertEq(beforeATokenBalance, aUsdc.balanceOf(address(this)), "AUSDC_BALANCE");
        assertEq(
            beforeSubstituteBalance, aaveTokenSubstitute.balanceOf(address(this)) + withdrawAmount, "WAUSDC_BALANCE"
        );
    }

    function testBurnWhenAmountExceedsWithdrawableAmount() public {
        uint256 amount = usdc.amount(32_000_000);

        IERC20(usdc).approve(address(aaveTokenSubstitute), amount);
        aaveTokenSubstitute.mint(amount, address(this));

        uint256 withdrawableAmount = usdc.balanceOf(address(aUsdc));
        vm.prank(address(aUsdc));
        usdc.transfer(Constants.USER2, withdrawableAmount - amount / 3);

        uint256 expectedWithdrawUnderlyingAmount =
            usdc.balanceOf(address(aUsdc)) + usdc.balanceOf(address(aaveTokenSubstitute));

        uint256 beforeTokenBalance = usdc.balanceOf(address(this));
        uint256 beforeATokenBalance = aUsdc.balanceOf(address(this));
        uint256 beforeSubstituteBalance = aaveTokenSubstitute.balanceOf(address(this));

        aaveTokenSubstitute.burn(amount, address(this));

        assertEq(beforeTokenBalance + expectedWithdrawUnderlyingAmount, usdc.balanceOf(address(this)), "USDC_BALANCE");
        assertEq(
            beforeATokenBalance + amount - expectedWithdrawUnderlyingAmount,
            aUsdc.balanceOf(address(this)),
            "AUSDC_BALANCE"
        );
        assertEq(beforeSubstituteBalance, aaveTokenSubstitute.balanceOf(address(this)) + amount, "WAUSDC_BALANCE");
    }

    function testBurnByAToken() public {
        uint256 amount = usdc.amount(100);
        IERC20(usdc).approve(address(aaveTokenSubstitute), amount);
        aaveTokenSubstitute.mint(amount, address(this));

        uint256 beforeTokenBalance = usdc.balanceOf(address(this));
        uint256 beforeATokenBalance = aUsdc.balanceOf(address(this));
        uint256 beforeSubstituteBalance = aaveTokenSubstitute.balanceOf(address(this));

        aaveTokenSubstitute.burnToAToken(amount, address(this));

        assertEq(beforeTokenBalance, usdc.balanceOf(address(this)), "USDC_BALANCE");
        assertEq(beforeATokenBalance + amount, aUsdc.balanceOf(address(this)), "AUSDC_BALANCE");
        assertEq(beforeSubstituteBalance, aaveTokenSubstitute.balanceOf(address(this)) + amount, "WAUSDC_BALANCE");
    }

    function testClaim() public {
        uint256 amount = usdc.amount(100);
        IERC20(usdc).approve(address(aaveTokenSubstitute), amount);
        aaveTokenSubstitute.mint(amount, address(this));

        uint256 timestamp = block.timestamp;
        vm.warp(timestamp + 365 days);

        uint256 beforeTokenBalance = aUsdc.balanceOf(aaveTokenSubstitute.treasury());
        aaveTokenSubstitute.claim();
        assertLt(
            beforeTokenBalance + aUsdc.amount(2), aUsdc.balanceOf(aaveTokenSubstitute.treasury()), "TREASURY_BALANCE"
        );
        assertGe(aUsdc.balanceOf(address(aaveTokenSubstitute)), aaveTokenSubstitute.totalSupply());
    }

    function testSetTreasury() public {
        aaveTokenSubstitute.setTreasury(address(0xdeadbeef));
        assertEq(aaveTokenSubstitute.treasury(), address(0xdeadbeef), "TREASURY");
    }

    function testSetTreasuryOwnership() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0x123)));
        vm.prank(address(0x123));
        aaveTokenSubstitute.setTreasury(address(0xdeadbeef));
    }
}
