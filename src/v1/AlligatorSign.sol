// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {INounsDAOV2} from "../interfaces/INounsDAOV2.sol";
import {INounsDAOData} from "../interfaces/INounsDAOData.sol";
import {Alligator} from "./Alligator.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {AddSignatureParams} from "../structs/AddSignatureParams.sol";
import {ProxySign} from "./ProxySign.sol";

contract AlligatorSign is Alligator {
    // =============================================================
    //                             ERRORS
    // =============================================================

    error InvalidLength();

    // =============================================================
    //                             EVENTS
    // =============================================================

    event SignedBatch(address proxy, address[] authority, bytes32[] hashes);

    // =============================================================
    //                       IMMUTABLE STORAGE
    // =============================================================

    bytes32 public constant PROPOSAL_TYPEHASH =
        keccak256(
            "Proposal(address proposer,address[] targets,uint256[] values,string[] signatures,bytes[] calldatas,string description,uint256 expiry)"
        );

    bytes32 public constant UPDATE_PROPOSAL_TYPEHASH =
        keccak256(
            "UpdateProposal(uint256 proposalId,address proposer,address[] targets,uint256[] values,string[] signatures,bytes[] calldatas,string description,uint256 expiry)"
        );

    INounsDAOData public immutable nounsDAOData;

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================

    constructor(
        INounsDAOV2 _governor,
        INounsDAOData _nounsDAOData,
        string memory _ensName,
        bytes32 _ensNameHash
    ) Alligator(_governor, _ensName, _ensNameHash) {
        nounsDAOData = _nounsDAOData;
    }

    // =============================================================
    //                       WRITE FUNCTIONS
    // =============================================================

    /**
     * @notice Add a signature from a proxy supporting a new candidate to be proposed to the DAO using `proposeBySigs`, on NounsDAOData contract.
     *
     * @param authority The authority chain to validate against.
     * @param params Array of parameters for each signature
     */
    function addSignature(address[] calldata authority, AddSignatureParams calldata params) external whenNotPaused {
        validate(msg.sender, authority, PERMISSION_PROPOSE, 0, 0xFE);
        address proxy = proxyAddress(authority[0]);

        bytes32 sigHash = sigDigest(
            params.proposalIdToUpdate == 0 ? PROPOSAL_TYPEHASH : UPDATE_PROPOSAL_TYPEHASH,
            params.encodedProp,
            params.expirationTimestamp,
            address(governor)
        );
        validSignatures[proxy][sigHash] = true;

        INounsDAOData(proxy).addSignature(
            params.sig,
            params.expirationTimestamp,
            params.proposer,
            params.slug,
            params.proposalIdToUpdate,
            params.encodedProp,
            params.reason
        );

        emit Signed(proxy, authority, sigHash);
    }

    /**
     * @notice Add multiple signatures in batch from a single proxy.
     *
     * @param authority The authority chain to validate against.
     * @param params Array of parameters for each signature
     */
    function addSignatureBatch(
        address[] calldata authority,
        AddSignatureParams[] calldata params
    ) external whenNotPaused {
        validate(msg.sender, authority, PERMISSION_PROPOSE, 0, 0xFE);
        address proxy = proxyAddress(authority[0]);

        uint256 length = params.length;
        bytes32[] memory hashes = new bytes32[](length);
        AddSignatureParams memory param;
        bytes32 sigHash;
        for (uint256 i; i < length; ) {
            param = params[i];

            sigHash = sigDigest(
                param.proposalIdToUpdate == 0 ? PROPOSAL_TYPEHASH : UPDATE_PROPOSAL_TYPEHASH,
                param.encodedProp,
                param.expirationTimestamp,
                address(governor)
            );
            validSignatures[proxy][sigHash] = true;
            hashes[i] = sigHash;

            INounsDAOData(proxy).addSignature(
                param.sig,
                param.expirationTimestamp,
                param.proposer,
                param.slug,
                param.proposalIdToUpdate,
                param.encodedProp,
                param.reason
            );

            unchecked {
                ++i;
            }
        }

        emit SignedBatch(proxy, authority, hashes);
    }

    /**
     * @notice Validate subdelegation rules and sign a hash.
     *
     * @param authority The authority chain to validate against.
     * @param hashes The hashes to sign.
     */
    function signBatch(address[] calldata authority, bytes32[] calldata hashes) external whenNotPaused {
        validate(msg.sender, authority, PERMISSION_SIGN, 0, 0xFE);
        address proxy = proxyAddress(authority[0]);

        uint256 length = hashes.length;
        for (uint256 i; i < length; ) {
            validSignatures[proxy][hashes[i]] = true;

            unchecked {
                ++i;
            }
        }

        emit SignedBatch(proxy, authority, hashes);
    }

    /**
     * @notice Deploy a new Proxy for an owner deterministically.
     *
     * @param owner The owner of the Proxy.
     * @param registerEnsName Whether to register the ENS name for the Proxy.
     *
     * @return endpoint Address of the Proxy
     */
    function create(address owner, bool registerEnsName) public virtual override returns (address endpoint) {
        endpoint = address(
            new ProxySign{salt: bytes32(uint256(uint160(owner)))}(address(governor), address(nounsDAOData))
        );
        emit ProxyDeployed(owner, endpoint);

        if (registerEnsName) {
            if (ensNameHash != 0) {
                string memory reverseName = registerDeployment(endpoint);
                ProxySign(payable(endpoint)).setENSReverseRecord(reverseName);
            }
        }
    }

    /**
     * @notice Generate the digest (hash) used to verify proposal signatures.
     *
     * @param typehash the EIP 712 type hash of the signed message, e.g. `PROPOSAL_TYPEHASH` or `UPDATE_PROPOSAL_TYPEHASH`.
     * @param proposalEncodeData the abi encoded proposal data, identical to the output of `calcProposalEncodeData`.
     * @param expirationTimestamp the signature's expiration timestamp.
     * @param verifyingContract the contract verifying the signature, e.g. the DAO proxy by default.
     *
     * @return bytes32 the signature's typed data hash.
     */
    function sigDigest(
        bytes32 typehash,
        bytes memory proposalEncodeData,
        uint256 expirationTimestamp,
        address verifyingContract
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encodePacked(typehash, proposalEncodeData, expirationTimestamp));

        bytes32 domainSeparator = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256(bytes("Nouns DAO")), block.chainid, verifyingContract)
        );

        return ECDSA.toTypedDataHash(domainSeparator, structHash);
    }
}
