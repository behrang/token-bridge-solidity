// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./SignatureChecker.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IWrappedJetton {
    function isWrappedJetton() external view returns (bool);
}

contract Bridge is SignatureChecker {
    using SafeERC20 for IERC20;
    address[] oracleSet;
    mapping(address => bool) public isOracle;
    mapping(bytes32 => bool) public finishedVotings;
    bool public allowLock;

    event Lock(
        address indexed from,
        address indexed token,
        bytes32 indexed to_addr_hash,
        uint256 value,
        uint8 decimals
    );
    event Unlock(
        address indexed token,
        bytes32 ton_address_hash,
        bytes32 indexed ton_tx_hash,
        uint64 lt,
        address indexed to,
        uint256 value
    );
    event NewOracleSet(uint256 oracleSetHash, address[] newOracles);

    constructor(address[] memory initialSet) {
        _updateOracleSet(0, initialSet);
    }

    function _generalVote(bytes32 digest, Signature[] memory signatures)
        internal
        view
    {
        require(
             signatures.length >= (2 * oracleSet.length + 2) / 3,
            "Not enough signatures"
        );
        require(!finishedVotings[digest], "Vote is already finished");
        uint256 signum = signatures.length;
        uint256 last_signer = 0;
        for (uint256 i = 0; i < signum; i++) {
            address signer = signatures[i].signer;
            require(isOracle[signer], "Unauthorized signer");
            uint256 next_signer = uint256(uint160(signer));
            require(next_signer > last_signer, "Signatures are not sorted");
            last_signer = next_signer;
            checkSignature(digest, signatures[i]);
        }
    }

    function lock(
        address token,
        uint256 amount,
        bytes32 to_address_hash
    ) external {
        require(allowLock, "Lock is currently disabled");
        require(token != address(0), "lock: wrong token address");
        require(token != address(0x582d872A1B094FC48F5DE31D3B73F2D9bE47def1), "lock wrapped toncoin");
        require(token != address(0x76A797A59Ba2C17726896976B7B3747BfD1d220f), "lock wrapped toncoin");
        require(!checkTokenIsWrappedJetton(token), "lock wrapped jetton");

        uint256 totalSupply = IERC20(token).totalSupply();
        require(totalSupply <= 2 ** 120 - 1, "Max totalSupply 2 ** 120 - 1");

        require(amount <= 2 ** 100, "Max amount 2 ** 100");

        uint256 oldBalance = IERC20(token).balanceOf(address(this));

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        uint256 newBalance = IERC20(token).balanceOf(address(this));

        require(newBalance > oldBalance, "newBalance must be greater than oldBalance");

        emit Lock(
            msg.sender,
            token,
            to_address_hash,
            newBalance - oldBalance,
            ERC20(token).decimals()
        );
    }

    function unlock(SwapData calldata data, Signature[] calldata signatures)
        external
    {
        bytes32 _id = getSwapDataId(data);
        _generalVote(_id, signatures);
        finishedVotings[_id] = true;
        IERC20(data.token).safeTransfer(data.receiver, data.amount);
        emit Unlock(data.token, data.tx.address_hash, data.tx.tx_hash, data.tx.lt, data.receiver, data.amount);
    }

    function voteForNewOracleSet(
        uint256 oracleSetHash,
        address[] calldata newOracles,
        Signature[] calldata signatures
    ) external {
        bytes32 _id = getNewSetId(oracleSetHash, newOracles);
        _generalVote(_id, signatures);
        finishedVotings[_id] = true;
        _updateOracleSet(oracleSetHash, newOracles);
    }

    function voteForSwitchLock(
        bool newLockStatus,
        uint256 nonce,
        Signature[] calldata signatures
    ) external {
        bytes32 _id = getNewLockStatusId(newLockStatus, nonce);
        _generalVote(_id, signatures);
        finishedVotings[_id] = true;
        allowLock = newLockStatus;
    }

    function _updateOracleSet(uint256 oracleSetHash, address[] memory newOracles)
        internal
    {
        require(newOracles.length > 2, "New set is too short");
        uint256 oldSetLen = oracleSet.length;
        for (uint256 i = 0; i < oldSetLen; i++) {
            isOracle[oracleSet[i]] = false;
        }
        oracleSet = newOracles;
        uint256 newSetLen = oracleSet.length;
        for (uint256 i = 0; i < newSetLen; i++) {
            require(!isOracle[newOracles[i]], "Duplicate oracle in Set");
            isOracle[newOracles[i]] = true;
        }
        emit NewOracleSet(oracleSetHash, newOracles);
    }

    function getFullOracleSet() external view returns (address[] memory) {
        return oracleSet;
    }

    function checkTokenIsWrappedJetton(address token) public view returns (bool) {
        try IWrappedJetton(token).isWrappedJetton() returns (
            bool isWrappedJetton
        ) {
            return isWrappedJetton;
        } catch {
            return false;
        }
    }
}
