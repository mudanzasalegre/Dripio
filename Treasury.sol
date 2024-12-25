// SPDX-License-Identifier: Propietario Unico
pragma solidity ^0.8.28;

import "./RoleManager.sol";

error NotAuthorized(address caller);
error InsufficientFunds(uint256 available, uint256 requested);
error EtherTransferFailed();
error ERC20TransferFailed();
error InvalidTokenAmount();
error NoEtherSent();

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

contract Treasury {
    RoleManager public roleManager;
    address public constant ETHER = address(0);

    mapping(uint256 => mapping(uint256 => mapping(address => uint256))) private balances;
    mapping(address => bool) public authorizedContracts;

    event Deposit(uint256 indexed companyId, uint256 indexed projectId, address indexed token, uint256 amount, address from);
    event Withdraw(uint256 indexed companyId, uint256 indexed projectId, address indexed token, uint256 amount, address to);
    event AuthorizedContract(address indexed contractAddress, bool authorized);

    modifier onlyTreasuryAdminOrAuthorized(uint256 companyId, uint256 projectId) {
        bool isTreasuryAdmin = roleManager.hasRoleCustom(roleManager.TREASURY_ADMIN_ROLE(), msg.sender);
        bool isAuthorizedContract = authorizedContracts[msg.sender];
        require(isTreasuryAdmin || isAuthorizedContract, "Not treasury admin or authorized");
        _;
    }

    constructor(address _roleManager) {
        roleManager = RoleManager(_roleManager);
    }

    function setAuthorizedContract(address _contract, bool _authorized) external {
        authorizedContracts[_contract] = _authorized;
        emit AuthorizedContract(_contract, _authorized);
    }

    function depositFunds(uint256 companyId, uint256 projectId, address token, uint256 amount) external payable {
        if (token == ETHER) {
            if (msg.value == 0) {
                revert NoEtherSent();
            }
            balances[companyId][projectId][ETHER] += msg.value;
            emit Deposit(companyId, projectId, ETHER, msg.value, msg.sender);
        } else {
            if (amount == 0) {
                revert InvalidTokenAmount();
            }
            bool success = IERC20(token).transferFrom(msg.sender, address(this), amount);
            if (!success) {
                revert ERC20TransferFailed();
            }
            balances[companyId][projectId][token] += amount;
            emit Deposit(companyId, projectId, token, amount, msg.sender);
        }
    }

    function withdrawFunds(uint256 companyId, uint256 projectId, address token, uint256 amount, address recipient)
        external
        onlyTreasuryAdminOrAuthorized(companyId, projectId)
    {
        uint256 available = balances[companyId][projectId][token];
        if (available < amount) {
            revert InsufficientFunds(available, amount);
        }
        balances[companyId][projectId][token] = available - amount;

        if (token == ETHER) {
            (bool sent, ) = recipient.call{value: amount}("");
            if (!sent) {
                revert EtherTransferFailed();
            }
        } else {
            bool success = IERC20(token).transfer(recipient, amount);
            if (!success) {
                revert ERC20TransferFailed();
            }
        }

        emit Withdraw(companyId, projectId, token, amount, recipient);
    }

    function getBalance(uint256 companyId, uint256 projectId, address token) external view returns (uint256) {
        return balances[companyId][projectId][token];
    }
}
