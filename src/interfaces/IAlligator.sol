// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

struct Rules {
  uint8 permissions;
  uint8 maxRedelegations;
  uint32 notValidBefore;
  uint32 notValidAfter;
  uint16 blocksBeforeVoteCloses;
  address customRule;
}

interface IAlligator {
  function create(address owner) external returns (address endpoint);

  function proxyAddress(address owner) external view returns (address endpoint);

  function propose(
    address[] calldata authority,
    address[] calldata targets,
    uint256[] calldata values,
    string[] calldata signatures,
    bytes[] calldata calldatas,
    string calldata description
  ) external returns (uint256 proposalId);

  function castVote(address[] calldata authority, uint256 proposalId, uint8 support) external;

  function castVoteWithReason(
    address[] calldata authority,
    uint256 proposalId,
    uint8 support,
    string calldata reason
  ) external;

  function castVotesWithReasonBatched(
    address[][] calldata authorities,
    uint256 proposalId,
    uint8 support,
    string calldata reason
  ) external;

  function castRefundableVotesWithReasonBatched(
    address[][] calldata authorities,
    uint256 proposalId,
    uint8 support,
    string calldata reason
  ) external;

  function castVoteBySig(
    address[] calldata authority,
    uint256 proposalId,
    uint8 support,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external;

  function sign(address[] calldata authority, bytes32 hash) external;

  function isValidProxySignature(
    address proxy,
    bytes32 hash,
    bytes calldata data
  ) external view returns (bytes4 magicValue);

  function subDelegate(address to, Rules calldata rules) external;

  function subDelegateBatched(address[] calldata targets, Rules[] calldata rules) external;

  function validate(
    address sender,
    address[] memory authority,
    uint8 permissions,
    uint256 proposalId,
    uint8 support
  ) external view;
}
