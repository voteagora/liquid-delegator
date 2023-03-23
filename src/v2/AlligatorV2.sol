// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {ProxyV2} from "./ProxyV2.sol";
import {Rules} from "../structs/Rules.sol";
import {IAlligatorV2} from "../interfaces/IAlligatorV2.sol";
import {IRule} from "../interfaces/IRule.sol";
import {ENSHelper} from "../utils/ENSHelper.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

abstract contract AlligatorV2 is IAlligatorV2, ENSHelper, Ownable, Pausable {
    // =============================================================
    //                             ERRORS
    // =============================================================

    error BadSignature();
    error InvalidAuthorityChain();
    error NotDelegated(address from, address to, uint256 requiredPermissions);
    error TooManyRedelegations(address from, address to);
    error NotValidYet(address from, address to, uint256 willBeValidFrom);
    error NotValidAnymore(address from, address to, uint256 wasValidUntil);
    error TooEarly(address from, address to, uint256 blocksBeforeVoteCloses);
    error InvalidCustomRule(address from, address to, address customRule);

    // =============================================================
    //                             EVENTS
    // =============================================================

    event ProxyDeployed(address indexed owner, Rules proxyRules, address proxy);
    event SubDelegation(address indexed from, address indexed to, Rules subDelegateRules);
    event SubDelegations(address indexed from, address[] to, Rules[] subDelegateRules);
    event SubDelegationProxy(
        address indexed from,
        address indexed to,
        Rules subDelegateRules,
        address indexed proxyOwner,
        Rules proxyRules
    );
    event SubDelegationProxies(
        address indexed from,
        address[] to,
        Rules[] subDelegateRules,
        address indexed proxyOwner,
        Rules proxyRules
    );
    event VoteCast(
        address indexed proxy,
        address indexed voter,
        address[] authority,
        uint256 proposalId,
        uint8 support
    );
    event VotesCast(
        address[] proxies,
        address indexed voter,
        address[][] authorities,
        uint256 proposalId,
        uint8 support
    );
    event Signed(address indexed proxy, address[] authority, bytes32 messageHash);

    // =============================================================
    //                       IMMUTABLE STORAGE
    // =============================================================

    address public immutable governor;

    uint256 internal constant PERMISSION_VOTE = 1;
    uint256 internal constant PERMISSION_SIGN = 1 << 1;
    uint256 internal constant PERMISSION_PROPOSE = 1 << 2;

    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    bytes32 internal constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support)");

    // =============================================================
    //                        MUTABLE STORAGE
    // =============================================================

    // Subdelegation rules `from` => `to`
    mapping(address from => mapping(address to => Rules subDelegationRules)) public subDelegations;

    // Subdelegation rules `from` => `to`, for a specific proxy
    mapping(bytes32 proxyHash => mapping(address from => mapping(address to => Rules subDelegationRules)))
        public subDelegationsProxy;

    mapping(address proxyAddress => mapping(bytes32 hashSig => bool isSignatureValid)) internal validSignatures;

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================

    constructor(
        address _governor,
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
                governor,
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
        proposalId = _propose(proxy, targets, values, signatures, calldatas, description);
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
        _castVote(proxy, proposalId, support);
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
        _castVoteWithReason(proxy, proposalId, support, reason);
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
        uint256 authorityLength = authorities.length;
        require(authorityLength == proxyRules.length);

        address[] memory proxies = new address[](authorityLength);
        address[] memory authority;
        Rules memory rules;

        for (uint256 i; i < authorityLength; ) {
            authority = authorities[i];
            rules = proxyRules[i];
            validate(rules, msg.sender, authority, PERMISSION_VOTE, proposalId, support);
            proxies[i] = proxyAddress(authority[0], rules);
            _castVoteWithReason(proxies[i], proposalId, support, reason);

            unchecked {
                ++i;
            }
        }

        emit VotesCast(proxies, msg.sender, authorities, proposalId, support);
    }

    /**
     * @notice Validate subdelegation rules and cast multiple refundable votes with reason on the governor.
     * Refunds the gas used to cast the votes up to a limit specified in `governor`.
     *
     * Note: The gas used will not be refunded for authority chains resulting in 0 votes cast.
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
        uint256 authorityLength = authorities.length;
        require(authorityLength == proxyRules.length);

        address[] memory proxies = new address[](authorityLength);
        address[] memory authority;
        Rules memory rules;

        for (uint256 i; i < authorityLength; ) {
            authority = authorities[i];
            rules = proxyRules[i];
            validate(rules, msg.sender, authority, PERMISSION_VOTE, proposalId, support);
            proxies[i] = proxyAddress(authority[0], rules);
            _castRefundableVoteWithReason(proxies[i], proposalId, support, reason);

            unchecked {
                ++i;
            }
        }

        emit VotesCast(proxies, msg.sender, authorities, proposalId, support);
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
        _castVote(proxy, proposalId, support);
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
        uint256 targetsLength = targets.length;
        require(targetsLength == subDelegateRules.length);

        for (uint256 i; i < targetsLength; ) {
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
        uint256 targetsLength = targets.length;
        require(targetsLength == subDelegateRules.length);

        if (proxyAddress(proxyOwner, proxyRules).code.length == 0) {
            create(proxyOwner, proxyRules, false);
        }

        for (uint256 i; i < targetsLength; ) {
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

        if (from != sender) revert NotDelegated(from, sender, permissions);
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
            if (proxy != proxyAddress(authority[0], proxyRules)) revert InvalidAuthorityChain();
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
                                        governor,
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
    //                   CUSTOM GOVERNOR FUNCTIONS
    // =============================================================

    /**
     * @notice Make a proposal on the governor.
     *
     * @param proxy The address of the Proxy
     * @param targets Target addresses for proposal calls
     * @param values Eth values for proposal calls
     * @param signatures Function signatures for proposal calls
     * @param calldatas Calldatas for proposal calls
     * @param description String description of the proposal
     * @return proposalId ID of the created proposal
     */
    function _propose(
        address proxy,
        address[] calldata targets,
        uint256[] calldata values,
        string[] calldata signatures,
        bytes[] calldata calldatas,
        string memory description
    ) internal virtual returns (uint256 proposalId);

    /**
     * @notice Cast a vote on the governor.
     *
     * @param proxy The address of the Proxy
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     */
    function _castVote(address proxy, uint256 proposalId, uint8 support) internal virtual;

    /**
     * @notice Cast a vote on the governor with reason.
     *
     * @param proxy The address of the Proxy
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     */
    function _castVoteWithReason(
        address proxy,
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) internal virtual;

    /**
     * @notice Cast a refundable vote on the governor with reason.
     *
     * @param proxy The address of the Proxy
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     */
    function _castRefundableVoteWithReason(
        address proxy,
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) internal virtual;

    /**
     * @notice Retrieve number of the proposal's end block.
     *
     * @param proposalId The id of the proposal to vote on
     * @return endBlock Proposal's end block number
     */
    function _proposalEndBlock(uint256 proposalId) internal view virtual returns (uint256 endBlock);

    // =============================================================
    //                     RESTRICTED, INTERNAL
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
                if (_proposalEndBlock(proposalId) > uint256(block.number) + uint256(rules.blocksBeforeVoteCloses)) {
                    revert TooEarly(from, to, rules.blocksBeforeVoteCloses);
                }
            }
            if (rules.customRule != address(0)) {
                if (
                    IRule(rules.customRule).validate(governor, sender, proposalId, uint8(support)) !=
                    IRule.validate.selector
                ) {
                    revert InvalidCustomRule(from, to, rules.customRule);
                }
            }
        }
    }
}
