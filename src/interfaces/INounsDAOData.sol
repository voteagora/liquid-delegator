// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface INounsDAOData {
    /**
     * @notice Add a signature supporting a new candidate to be proposed to the DAO using `proposeBySigs`, by emitting an event with the signature data.
     * Only lets the signer account submit their signature, to minimize potential spam.
     * @param sig the signature bytes.
     * @param expirationTimestamp the signature's expiration timestamp.
     * @param proposer the proposer account that posted the candidate proposal with the provided slug.
     * @param slug the slug of the proposal candidate signer signed on.
     * @param proposalIdToUpdate if this is an update to an existing proposal, the ID of the proposal to update, otherwise 0.
     * @param encodedProp the abi encoding of the candidate version signed; should be identical to the output of
     * the `NounsDAOV3Proposals.calcProposalEncodeData` function.
     * @param reason signer's reason free text.
     */
    function addSignature(
        bytes memory sig,
        uint256 expirationTimestamp,
        address proposer,
        string memory slug,
        uint256 proposalIdToUpdate,
        bytes memory encodedProp,
        string memory reason
    ) external;
}
