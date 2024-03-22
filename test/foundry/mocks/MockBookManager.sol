// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../contracts/external/clober-v2/BookId.sol";
import "../../../contracts/external/clober-v2/IHooks.sol";
import "../../../contracts/external/clober-v2/Currency.sol";
import "../../../contracts/external/clober-v2/FeePolicy.sol";

contract MockBookManager {
    function getBookKey(BookId) external pure returns (IBookManager.BookKey memory) {
        IHooks hooks;
        return IBookManager.BookKey({
            base: CurrencyLibrary.NATIVE,
            unit: 10 ** 6,
            quote: CurrencyLibrary.NATIVE,
            makerPolicy: FeePolicyLibrary.encode(true, -100),
            hooks: hooks,
            takerPolicy: FeePolicyLibrary.encode(true, -100)
        });
    }
}
