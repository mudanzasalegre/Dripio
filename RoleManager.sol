// SPDX-License-Identifier: Propietario Unico
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract RoleManager is AccessControl {
    bytes32 public constant COMPANY_OWNER_ROLE = keccak256("COMPANY_OWNER_ROLE");
    bytes32 public constant PROJECT_ADMIN_ROLE  = keccak256("PROJECT_ADMIN_ROLE");
    bytes32 public constant TREASURY_ADMIN_ROLE = keccak256("TREASURY_ADMIN_ROLE");
    bytes32 public constant PAYMENT_ADMIN_ROLE  = keccak256("PAYMENT_ADMIN_ROLE");

    mapping(uint256 => mapping(address => bool)) private companyProjectAdmins;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function assignRole(address user, bytes32 role) external {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) || 
            hasRole(COMPANY_OWNER_ROLE, msg.sender),
            "RoleManager: must be admin or company owner"
        );
        _grantRole(role, user);
    }

    function revokeRoleCustom(address user, bytes32 role) external {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) || 
            hasRole(COMPANY_OWNER_ROLE, msg.sender),
            "RoleManager: must be admin or company owner"
        );
        _revokeRole(role, user);
    }

    function hasRoleCustom(bytes32 role, address user) external view returns (bool) {
        return hasRole(role, user);
    }

    function assignLocalProjectAdmin(uint256 companyId, address user) external {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) || 
            hasRole(COMPANY_OWNER_ROLE, msg.sender),
            "RoleManager: not allowed to assign local project admin"
        );
        companyProjectAdmins[companyId][user] = true;
    }

    function revokeLocalProjectAdmin(uint256 companyId, address user) external {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) || 
            hasRole(COMPANY_OWNER_ROLE, msg.sender),
            "RoleManager: not allowed to revoke local project admin"
        );
        companyProjectAdmins[companyId][user] = false;
    }

    function isProjectAdminForCompany(uint256 companyId, address user) external view returns (bool) {
        return companyProjectAdmins[companyId][user];
    }
}
