// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CloberOrderBook} from "../../../contracts/external/clober/CloberOrderBook.sol";
import {CloberMarketFactory} from "../../../contracts/external/clober/CloberMarketFactory.sol";
import {ICouponMarketRouter} from "../../../contracts/interfaces/ICouponMarketRouter.sol";
import {ICouponManager} from "../../../contracts/interfaces/ICouponManager.sol";
import {ISubstitute} from "../../../contracts/interfaces/ISubstitute.sol";
import {Coupon} from "../../../contracts/libraries/Coupon.sol";
import {CouponKey, CouponKeyLibrary} from "../../../contracts/libraries/CouponKey.sol";
import {Epoch, EpochLibrary} from "../../../contracts/libraries/Epoch.sol";
import {CouponMarketRouter} from "../../../contracts/CouponMarketRouter.sol";
import {CouponWrapper} from "../../../contracts/CouponWrapper.sol";
import {Constants} from "../Constants.sol";
import {ForkUtils, PermitSignLibrary, VmLogUtilsLibrary} from "../Utils.sol";

contract CouponMarketRouterIntegrationTest is Test {
    using EpochLibrary for Epoch;
    using CouponKeyLibrary for CouponKey;
    using PermitSignLibrary for Vm;
    using VmLogUtilsLibrary for Vm.Log[];

    address private constant _WETH_COUPON_MARKET = address(0);
    // WaETH-CP646
    CloberOrderBook public market1 = CloberOrderBook(0x20079b5959A4C865D935D3AbC6141978cfac525D);
    // WaUSDC-CP646
    CloberOrderBook public market2 = CloberOrderBook(0x89f0541D282B950E05f8918dC8fA234961525f39);
    CloberMarketFactory public cloberFactory = CloberMarketFactory(Constants.CLOBER_FACTORY);
    ISubstitute public wethSubstitute = ISubstitute(Constants.COUPON_WETH_SUBSTITUTE);
    ISubstitute public usdcSubstitute = ISubstitute(Constants.COUPON_USDC_SUBSTITUTE);
    ICouponManager public couponManager = ICouponManager(Constants.COUPON_COUPON_MANAGER);
    CouponWrapper public wrapper;
    CouponMarketRouter public router;
    uint16 public ethBestBid;
    uint64 public ethBestBidAmount;
    uint16 public usdcBestBid;
    uint64 public usdcBestBidAmount;
    CouponKey public couponKey1;
    CouponKey public couponKey2;
    Epoch public epoch;
    IERC20 public wrappedCoupon1;
    IERC20 public wrappedCoupon2;
    IERC20 public usdc = IERC20(Constants.USDC);
    address public user;
    address public recipient = address(123);

    function setUp() public {
        ForkUtils.fork(vm, Constants.FORK_BLOCK_NUMBER);
        user = vm.addr(1);
        wrapper = new CouponWrapper(Constants.COUPON_COUPON_MANAGER, Constants.WRAPPED1155_FACTORY);
        router =
        new CouponMarketRouter(Constants.WRAPPED1155_FACTORY, address(cloberFactory), Constants.COUPON_COUPON_MANAGER, address(wrapper));
        epoch = EpochLibrary.current();
        couponKey1 = CouponKey({asset: address(wethSubstitute), epoch: epoch});
        ethBestBid = market1.bestPriceIndex(true);
        ethBestBidAmount = market1.getDepth(true, ethBestBid);
        wrappedCoupon1 = IERC20(wrapper.getWrappedCoupon(couponKey1));
        // ordered about 35.473342226039930014 ethers
        couponKey2 = CouponKey({asset: address(usdcSubstitute), epoch: epoch});
        usdcBestBid = market2.bestPriceIndex(true);
        usdcBestBidAmount = market2.getDepth(true, usdcBestBid);
        wrappedCoupon2 = IERC20(wrapper.getWrappedCoupon(couponKey2));

        Coupon[] memory mintCoupons = new Coupon[](2);
        mintCoupons[0] = Coupon({key: couponKey1, amount: 10 ether});
        mintCoupons[1] = Coupon({key: couponKey2, amount: 10 * 1e6});
        vm.prank(Constants.COUPON_BOND_POSITION_MANAGER);
        couponManager.mintBatch(user, mintCoupons, "");

        vm.startPrank(user);
        couponManager.setApprovalForAll(address(wrapper), true);
        mintCoupons[0].amount = 5 ether;
        mintCoupons[1].amount = 5 * 1e6;
        wrapper.wrap(mintCoupons, user);
        vm.stopPrank();
    }

    function testMarketSellCoupons() public {
        vm.startPrank(user);

        uint256 beforeCouponBalance = couponManager.balanceOf(user, couponKey1.toId());
        uint256 beforeWrappedCouponBalance = wrappedCoupon1.balanceOf(user);
        uint256 beforeBalance = user.balance;
        uint256 beforeRecipientBalance = recipient.balance;

        wrappedCoupon1.approve(address(router), 1 ether);
        vm.recordLogs();
        router.marketSellCoupons(_buildETHParams(2 ether), vm.signPermit(1, couponManager, address(router), true));
        Vm.Log[] memory takeOrders = vm.getRecordedLogs().findLogsByEvent(CloberOrderBook.TakeOrder.selector);

        (, uint64 rawAmount,) = abi.decode(takeOrders[0].data, (uint16, uint64, uint8));
        uint256 actualInputAmount = market1.rawToBase(rawAmount, ethBestBid, true);
        uint256 actualOutputAmount = market1.rawToQuote(rawAmount) * (1e6 - market1.takerFee()) / 1e6;

        uint256 afterCouponBalance = couponManager.balanceOf(user, couponKey1.toId());
        uint256 afterWrappedCouponBalance = wrappedCoupon1.balanceOf(user);
        uint256 afterBalance = user.balance;
        uint256 afterRecipientBalance = recipient.balance;

        assertGe(afterCouponBalance + 1 ether, beforeCouponBalance, "COUPON_BALANCE");
        assertEq(afterCouponBalance + actualInputAmount - 1 ether, beforeCouponBalance, "COUPON_BALANCE_ACTUAL");
        assertEq(afterWrappedCouponBalance + 1 ether, beforeWrappedCouponBalance, "WRAPPED_COUPON_BALANCE");
        assertEq(afterBalance, beforeBalance, "USER_ETH_BALANCE");
        assertEq(afterRecipientBalance, beforeRecipientBalance + actualOutputAmount, "RECIPIENT_ETH_BALANCE");

        vm.stopPrank();
    }

    function testMarketSellCouponsWhenWrappedCouponBalanceInSufficient() public {
        vm.startPrank(user);

        wrappedCoupon1.transfer(address(123), wrappedCoupon1.balanceOf(user) - 0.5 ether);
        assertEq(wrappedCoupon1.balanceOf(user), 0.5 ether, "BEFORE_WRAPPED_COUPON_BALANCE");

        uint256 beforeCouponBalance = couponManager.balanceOf(user, couponKey1.toId());
        uint256 beforeBalance = user.balance;
        uint256 beforeRecipientBalance = recipient.balance;

        wrappedCoupon1.approve(address(router), 1 ether);
        vm.recordLogs();
        router.marketSellCoupons(_buildETHParams(2 ether), vm.signPermit(1, couponManager, address(router), true));
        Vm.Log[] memory takeOrders = vm.getRecordedLogs().findLogsByEvent(CloberOrderBook.TakeOrder.selector);

        (, uint64 rawAmount,) = abi.decode(takeOrders[0].data, (uint16, uint64, uint8));
        uint256 actualInputAmount = market1.rawToBase(rawAmount, ethBestBid, true);
        uint256 actualOutputAmount = market1.rawToQuote(rawAmount) * (1e6 - market1.takerFee()) / 1e6;

        uint256 afterCouponBalance = couponManager.balanceOf(user, couponKey1.toId());
        uint256 afterWrappedCouponBalance = wrappedCoupon1.balanceOf(user);
        uint256 afterBalance = user.balance;
        uint256 afterRecipientBalance = recipient.balance;

        assertGe(afterCouponBalance + 1.5 ether, beforeCouponBalance, "COUPON_BALANCE");
        assertEq(afterCouponBalance + actualInputAmount - 0.5 ether, beforeCouponBalance, "COUPON_BALANCE_ACTUAL");
        assertEq(afterWrappedCouponBalance, 0, "WRAPPED_COUPON_BALANCE");
        assertEq(afterBalance, beforeBalance, "USER_ETH_BALANCE");
        assertEq(afterRecipientBalance, beforeRecipientBalance + actualOutputAmount, "RECIPIENT_ETH_BALANCE");

        vm.stopPrank();
    }

    function testMarketSellCouponsWithoutWrappedCoupons() public {
        vm.startPrank(user);

        uint256 beforeCouponBalance = couponManager.balanceOf(user, couponKey1.toId());
        uint256 beforeWrappedCouponBalance = wrappedCoupon1.balanceOf(user);
        uint256 beforeBalance = user.balance;
        uint256 beforeRecipientBalance = recipient.balance;

        vm.recordLogs();
        router.marketSellCoupons(_buildETHParams(2 ether), vm.signPermit(1, couponManager, address(router), true));
        Vm.Log[] memory takeOrders = vm.getRecordedLogs().findLogsByEvent(CloberOrderBook.TakeOrder.selector);

        (, uint64 rawAmount,) = abi.decode(takeOrders[0].data, (uint16, uint64, uint8));
        uint256 actualInputAmount = market1.rawToBase(rawAmount, ethBestBid, true);
        uint256 actualOutputAmount = market1.rawToQuote(rawAmount) * (1e6 - market1.takerFee()) / 1e6;

        uint256 afterCouponBalance = couponManager.balanceOf(user, couponKey1.toId());
        uint256 afterWrappedCouponBalance = wrappedCoupon1.balanceOf(user);
        uint256 afterBalance = user.balance;
        uint256 afterRecipientBalance = recipient.balance;

        assertGe(afterCouponBalance + 2 ether, beforeCouponBalance, "COUPON_BALANCE");
        assertEq(afterCouponBalance + actualInputAmount, beforeCouponBalance, "COUPON_BALANCE_ACTUAL");
        assertEq(afterWrappedCouponBalance, beforeWrappedCouponBalance, "WRAPPED_COUPON_BALANCE");
        assertEq(afterBalance, beforeBalance, "USER_ETH_BALANCE");
        assertEq(afterRecipientBalance, beforeRecipientBalance + actualOutputAmount, "RECIPIENT_ETH_BALANCE");

        vm.stopPrank();
    }

    function testMarketSellCouponsOnlyWithWrappedCoupons() public {
        vm.startPrank(user);

        uint256 beforeCouponBalance = couponManager.balanceOf(user, couponKey1.toId());
        uint256 beforeWrappedCouponBalance = wrappedCoupon1.balanceOf(user);
        uint256 beforeBalance = user.balance;
        uint256 beforeRecipientBalance = recipient.balance;

        wrappedCoupon1.approve(address(router), 2 ether);
        vm.recordLogs();
        router.marketSellCoupons(_buildETHParams(2 ether), vm.signPermit(1, couponManager, address(router), true));
        Vm.Log[] memory takeOrders = vm.getRecordedLogs().findLogsByEvent(CloberOrderBook.TakeOrder.selector);

        (, uint64 rawAmount,) = abi.decode(takeOrders[0].data, (uint16, uint64, uint8));
        uint256 actualInputAmount = market1.rawToBase(rawAmount, ethBestBid, true);
        uint256 actualOutputAmount = market1.rawToQuote(rawAmount) * (1e6 - market1.takerFee()) / 1e6;

        uint256 afterCouponBalance = couponManager.balanceOf(user, couponKey1.toId());
        uint256 afterWrappedCouponBalance = wrappedCoupon1.balanceOf(user);
        uint256 afterBalance = user.balance;
        uint256 afterRecipientBalance = recipient.balance;

        assertEq(afterCouponBalance, beforeCouponBalance, "COUPON_BALANCE");
        assertGe(afterWrappedCouponBalance + 2 ether, beforeWrappedCouponBalance, "WRAPPED_COUPON_BALANCE");
        assertEq(
            afterWrappedCouponBalance + actualInputAmount, beforeWrappedCouponBalance, "WRAPPED_COUPON_BALANCE_ACTUAL"
        );
        assertEq(afterBalance, beforeBalance, "USER_ETH_BALANCE");
        assertEq(afterRecipientBalance, beforeRecipientBalance + actualOutputAmount, "RECIPIENT_ETH_BALANCE");

        vm.stopPrank();
    }

    function testBatchMarketSellCoupons() public {
        vm.startPrank(user);

        uint256[2] memory beforeCouponBalance =
            [couponManager.balanceOf(user, couponKey1.toId()), couponManager.balanceOf(user, couponKey2.toId())];
        uint256[2] memory beforeWrappedCouponBalance = [wrappedCoupon1.balanceOf(user), wrappedCoupon2.balanceOf(user)];
        uint256[2] memory beforeBalance = [user.balance, usdc.balanceOf(user)];
        uint256[2] memory beforeRecipientBalance = [recipient.balance, usdc.balanceOf(recipient)];

        wrappedCoupon1.approve(address(router), 1 ether);
        wrappedCoupon2.approve(address(router), 1e6 / 2);
        vm.recordLogs();
        ICouponMarketRouter.MarketSellParams[] memory paramsList = new ICouponMarketRouter.MarketSellParams[](2);
        paramsList[0] = _buildETHParams(1 ether);
        paramsList[1] = _buildUSDCParams(1e6);
        router.batchMarketSellCoupons(paramsList, vm.signPermit(1, couponManager, address(router), true));
        Vm.Log[] memory takeOrders = vm.getRecordedLogs().findLogsByEvent(CloberOrderBook.TakeOrder.selector);

        (, uint64 rawAmount1,) = abi.decode(takeOrders[0].data, (uint16, uint64, uint8));
        (, uint64 rawAmount2,) = abi.decode(takeOrders[1].data, (uint16, uint64, uint8));
        uint256[2] memory actualInputAmount =
            [market1.rawToBase(rawAmount1, ethBestBid, true), market2.rawToBase(rawAmount2, usdcBestBid, true)];
        uint256[2] memory actualOutputAmount = [
            market1.rawToQuote(rawAmount1) * (1e6 - market1.takerFee()) / 1e6,
            market2.rawToQuote(rawAmount2) * (1e6 - market2.takerFee()) / 1e6
        ];

        uint256[2] memory afterCouponBalance =
            [couponManager.balanceOf(user, couponKey1.toId()), couponManager.balanceOf(user, couponKey2.toId())];
        uint256[2] memory afterWrappedCouponBalance = [wrappedCoupon1.balanceOf(user), wrappedCoupon2.balanceOf(user)];
        uint256[2] memory afterBalance = [user.balance, usdc.balanceOf(user)];
        uint256[2] memory afterRecipientBalance = [recipient.balance, usdc.balanceOf(recipient)];

        assertEq(afterCouponBalance[0], beforeCouponBalance[0], "COUPON_BALANCE[0]");
        assertGe(afterWrappedCouponBalance[0] + 1 ether, afterWrappedCouponBalance[0], "WRAPPED_COUPON_BALANCE[0]");
        assertEq(
            afterWrappedCouponBalance[0] + actualInputAmount[0],
            beforeWrappedCouponBalance[0],
            "WRAPPED_COUPON_BALANCE_ACTUAL[0]"
        );
        assertEq(afterBalance[0], beforeBalance[0], "USER_ETH_BALANCE[0]");
        assertEq(
            afterRecipientBalance[0], beforeRecipientBalance[0] + actualOutputAmount[0], "RECIPIENT_ETH_BALANCE[0]"
        );
        assertGe(afterCouponBalance[1] + 1e6 / 2, beforeCouponBalance[1], "COUPON_BALANCE[1]");
        assertEq(
            afterCouponBalance[1] + actualInputAmount[1] - 1e6 / 2, beforeCouponBalance[1], "COUPON_BALANCE_ACTUAL[1]"
        );
        assertEq(afterWrappedCouponBalance[1] + 1e6 / 2, beforeWrappedCouponBalance[1], "WRAPPED_COUPON_BALANCE[1]");
        assertEq(afterBalance[1], beforeBalance[1], "USER_ETH_BALANCE[1]");
        assertEq(
            afterRecipientBalance[1], beforeRecipientBalance[1] + actualOutputAmount[1], "RECIPIENT_ETH_BALANCE[1]"
        );

        vm.stopPrank();
    }

    function _buildETHParams(uint256 sellAmount) internal view returns (ICouponMarketRouter.MarketSellParams memory) {
        return ICouponMarketRouter.MarketSellParams({
            market: address(market1),
            deadline: type(uint64).max,
            limitPriceIndex: 0,
            minRawAmount: 0,
            recipient: recipient,
            couponKey: couponKey1,
            amount: sellAmount
        });
    }

    function _buildUSDCParams(uint256 sellAmount) internal view returns (ICouponMarketRouter.MarketSellParams memory) {
        return ICouponMarketRouter.MarketSellParams({
            market: address(market2),
            deadline: type(uint64).max,
            limitPriceIndex: 0,
            minRawAmount: 0,
            recipient: recipient,
            couponKey: couponKey2,
            amount: sellAmount
        });
    }
}
