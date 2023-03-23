// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {AlligatorV2Open} from "src/v2/extensions/AlligatorV2Open.sol";
import "./utils/AlligatorV2Base.sol";
import "./mock/GovernorOZMock.sol";

contract AlligatorV2OpenTest is AlligatorV2Base {
    // =============================================================
    //                             TESTS
    // =============================================================

    function setUp() public override {
        SetupV2.setUp();

        governor = new GovernorOZMock();
        alligator = AlligatorV2(
            payable(
                _create3Factory.deploy(
                    keccak256(bytes("SALT")),
                    bytes.concat(
                        type(AlligatorV2Open).creationCode,
                        abi.encode(address(governor), "", 0, address(this))
                    )
                )
            )
        );
        root = alligator.create(address(this), baseRules, true); // selfProxy
    }
}
