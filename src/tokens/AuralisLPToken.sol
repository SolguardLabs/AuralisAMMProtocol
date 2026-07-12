// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20Minimal } from "../interfaces/IERC20Minimal.sol";

/// @title Auralis LP token
/// @notice ERC-20 pool-share implementation with EIP-2612 approvals by signature.
/// @dev Pool contracts inherit this token and expose liquidity operations that call `_mint` and `_burn`.
abstract contract AuralisLPToken is IERC20Minimal {
    /// @notice EIP-712 domain schema used to construct the domain separator.
    bytes32 internal constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    /// @notice EIP-2612 permit schema.
    bytes32 public constant PERMIT_TYPEHASH = keccak256(
        "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
    );

    /// @dev Highest valid secp256k1 signature `s` value, preventing signature malleability.
    uint256 private constant SECP256K1N_HALF =
        0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;

    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    uint256 public override totalSupply;
    mapping(address account => uint256 balance) public override balanceOf;
    mapping(address owner => mapping(address spender => uint256 amount)) public override allowance;

    /// @notice Current permit nonce for each token owner.
    mapping(address owner => uint256 nonce) public nonces;

    uint256 private immutable INITIAL_CHAIN_ID;
    bytes32 private immutable INITIAL_DOMAIN_SEPARATOR;
    bytes32 private immutable HASHED_NAME;

    error ZeroAddress();
    error InsufficientBalance(address account, uint256 balance, uint256 required);
    error InsufficientAllowance(address spender, uint256 allowance, uint256 required);
    error PermitExpired(uint256 deadline);
    error InvalidPermitSigner(address recovered, address expected);
    error InvalidSignatureS();
    error InvalidSignatureV();
    error SupplyOverflow();

    /// @param name_ Human-readable token name.
    /// @param symbol_ Token ticker.
    constructor(
        string memory name_,
        string memory symbol_
    ) {
        name = name_;
        symbol = symbol_;
        HASHED_NAME = keccak256(bytes(name_));
        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = _computeDomainSeparator();
    }

    /// @notice Returns the EIP-712 domain separator for the current chain.
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return
            block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : _computeDomainSeparator();
    }

    /// @inheritdoc IERC20Minimal
    function approve(
        address spender,
        uint256 value
    ) external override returns (bool success) {
        _approve(msg.sender, spender, value);
        return true;
    }

    /// @inheritdoc IERC20Minimal
    function transfer(
        address to,
        uint256 value
    ) external override returns (bool success) {
        _transfer(msg.sender, to, value);
        return true;
    }

    /// @inheritdoc IERC20Minimal
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external override returns (bool success) {
        _spendAllowance(from, msg.sender, value);
        _transfer(from, to, value);
        return true;
    }

    /// @notice Atomically increases `spender`'s allowance.
    function increaseAllowance(
        address spender,
        uint256 addedValue
    ) external returns (bool success) {
        uint256 currentAllowance = allowance[msg.sender][spender];
        if (addedValue > type(uint256).max - currentAllowance) revert SupplyOverflow();
        _approve(msg.sender, spender, currentAllowance + addedValue);
        return true;
    }

    /// @notice Atomically decreases `spender`'s allowance.
    function decreaseAllowance(
        address spender,
        uint256 subtractedValue
    ) external returns (bool success) {
        uint256 currentAllowance = allowance[msg.sender][spender];
        if (currentAllowance < subtractedValue) {
            revert InsufficientAllowance(spender, currentAllowance, subtractedValue);
        }
        unchecked {
            _approve(msg.sender, spender, currentAllowance - subtractedValue);
        }
        return true;
    }

    /// @notice Sets an ERC-20 allowance using an EIP-712 signature from `owner`.
    /// @param owner Account granting the allowance.
    /// @param spender Account receiving the allowance.
    /// @param value New allowance.
    /// @param deadline Last timestamp at which the signature is valid.
    /// @param v Recovery identifier.
    /// @param r First ECDSA signature component.
    /// @param s Second ECDSA signature component.
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        // Timestamp-based expiry is part of the EIP-2612 permit specification.
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp > deadline) revert PermitExpired(deadline);
        if (owner == address(0) || spender == address(0)) revert ZeroAddress();
        if (uint256(s) > SECP256K1N_HALF) revert InvalidSignatureS();
        if (v != 27 && v != 28) revert InvalidSignatureV();

        uint256 nonce = nonces[owner];
        bytes32 structHash =
            keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));
        address recovered = ecrecover(digest, v, r, s);
        if (recovered == address(0) || recovered != owner) {
            revert InvalidPermitSigner(recovered, owner);
        }

        if (nonce == type(uint256).max) revert SupplyOverflow();
        unchecked {
            nonces[owner] = nonce + 1;
        }
        _approve(owner, spender, value);
    }

    /// @notice Moves tokens between two nonzero accounts.
    function _transfer(
        address from,
        address to,
        uint256 value
    ) internal virtual {
        if (from == address(0) || to == address(0)) revert ZeroAddress();
        uint256 fromBalance = balanceOf[from];
        if (fromBalance < value) revert InsufficientBalance(from, fromBalance, value);

        unchecked {
            balanceOf[from] = fromBalance - value;
            balanceOf[to] += value;
        }
        emit Transfer(from, to, value);
    }

    /// @notice Creates `value` tokens for `to`.
    function _mint(
        address to,
        uint256 value
    ) internal virtual {
        if (to == address(0)) revert ZeroAddress();
        uint256 supply = totalSupply;
        if (value > type(uint256).max - supply) revert SupplyOverflow();

        unchecked {
            totalSupply = supply + value;
            balanceOf[to] += value;
        }
        emit Transfer(address(0), to, value);
    }

    /// @notice Destroys `value` tokens belonging to `from`.
    function _burn(
        address from,
        uint256 value
    ) internal virtual {
        if (from == address(0)) revert ZeroAddress();
        uint256 fromBalance = balanceOf[from];
        if (fromBalance < value) revert InsufficientBalance(from, fromBalance, value);

        unchecked {
            balanceOf[from] = fromBalance - value;
            totalSupply -= value;
        }
        emit Transfer(from, address(0), value);
    }

    /// @notice Writes an allowance and emits the corresponding ERC-20 event.
    function _approve(
        address owner,
        address spender,
        uint256 value
    ) internal virtual {
        if (owner == address(0) || spender == address(0)) revert ZeroAddress();
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    /// @notice Consumes a finite allowance while preserving infinite approvals.
    function _spendAllowance(
        address owner,
        address spender,
        uint256 value
    ) internal virtual {
        uint256 currentAllowance = allowance[owner][spender];
        if (currentAllowance == type(uint256).max) return;
        if (currentAllowance < value) {
            revert InsufficientAllowance(spender, currentAllowance, value);
        }

        unchecked {
            allowance[owner][spender] = currentAllowance - value;
        }
        emit Approval(owner, spender, allowance[owner][spender]);
    }

    function _computeDomainSeparator() private view returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH, HASHED_NAME, keccak256("1"), block.chainid, address(this)
            )
        );
    }
}
