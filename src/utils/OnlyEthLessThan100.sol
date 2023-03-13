// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {INounsDAOV2} from "../interfaces/INounsDAOV2.sol";
import {IRule} from "../interfaces/IRule.sol";

contract OnlyEthLessThan100 is IRule {
    function validate(
        address governor,
        address, // voter
        uint256 proposalId,
        uint8 // support
    ) external view override returns (bytes4) {
        // TODO: Should we allow vetoing proposals with total eth > 100?

        (
            address[] memory targets,
            uint256[] memory values,
            string[] memory signatures,
            bytes[] memory calldatas
        ) = INounsDAOV2(governor).getActions(proposalId);

        uint256 totalEth;
        for (uint256 i = 0; i < targets.length; i++) {
            totalEth += values[i];
            require(bytes(signatures[i]).length == 0, "OnlyEthLessThan100: no function calls");
            require(calldatas[i].length == 0, "OnlyEthLessThan100: no function calls");
        }

        require(totalEth < 100 ether, "OnlyEthLessThan100: total eth must be less than 100");

        return IRule.validate.selector;
    }
}
