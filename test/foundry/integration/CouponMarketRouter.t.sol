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
    CloberOrderBook public market = CloberOrderBook(0x20079b5959A4C865D935D3AbC6141978cfac525D);
    CloberMarketFactory public cloberFactory = CloberMarketFactory(Constants.CLOBER_FACTORY);
    ISubstitute public substitute = ISubstitute(Constants.COUPON_WETH_SUBSTITUTE);
    ICouponManager public couponManager = ICouponManager(Constants.COUPON_COUPON_MANAGER);
    CouponWrapper public wrapper;
    CouponMarketRouter public router;
    uint16 public bestBid;
    uint64 public bestBidAmount;
    CouponKey public couponKey;
    Epoch public epoch;
    IERC20 public wrappedCoupon;
    address public user;
    address public recipient = address(123);

    function setUp() public {
        ForkUtils.fork(vm, Constants.FORK_BLOCK_NUMBER);
        user = vm.addr(1);
        wrapper = new CouponWrapper(Constants.COUPON_COUPON_MANAGER, Constants.WRAPPED1155_FACTORY);
        router =
        new CouponMarketRouter(Constants.WRAPPED1155_FACTORY, address(cloberFactory), Constants.COUPON_COUPON_MANAGER, address(wrapper));
        epoch = EpochLibrary.current();
        couponKey = CouponKey({asset: address(substitute), epoch: epoch});
        bestBid = market.bestPriceIndex(true);
        bestBidAmount = market.getDepth(true, bestBid);
        wrappedCoupon = IERC20(wrapper.getWrappedCoupon(couponKey));
        // ordered about 35.473342226039930014 ethers

        Coupon[] memory mintCoupons = new Coupon[](1);
        mintCoupons[0] = Coupon({key: couponKey, amount: 10 ether});
        vm.prank(Constants.COUPON_BOND_POSITION_MANAGER);
        couponManager.mintBatch(user, mintCoupons, "");

        vm.startPrank(user);
        couponManager.setApprovalForAll(address(wrapper), true);
        mintCoupons[0].amount = 5 ether;
        wrapper.wrap(mintCoupons, user);
        vm.stopPrank();
    }

    function testMarketSellCoupons() public {
        vm.startPrank(user);

        uint256 beforeCouponBalance = couponManager.balanceOf(user, couponKey.toId());
        uint256 beforeWrappedCouponBalance = wrappedCoupon.balanceOf(user);
        uint256 beforeBalance = user.balance;
        uint256 beforeRecipientBalance = recipient.balance;

        wrappedCoupon.approve(address(router), 1 ether);
        vm.recordLogs();
        router.marketSellCoupons(_buildParams(2 ether), vm.signERC1155Permit(1, couponManager, address(router), true));
        Vm.Log[] memory takeOrders = vm.getRecordedLogs().findLogsByEvent(CloberOrderBook.TakeOrder.selector);

        // Catch event TakeOrder(address indexed sender, address indexed user, uint16 priceIndex, uint64 rawAmount, uint8 options);
        (, uint64 rawAmount,) = abi.decode(takeOrders[0].data, (uint16, uint64, uint8));
        uint256 actualInputAmount = market.rawToBase(rawAmount, bestBid, true);
        uint256 actualOutputAmount = market.rawToQuote(rawAmount) * (1e6 - market.takerFee()) / 1e6;

        uint256 afterCouponBalance = couponManager.balanceOf(user, couponKey.toId());
        uint256 afterWrappedCouponBalance = wrappedCoupon.balanceOf(user);
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

        wrappedCoupon.transfer(address(123), wrappedCoupon.balanceOf(user) - 0.5 ether);
        assertEq(wrappedCoupon.balanceOf(user), 0.5 ether, "BEFORE_WRAPPED_COUPON_BALANCE");

        uint256 beforeCouponBalance = couponManager.balanceOf(user, couponKey.toId());
        uint256 beforeBalance = user.balance;
        uint256 beforeRecipientBalance = recipient.balance;

        wrappedCoupon.approve(address(router), 1 ether);
        vm.recordLogs();
        router.marketSellCoupons(_buildParams(2 ether), vm.signERC1155Permit(1, couponManager, address(router), true));
        Vm.Log[] memory takeOrders = vm.getRecordedLogs().findLogsByEvent(CloberOrderBook.TakeOrder.selector);

        // Catch event TakeOrder(address indexed sender, address indexed user, uint16 priceIndex, uint64 rawAmount, uint8 options);
        (, uint64 rawAmount,) = abi.decode(takeOrders[0].data, (uint16, uint64, uint8));
        uint256 actualInputAmount = market.rawToBase(rawAmount, bestBid, true);
        uint256 actualOutputAmount = market.rawToQuote(rawAmount) * (1e6 - market.takerFee()) / 1e6;

        uint256 afterCouponBalance = couponManager.balanceOf(user, couponKey.toId());
        uint256 afterWrappedCouponBalance = wrappedCoupon.balanceOf(user);
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

        uint256 beforeCouponBalance = couponManager.balanceOf(user, couponKey.toId());
        uint256 beforeWrappedCouponBalance = wrappedCoupon.balanceOf(user);
        uint256 beforeBalance = user.balance;
        uint256 beforeRecipientBalance = recipient.balance;

        vm.recordLogs();
        router.marketSellCoupons(_buildParams(2 ether), vm.signERC1155Permit(1, couponManager, address(router), true));
        Vm.Log[] memory takeOrders = vm.getRecordedLogs().findLogsByEvent(CloberOrderBook.TakeOrder.selector);

        // Catch event TakeOrder(address indexed sender, address indexed user, uint16 priceIndex, uint64 rawAmount, uint8 options);
        (, uint64 rawAmount,) = abi.decode(takeOrders[0].data, (uint16, uint64, uint8));
        uint256 actualInputAmount = market.rawToBase(rawAmount, bestBid, true);
        uint256 actualOutputAmount = market.rawToQuote(rawAmount) * (1e6 - market.takerFee()) / 1e6;

        uint256 afterCouponBalance = couponManager.balanceOf(user, couponKey.toId());
        uint256 afterWrappedCouponBalance = wrappedCoupon.balanceOf(user);
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

        uint256 beforeCouponBalance = couponManager.balanceOf(user, couponKey.toId());
        uint256 beforeWrappedCouponBalance = wrappedCoupon.balanceOf(user);
        uint256 beforeBalance = user.balance;
        uint256 beforeRecipientBalance = recipient.balance;

        wrappedCoupon.approve(address(router), 2 ether);
        vm.recordLogs();
        router.marketSellCoupons(_buildParams(2 ether), vm.signERC1155Permit(1, couponManager, address(router), true));
        Vm.Log[] memory takeOrders = vm.getRecordedLogs().findLogsByEvent(CloberOrderBook.TakeOrder.selector);

        // Catch event TakeOrder(address indexed sender, address indexed user, uint16 priceIndex, uint64 rawAmount, uint8 options);
        (, uint64 rawAmount,) = abi.decode(takeOrders[0].data, (uint16, uint64, uint8));
        uint256 actualInputAmount = market.rawToBase(rawAmount, bestBid, true);
        uint256 actualOutputAmount = market.rawToQuote(rawAmount) * (1e6 - market.takerFee()) / 1e6;

        uint256 afterCouponBalance = couponManager.balanceOf(user, couponKey.toId());
        uint256 afterWrappedCouponBalance = wrappedCoupon.balanceOf(user);
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

    function _buildParams(uint256 sellAmount) internal view returns (ICouponMarketRouter.MarketSellParams memory) {
        return ICouponMarketRouter.MarketSellParams({
            market: address(market),
            deadline: type(uint64).max,
            limitPriceIndex: 0,
            minRawAmount: 0,
            recipient: recipient,
            couponKey: couponKey,
            amount: sellAmount
        });
    }
}
