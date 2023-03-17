// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {ProxyV2} from "./ProxyV2.sol";
import {ENSHelper} from "../utils/ENSHelper.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {INounsDAOV2} from "../interfaces/INounsDAOV2.sol";
import {IRule} from "../interfaces/IRule.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/IAlligatorV2.sol";

contract AlligatorV2 is IAlligatorV2, ENSHelper, Ownable, Pausable {
    // =============================================================
    //                             ERRORS
    // =============================================================

    error BadSignature();
    error NotDelegated(address from, address to, uint256 requiredPermissions);
    error TooManyRedelegations(address from, address to);
    error NotValidYet(address from, address to, uint256 willBeValidFrom);
    error NotValidAnymore(address from, address to, uint256 wasValidUntil);
    error TooEarly(address from, address to, uint256 blocksBeforeVoteCloses);
    error InvalidCustomRule(address from, address to, address customRule);

    // =============================================================
    //                       IMMUTABLE STORAGE
    // =============================================================

    INounsDAOV2 public immutable governor;

    uint8 internal constant PERMISSION_VOTE = 1;
    uint8 internal constant PERMISSION_SIGN = 1 << 1;
    uint8 internal constant PERMISSION_PROPOSE = 1 << 2;

    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    bytes32 internal constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support)");

    /// @notice The maximum priority fee used to cap gas refunds in `castRefundableVote`
    uint256 public constant MAX_REFUND_PRIORITY_FEE = 2 gwei;

    /// @notice The vote refund gas overhead, including 7K for ETH transfer and 29K for general transaction overhead
    uint256 public constant REFUND_BASE_GAS = 36000;

    /// @notice The maximum gas units the DAO will refund voters on; supports about 9,190 characters
    uint256 public constant MAX_REFUND_GAS_USED = 200_000;

    /// @notice The maximum basefee the DAO will refund voters on
    uint256 public constant MAX_REFUND_BASE_FEE = 200 gwei;

    // =============================================================
    //                        MUTABLE STORAGE
    // =============================================================

    // Subdelegation rules to `to` for all proxies owned by `from`
    mapping(address from => mapping(address to => Rules subDelegationRules)) public subDelegations;

    // Subdelegation rules to `to` for a single proxy owned by `from`
    mapping(bytes32 proxyHash => mapping(address from => mapping(address to => Rules subDelegationRules)))
        public subDelegationsProxy;

    mapping(address proxyAddress => mapping(bytes32 hashSig => bool isSignatureValid)) internal validSignatures;

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================

    constructor(
        INounsDAOV2 _governor,
        string memory _ensName,
        bytes32 _ensNameHash,
        address _initOwner
    ) ENSHelper(_ensName, _ensNameHash) {
        governor = _governor;
        _transferOwnership(_initOwner);
    }

    // =============================================================
    //                      PROXY OPERATIONS
    // =============================================================

    /**
     * @notice Deploy a new Proxy for an owner deterministically.
     *
     * @param owner The owner of the Proxy.
     * @param proxyRules The base rules of the Proxy.
     * @param registerEnsName Whether to register the ENS name for the Proxy.
     *
     * @return endpoint Address of the Proxy
     */
    function create(address owner, Rules calldata proxyRules, bool registerEnsName) public returns (address endpoint) {
        endpoint = address(
            new ProxyV2{salt: bytes32(uint256(uint160(owner)))}(
                address(governor),
                proxyRules.permissions,
                proxyRules.maxRedelegations,
                proxyRules.notValidBefore,
                proxyRules.notValidAfter,
                proxyRules.blocksBeforeVoteCloses,
                proxyRules.customRule
            )
        );
        emit ProxyDeployed(owner, proxyRules, endpoint);

        if (registerEnsName) {
            if (ensNameHash != 0) {
                string memory reverseName = registerDeployment(endpoint);
                ProxyV2(payable(endpoint)).setENSReverseRecord(reverseName);
            }
        }
    }

    /**
     * @notice Register ENS name for an already deployed Proxy.
     *
     * @param owner The owner of the Proxy.
     * @param proxyRules The base rules of the Proxy.
     *
     * @dev Reverts if the ENS name is already set.
     */
    function registerProxyDeployment(address owner, Rules calldata proxyRules) public {
        if (ensNameHash != 0) {
            address proxy = proxyAddress(owner, proxyRules);
            string memory reverseName = registerDeployment(proxy);
            ProxyV2(payable(proxy)).setENSReverseRecord(reverseName);
        }
    }

    // =============================================================
    //                     GOVERNOR OPERATIONS
    // =============================================================

    /**
     * @notice Validate subdelegation rules and make a proposal to the governor.
     *
     * @param proxyRules The base rules of the Proxy.
     * @param authority The authority chain to validate against.
     * @param targets Target addresses for proposal calls
     * @param values Eth values for proposal calls
     * @param signatures Function signatures for proposal calls
     * @param calldatas Calldatas for proposal calls
     * @param description String description of the proposal
     *
     * @return proposalId Proposal id of new proposal
     *
     * @dev Reverts if the proxy has not been created.
     */
    function propose(
        Rules calldata proxyRules,
        address[] calldata authority,
        address[] calldata targets,
        uint256[] calldata values,
        string[] calldata signatures,
        bytes[] calldata calldatas,
        string memory description
    ) external whenNotPaused returns (uint256 proposalId) {
        address proxy = proxyAddress(authority[0], proxyRules);
        // Create a proposal first so the custom rules can validate it
        proposalId = INounsDAOV2(proxy).propose(targets, values, signatures, calldatas, description);
        validate(proxyRules, msg.sender, authority, PERMISSION_PROPOSE, proposalId, 0xFF);
    }

    /**
     * @notice Validate subdelegation rules and cast a vote on the governor.
     *
     * @param proxyRules The base rules of the Proxy to vote from.
     * @param authority The authority chain to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     *
     * @dev Reverts if the proxy has not been created.
     */
    function castVote(
        Rules calldata proxyRules,
        address[] calldata authority,
        uint256 proposalId,
        uint8 support
    ) external whenNotPaused {
        validate(proxyRules, msg.sender, authority, PERMISSION_VOTE, proposalId, support);

        address proxy = proxyAddress(authority[0], proxyRules);
        INounsDAOV2(proxy).castVote(proposalId, support);
        emit VoteCast(proxy, msg.sender, authority, proposalId, support);
    }

    /**
     * @notice Validate subdelegation rules and cast a vote with reason on the governor.
     *
     * @param proxyRules The base rules of the Proxy to vote from.
     * @param authority The authority chain to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     *
     * @dev Reverts if the proxy has not been created.
     */
    function castVoteWithReason(
        Rules calldata proxyRules,
        address[] calldata authority,
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) public whenNotPaused {
        validate(proxyRules, msg.sender, authority, PERMISSION_VOTE, proposalId, support);

        address proxy = proxyAddress(authority[0], proxyRules);
        INounsDAOV2(proxy).castVoteWithReason(proposalId, support, reason);
        emit VoteCast(proxy, msg.sender, authority, proposalId, support);
    }

    /**
     * @notice Validate subdelegation rules and cast multiple votes with reason on the governor.
     *
     * @param proxyRules The base rules of the Proxies to vote from.
     * @param authorities The authority chains to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     *
     * @dev Reverts if the proxy has not been created.
     */
    function castVotesWithReasonBatched(
        Rules[] calldata proxyRules,
        address[][] calldata authorities,
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) public whenNotPaused {
        address[] memory proxies = new address[](authorities.length);
        address[] memory authority;
        Rules memory rules;

        for (uint256 i; i < authorities.length; ) {
            authority = authorities[i];
            rules = proxyRules[i];
            validate(rules, msg.sender, authority, PERMISSION_VOTE, proposalId, support);
            proxies[i] = proxyAddress(authority[0], rules);
            INounsDAOV2(proxies[i]).castVoteWithReason(proposalId, support, reason);

            unchecked {
                ++i;
            }
        }

        emit VotesCast(proxies, msg.sender, authorities, proposalId, support);
    }

    /**
     * @notice Validate subdelegation rules and cast multiple votes with reason on the governor.
     * Refunds the gas used to cast the votes, if possible.
     *
     * @param proxyRules The base rules of the Proxies to vote from.
     * @param authorities The authority chains to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     *
     * @dev Reverts if the proxy has not been created.
     */
    function castRefundableVotesWithReasonBatched(
        Rules[] calldata proxyRules,
        address[][] calldata authorities,
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) external whenNotPaused {
        uint256 startGas = gasleft();
        castVotesWithReasonBatched(proxyRules, authorities, proposalId, support, reason);
        _refundGas(startGas);
    }

    /**
     * @notice Validate subdelegation rules and cast a vote by signature on the governor.
     *
     * @param proxyRules The base rules of the Proxy to vote from.
     * @param authority The authority chain to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     *
     * @dev Reverts if the proxy has not been created.
     */
    function castVoteBySig(
        Rules calldata proxyRules,
        address[] calldata authority,
        uint256 proposalId,
        uint8 support,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external whenNotPaused {
        bytes32 domainSeparator = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256("Alligator"), block.chainid, address(this))
        );
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);

        if (signatory == address(0)) {
            revert BadSignature();
        }

        validate(proxyRules, signatory, authority, PERMISSION_VOTE, proposalId, support);

        address proxy = proxyAddress(authority[0], proxyRules);
        INounsDAOV2(proxy).castVote(proposalId, support);
        emit VoteCast(proxy, signatory, authority, proposalId, support);
    }

    /**
     * @notice Validate subdelegation rules and sign a hash.
     *
     * @param proxyRules The base rules of the Proxy to sign from.
     * @param authority The authority chain to validate against.
     * @param hash The hash to sign.
     */
    function sign(Rules calldata proxyRules, address[] calldata authority, bytes32 hash) external whenNotPaused {
        validate(proxyRules, msg.sender, authority, PERMISSION_SIGN, 0, 0xFE);

        address proxy = proxyAddress(authority[0], proxyRules);
        validSignatures[proxy][hash] = true;
        emit Signed(proxy, authority, hash);
    }

    // =============================================================
    //                        SUBDELEGATIONS
    // =============================================================

    /**
     * @notice Subdelegate all sender Proxies to an address with rules.
     *
     * @param to The address to subdelegate to.
     * @param subDelegateRules The rules to apply to the subdelegation.
     */
    function subDelegateAll(address to, Rules calldata subDelegateRules) external {
        subDelegations[msg.sender][to] = subDelegateRules;
        emit SubDelegation(msg.sender, to, subDelegateRules);
    }

    /**
     * @notice Subdelegate all sender Proxies to multiple addresses with rules.
     *
     * @param targets The addresses to subdelegate to.
     * @param subDelegateRules The rules to apply to the subdelegations.
     */
    function subDelegateAllBatched(address[] calldata targets, Rules[] calldata subDelegateRules) external {
        for (uint256 i; i < targets.length; ) {
            subDelegations[msg.sender][targets[i]] = subDelegateRules[i];

            unchecked {
                ++i;
            }
        }

        emit SubDelegations(msg.sender, targets, subDelegateRules);
    }

    /**
     * @notice Subdelegate one Proxy to an address with rules.
     * Creates a Proxy for `proxyOwner` and `proxyRules` if it does not exist.
     *
     * @param proxyOwner Owner of the proxy being subdelegated.
     * @param proxyRules The base rules of the Proxy to sign from.
     * @param to The address to subdelegate to.
     * @param subDelegateRules The rules to apply to the subdelegation.
     */
    function subDelegate(
        address proxyOwner,
        Rules calldata proxyRules,
        address to,
        Rules calldata subDelegateRules
    ) external {
        if (proxyAddress(proxyOwner, proxyRules).code.length == 0) {
            create(proxyOwner, proxyRules, false);
        }

        subDelegationsProxy[keccak256(abi.encode(proxyOwner, proxyRules))][msg.sender][to] = subDelegateRules;
        emit SubDelegationProxy(msg.sender, to, subDelegateRules, proxyOwner, proxyRules);
    }

    /**
     * @notice Subdelegate one Proxy to multiple addresses with rules.
     * Creates a Proxy for `proxyOwner` and `proxyRules` if it does not exist.
     *
     * @param proxyOwner Owner of the proxy being subdelegated.
     * @param proxyRules The base rules of the Proxy to sign from.
     * @param targets The addresses to subdelegate to.
     * @param subDelegateRules The rules to apply to the subdelegations.
     */
    function subDelegateBatched(
        address proxyOwner,
        Rules calldata proxyRules,
        address[] calldata targets,
        Rules[] calldata subDelegateRules
    ) external {
        if (proxyAddress(proxyOwner, proxyRules).code.length == 0) {
            create(proxyOwner, proxyRules, false);
        }

        for (uint256 i; i < targets.length; ) {
            subDelegationsProxy[keccak256(abi.encode(proxyOwner, proxyRules))][msg.sender][
                targets[i]
            ] = subDelegateRules[i];

            unchecked {
                ++i;
            }
        }

        emit SubDelegationProxies(msg.sender, targets, subDelegateRules, proxyOwner, proxyRules);
    }

    // =============================================================
    //                         VIEW FUNCTIONS
    // =============================================================

    /**
     * @notice Validate subdelegation rules. Proxy-specific delegations override address-specific delegations.
     *
     * @param proxyRules The base rules of the Proxy.
     * @param sender The sender address to validate.
     * @param authority The authority chain to validate against.
     * @param permissions The permissions to validate.
     * @param proposalId The id of the proposal for which validation is being performed.
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain, 0xFF=proposal
     */
    function validate(
        Rules memory proxyRules,
        address sender,
        address[] memory authority,
        uint256 permissions,
        uint256 proposalId,
        uint256 support
    ) public view {
        uint256 authorityLength = authority.length;

        // Validate base proxy rules
        _validateRules(
            proxyRules,
            sender,
            authorityLength,
            permissions,
            proposalId,
            support,
            address(0),
            address(0),
            1
        );

        address from = authority[0];

        if (from == sender) {
            return;
        }

        bytes32 proxyHash = keccak256(abi.encode(from, proxyRules));
        address to;
        Rules memory subdelegationRules;
        for (uint256 i = 1; i < authorityLength; ) {
            to = authority[i];
            // Retrieve proxy-specific rules
            subdelegationRules = subDelegationsProxy[proxyHash][from][to];
            // If a subdelegation is not present, retrieve address-specific rules
            if (subdelegationRules.permissions == 0) subdelegationRules = subDelegations[from][to];

            unchecked {
                // Validate subdelegation rules
                _validateRules(
                    subdelegationRules,
                    sender,
                    authorityLength,
                    permissions,
                    proposalId,
                    support,
                    from,
                    to,
                    ++i // pass `i + 1` and increment at the same time
                );
            }

            from = to;
        }

        if (from == sender) {
            return;
        }

        revert NotDelegated(from, sender, permissions);
    }

    /**
     * @notice Checks if proxy signature is valid.
     *
     * @param proxy The address of the proxy contract.
     * @param proxyRules The base rules of the Proxy.
     * @param hash The hash to validate.
     * @param data The data to validate.
     *
     * @return magicValue `IERC1271.isValidSignature` if signature is valid, or 0 if not.
     */
    function isValidProxySignature(
        address proxy,
        Rules calldata proxyRules,
        bytes32 hash,
        bytes calldata data
    ) public view returns (bytes4 magicValue) {
        if (data.length > 0) {
            (address[] memory authority, bytes memory signature) = abi.decode(data, (address[], bytes));
            address signer = ECDSA.recover(hash, signature);
            validate(proxyRules, signer, authority, PERMISSION_SIGN, 0, 0xFE);
            return IERC1271.isValidSignature.selector;
        }
        return validSignatures[proxy][hash] ? IERC1271.isValidSignature.selector : bytes4(0);
    }

    /**
     * @notice Returns the address of the proxy contract for a given owner.
     *
     * @param owner The owner of the Proxy.
     * @param proxyRules The base rules of the Proxy.
     *
     * @return endpoint The address of the Proxy.
     */
    function proxyAddress(address owner, Rules memory proxyRules) public view returns (address endpoint) {
        endpoint = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            bytes32(uint256(uint160(owner))), // salt
                            keccak256(
                                abi.encodePacked(
                                    type(ProxyV2).creationCode,
                                    abi.encode(
                                        address(governor),
                                        proxyRules.permissions,
                                        proxyRules.maxRedelegations,
                                        proxyRules.notValidBefore,
                                        proxyRules.notValidAfter,
                                        proxyRules.blocksBeforeVoteCloses,
                                        proxyRules.customRule
                                    )
                                )
                            )
                        )
                    )
                )
            )
        );
    }

    // =============================================================
    //                  RESTRICTED, INTERNAL, OTHER
    // =============================================================

    /**
     * @notice Pauses and unpauses propose, vote and sign operations.
     *
     * @dev Only contract owner can toggle pause.
     */
    function _togglePause() external onlyOwner {
        if (!paused()) {
            _pause();
        } else {
            _unpause();
        }
    }

    // Refill Alligator's balance for gas refunds
    receive() external payable {}

    function _validateRules(
        Rules memory rules,
        address sender,
        uint256 authorityLength,
        uint256 permissions,
        uint256 proposalId,
        uint256 support,
        address from,
        address to,
        uint256 redelegationIndex
    ) private view {
        /// @dev `maxRedelegation` cannot overflow as it increases by 1 each iteration
        /// @dev block.number + rules.blocksBeforeVoteCloses cannot overflow uint256
        unchecked {
            if ((rules.permissions & permissions) != permissions) {
                revert NotDelegated(from, to, permissions);
            }
            if (rules.maxRedelegations + redelegationIndex < authorityLength) {
                revert TooManyRedelegations(from, to);
            }
            if (block.timestamp < rules.notValidBefore) {
                revert NotValidYet(from, to, rules.notValidBefore);
            }
            if (rules.notValidAfter != 0) {
                if (block.timestamp > rules.notValidAfter) revert NotValidAnymore(from, to, rules.notValidAfter);
            }
            if (rules.blocksBeforeVoteCloses != 0) {
                INounsDAOV2.ProposalCondensed memory proposal = governor.proposals(proposalId);
                if (proposal.endBlock > uint256(block.number) + uint256(rules.blocksBeforeVoteCloses)) {
                    revert TooEarly(from, to, rules.blocksBeforeVoteCloses);
                }
            }
            if (rules.customRule != address(0)) {
                if (
                    IRule(rules.customRule).validate(address(governor), sender, proposalId, uint8(support)) !=
                    IRule.validate.selector
                ) {
                    revert InvalidCustomRule(from, to, rules.customRule);
                }
            }
        }
    }

    function _refundGas(uint256 startGas) internal {
        unchecked {
            uint256 balance = address(this).balance;
            if (balance == 0) {
                return;
            }
            uint256 basefee = min(block.basefee, MAX_REFUND_BASE_FEE);
            uint256 gasPrice = min(tx.gasprice, basefee + MAX_REFUND_PRIORITY_FEE);
            uint256 gasUsed = min(startGas - gasleft() + REFUND_BASE_GAS, MAX_REFUND_GAS_USED);
            uint256 refundAmount = min(gasPrice * gasUsed, balance);
            (bool refundSent, ) = msg.sender.call{value: refundAmount}("");
            emit RefundableVote(msg.sender, refundAmount, refundSent);
        }
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
