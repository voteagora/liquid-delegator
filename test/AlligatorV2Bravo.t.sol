// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {AlligatorV2Bravo} from "src/v2/extensions/AlligatorV2Bravo.sol";
import "./utils/AlligatorV2Base.sol";
import "./mock/GovernorBravoMock.sol";

contract AlligatorV2BravoTest is AlligatorV2Base {
    // =============================================================
    //                             TESTS
    // =============================================================

    function setUp() public override {
        SetupV2.setUp();

        governor = new GovernorBravoMock();
        alligator = AlligatorV2(
            payable(
                _create3Factory.deploy(
                    keccak256(bytes("SALT")),
                    bytes.concat(
                        type(AlligatorV2Bravo).creationCode,
                        abi.encode(address(governor), "", 0, address(this))
                    )
                )
            )
        );
        root = alligator.create(address(this), baseRules, true); // selfProxy
    }
}
