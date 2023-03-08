// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IAlligatorV2} from "../interfaces/IAlligatorV2.sol";
import {IENSReverseRegistrar} from "../interfaces/IENSReverseRegistrar.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import "../structs/Rules.sol";

contract ProxyV2 is IERC1271 {
    address internal immutable alligator;
    address internal immutable governor;

    // Rules
    uint256 public immutable permissions;
    uint256 public immutable maxRedelegations;
    uint256 public immutable notValidBefore;
    uint256 public immutable notValidAfter;
    uint256 public immutable blocksBeforeVoteCloses;
    address public immutable customRule;

    constructor(address _governor, Rules memory _rules) {
        alligator = msg.sender;
        governor = _governor;

        permissions = _rules.permissions;
        maxRedelegations = _rules.maxRedelegations;
        notValidBefore = _rules.notValidBefore;
        notValidAfter = _rules.notValidAfter;
        blocksBeforeVoteCloses = _rules.blocksBeforeVoteCloses;
        customRule = _rules.customRule;
    }

    function isValidSignature(bytes32 hash, bytes calldata signature) external view override returns (bytes4) {
        return
            IAlligatorV2(alligator).isValidProxySignature(
                address(this),
                Rules(
                    uint8(permissions),
                    uint8(maxRedelegations),
                    uint32(notValidBefore),
                    uint32(notValidAfter),
                    uint16(blocksBeforeVoteCloses),
                    customRule
                ),
                hash,
                signature
            );
    }

    function setENSReverseRecord(string calldata name) external {
        require(msg.sender == alligator);
        IENSReverseRegistrar(0x084b1c3C81545d370f3634392De611CaaBFf8148).setName(name);
    }

    fallback() external payable {
        require(msg.sender == alligator);
        address addr = governor;

        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := call(gas(), addr, callvalue(), 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    // `receive` is omitted to minimize contract size
}
