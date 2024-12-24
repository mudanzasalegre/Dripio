// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RoleManager
 * @dev Contrato centralizado para asignar y administrar roles usando AccessControl de OpenZeppelin.
 *      La idea es permitir que cada empresa (companyId) y cada proyecto (projectId) asigne
 *      permisos a usuarios específicos, sin duplicar lógica en cada contrato.
 */
contract RoleManager is AccessControl {
    // Roles "globales" (usados como plantilla)
    bytes32 public constant COMPANY_OWNER_ROLE = keccak256("COMPANY_OWNER_ROLE");
    bytes32 public constant PROJECT_ADMIN_ROLE  = keccak256("PROJECT_ADMIN_ROLE");
    bytes32 public constant TREASURY_ADMIN_ROLE = keccak256("TREASURY_ADMIN_ROLE");
    bytes32 public constant PAYMENT_ADMIN_ROLE  = keccak256("PAYMENT_ADMIN_ROLE");
    // Podrías añadir EMPLOYEE_MANAGER_ROLE, etc.

    // Deployer => DEFAULT_ADMIN_ROLE
    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev Asigna un rol a un usuario. Solo un ADMIN puede hacerlo.
     *      En un diseño más avanzado, podrías mapear (companyId, projectId, user) => roles,
     *      pero para el ejemplo usamos roles "globales" + tenemos en cuenta la "dueñez" de la compañía.
     */
    function assignRole(address user, bytes32 role) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not global admin");
        _setupRole(role, user);
    }

    /**
     * @dev Revoca un rol a un usuario. Solo un ADMIN puede hacerlo.
     */
    function revokeRoleCustom(address user, bytes32 role) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not global admin");
        _revokeRole(role, user);
    }

    /**
     * @dev Verifica si `user` tiene un `role`.
     */
    function hasRoleCustom(bytes32 role, address user) external view returns (bool) {
        return hasRole(role, user);
    }
}