// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public immutable decimals;

    uint256 public totalSupply;
    uint24 public transferFeePpm;
    address public feeRecipient;

    mapping(address account => uint256 amount) public balanceOf;
    mapping(address owner => mapping(address spender => uint256 amount)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    error InsufficientBalance();
    error InsufficientAllowance();
    error InvalidFee();
    error ZeroAddress();

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) {
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
        feeRecipient = address(0xFEE);
    }

    function mint(
        address recipient,
        uint256 amount
    ) external {
        if (recipient == address(0)) revert ZeroAddress();
        totalSupply += amount;
        balanceOf[recipient] += amount;
        emit Transfer(address(0), recipient, amount);
    }

    function burn(
        address owner,
        uint256 amount
    ) external {
        uint256 balance = balanceOf[owner];
        if (balance < amount) revert InsufficientBalance();
        unchecked {
            balanceOf[owner] = balance - amount;
            totalSupply -= amount;
        }
        emit Transfer(owner, address(0), amount);
    }

    function setTransferFee(
        uint24 feePpm,
        address recipient
    ) external {
        if (feePpm > 1_000_000) revert InvalidFee();
        if (recipient == address(0)) revert ZeroAddress();
        transferFeePpm = feePpm;
        feeRecipient = recipient;
    }

    function approve(
        address spender,
        uint256 amount
    ) external returns (bool) {
        if (spender == address(0)) revert ZeroAddress();
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(
        address owner,
        address recipient,
        uint256 amount
    ) external returns (bool) {
        uint256 currentAllowance = allowance[owner][msg.sender];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < amount) revert InsufficientAllowance();
            unchecked {
                allowance[owner][msg.sender] = currentAllowance - amount;
            }
            emit Approval(owner, msg.sender, allowance[owner][msg.sender]);
        }
        _transfer(owner, recipient, amount);
        return true;
    }

    function _transfer(
        address owner,
        address recipient,
        uint256 amount
    ) internal {
        if (recipient == address(0)) revert ZeroAddress();
        uint256 balance = balanceOf[owner];
        if (balance < amount) revert InsufficientBalance();

        uint256 fee = amount * transferFeePpm / 1_000_000;
        uint256 received = amount - fee;
        unchecked {
            balanceOf[owner] = balance - amount;
            balanceOf[recipient] += received;
        }
        emit Transfer(owner, recipient, received);

        if (fee != 0) {
            balanceOf[feeRecipient] += fee;
            emit Transfer(owner, feeRecipient, fee);
        }
    }
}
