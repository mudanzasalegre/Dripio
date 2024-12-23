// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title Treasury
 * @dev Contrato para almacenar los fondos de múltiples empresas,
 *      cada una con su propia "sub-bóveda".
 */
contract Treasury {
    // -- Custom Errors -- //
    error NotAuthorized(address caller);
    error InsufficientFunds(uint256 available, uint256 requested);
    error EtherTransferFailed();
    error ERC20TransferFailed();
    error InvalidTokenAmount();
    error NoEtherSent();

    // Mapeo: companyId -> (tokenAddress -> balance)
    mapping(uint256 => mapping(address => uint256)) private balances;

    // Dirección "especial" para manejar Ether dentro del contrato
    address public constant ETHER = address(0);

    // Mapeo de contratos autorizados (p.ej. PaymentStreaming) => true/false
    mapping(address => bool) public authorizedContracts;

    // -- Eventos -- //
    event Deposit(
        uint256 indexed companyId,
        address indexed token,
        uint256 amount,
        address indexed from
    );

    event Withdraw(
        uint256 indexed companyId,
        address indexed token,
        uint256 amount,
        address indexed to
    );

    event AuthorizedContract(address indexed contractAddress, bool authorized);

    // -- Modifiers -- //

    /**
     * @dev Verifica que la llamada provenga de un contrato autorizado.
     *      Puedes añadir lógica adicional para asociar cada contract con un companyId,
     *      o implementar un sistema AccessControl más robusto si lo requieres.
     */
    modifier onlyAuthorized(uint256 companyId) {
        if (!authorizedContracts[msg.sender]) {
            revert NotAuthorized(msg.sender);
        }
        _;
    }

    // -- Funciones -- //

    /**
     * @notice Autoriza o desautoriza un contrato a mover fondos.
     * @dev En un diseño más completo, se usaría Ownable o AccessControl de OpenZeppelin.
     * @param _contract Dirección del contrato que se desea (des)autorizar.
     * @param _authorized Booleano para autorizar o desautorizar.
     */
    function setAuthorizedContract(address _contract, bool _authorized) external {
        // Aquí podrías requerir que solo el "dueño" de la tesorería lo ejecute.
        authorizedContracts[_contract] = _authorized;
        emit AuthorizedContract(_contract, _authorized);
    }

    /**
     * @notice Depositar fondos en la sub-bóveda de una empresa.
     * @param companyId  El ID de la empresa.
     * @param token      La dirección del token (o address(0) para Ether).
     * @param amount     Cantidad a depositar (usar 0 si es Ether).
     *
     * Si `token == ETHER`, se confía en que `msg.value` sea mayor que 0.
     * Si `token != ETHER`, se transfiere 'amount' vía transferFrom.
     */
    function depositFunds(uint256 companyId, address token, uint256 amount) external payable {
        if (token == ETHER) {
            // Depositar Ether
            if (msg.value == 0) {
                revert NoEtherSent();
            }
            balances[companyId][ETHER] += msg.value;
            emit Deposit(companyId, ETHER, msg.value, msg.sender);

        } else {
            // Depositar tokens ERC20
            if (amount == 0) {
                revert InvalidTokenAmount();
            }
            bool success = ERC20(token).transferFrom(msg.sender, address(this), amount);
            if (!success) {
                revert ERC20TransferFailed();
            }
            balances[companyId][token] += amount;
            emit Deposit(companyId, token, amount, msg.sender);
        }
    }

    /**
     * @notice Retirar fondos de la sub-bóveda de la empresa. Solo para contratos autorizados.
     * @param companyId  El ID de la empresa.
     * @param token      La dirección del token (o address(0) para Ether).
     * @param amount     Cantidad a retirar.
     * @param recipient  Dirección que recibirá los fondos.
     */
    function withdrawFunds(
        uint256 companyId,
        address token,
        uint256 amount,
        address recipient
    )
        external
        onlyAuthorized(companyId)
    {
        uint256 available = balances[companyId][token];
        if (available < amount) {
            revert InsufficientFunds(available, amount);
        }

        // Ajuste del balance en la sub-bóveda
        balances[companyId][token] = available - amount;

        if (token == ETHER) {
            // Enviamos Ether
            (bool sent, ) = recipient.call{value: amount}("");
            if (!sent) {
                revert EtherTransferFailed();
            }
        } else {
            // Enviamos tokens ERC20
            bool success = ERC20(token).transfer(recipient, amount);
            if (!success) {
                revert ERC20TransferFailed();
            }
        }

        emit Withdraw(companyId, token, amount, recipient);
    }

    /**
     * @notice Consulta el balance de un token en la sub-bóveda de una empresa.
     * @param companyId El ID de la empresa.
     * @param token     La dirección del token (o address(0) para Ether).
     * @return El balance disponible en la sub-bóveda.
     */
    function getBalance(uint256 companyId, address token) external view returns (uint256) {
        return balances[companyId][token];
    }
}

/**
 * @dev Interfaz mínima de un token ERC20 necesaria para que
 *      la Tesorería pueda transferir o recibir fondos.
 */
interface ERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
}
