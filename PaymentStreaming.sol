// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./Treasury.sol";
import "./CompanyRegistry.sol";

/**
 * @title PaymentStreaming
 * @dev Maneja la creación y gestión de streams de pago para salarios y bonuses,
 *      calculando saldos acumulados a lo largo del tiempo.
 */
contract PaymentStreaming {
    // -- Custom Errors -- //
    error ProjectNotActive(uint256 projectId);
    error NotProjectOwner(address caller, uint256 projectId);
    error StreamNotActive(uint256 streamId);
    error NotStreamRecipient(address caller, uint256 streamId);
    error InvalidTimeRange(uint256 startTime, uint256 endTime);
    error ZeroTotalAmount();
    error EmployeeNotActive(address employee, uint256 projectId);
    error NothingToWithdraw(uint256 streamId);
    error StreamAlreadyInactive(uint256 streamId);

    Treasury public treasury;
    CompanyRegistry public registry;

    // Identificador para Ether en el contrato Treasury
    address public constant ETHER = address(0);

    // Datos del stream
    struct Stream {
        uint256 streamId;
        uint256 projectId;
        address token;       // USDC, USDT, DAI o address(0) para Ether
        address recipient;   // Empleado
        uint256 totalAmount; // Total a cobrar
        uint256 startTime;   // Timestamp inicio
        uint256 endTime;     // Timestamp fin
        uint256 withdrawn;   // Cuánto ha retirado ya
        bool isBonus;        // Indica si es un bonus
        bool isActive;       
    }

    // streamId -> Stream
    mapping(uint256 => Stream) public streams;
    uint256 public nextStreamId;

    // -- Eventos -- //
    event StreamCreated(
        uint256 indexed streamId,
        uint256 indexed projectId,
        address token,
        address indexed recipient,
        uint256 totalAmount,
        uint256 startTime,
        uint256 endTime,
        bool isBonus
    );

    event Withdraw(uint256 indexed streamId, address indexed recipient, uint256 amount);
    event StreamCancelled(uint256 indexed streamId, uint256 refundedAmount);

    // -- Constructor -- //
    constructor(address _treasury, address _registry) {
        treasury = Treasury(_treasury);
        registry = CompanyRegistry(_registry);
    }

    // -- Modifiers -- //

    /**
     * @dev Verifica que el proyecto esté activo y que el msg.sender sea el owner de la compañía correspondiente.
     */
    modifier onlyProjectOwner(uint256 projectId) {
        // Obtenemos la info del proyecto
        (uint256 companyId, , , bool projectActive) = registry.getProjectInfo(projectId);

        if (!projectActive) {
            revert ProjectNotActive(projectId);
        }

        address owner = registry.getCompanyOwner(companyId);
        if (msg.sender != owner) {
            revert NotProjectOwner(msg.sender, projectId);
        }
        _;
    }

    /**
     * @dev Verifica que el stream exista, esté activo y que el msg.sender sea su destinatario.
     */
    modifier onlyRecipient(uint256 streamId) {
        Stream memory s = streams[streamId];
        if (!s.isActive) {
            revert StreamNotActive(streamId);
        }
        if (msg.sender != s.recipient) {
            revert NotStreamRecipient(msg.sender, streamId);
        }
        _;
    }

    // -- Funciones Principales -- //

    /**
     * @notice Crea un stream de pago para un empleado.
     * @param projectId   ID del proyecto al que pertenece el empleado.
     * @param token       Dirección del token (o address(0) para Ether).
     * @param recipient   Dirección del empleado que recibirá el pago.
     * @param totalAmount Cantidad total a asignar en el stream.
     * @param startTime   Momento a partir del cual el empleado empieza a acumular saldo.
     * @param endTime     Momento final de acumulación de saldo.
     * @param isBonus     Indica si es un stream de bonus.
     * @return streamId   ID único del stream creado.
     */
    function createStream(
        uint256 projectId,
        address token,
        address recipient,
        uint256 totalAmount,
        uint256 startTime,
        uint256 endTime,
        bool isBonus
    )
        external
        onlyProjectOwner(projectId)
        returns (uint256 streamId)
    {
        if (endTime <= startTime) {
            revert InvalidTimeRange(startTime, endTime);
        }
        if (totalAmount == 0) {
            revert ZeroTotalAmount();
        }

        // Verificar si el empleado está activo en el proyecto
        bool employeeActive = registry.isEmployeeActive(projectId, recipient);
        if (!employeeActive) {
            revert EmployeeNotActive(recipient, projectId);
        }

        // Creamos el stream
        streamId = nextStreamId++;
        streams[streamId] = Stream({
            streamId: streamId,
            projectId: projectId,
            token: token,
            recipient: recipient,
            totalAmount: totalAmount,
            startTime: startTime,
            endTime: endTime,
            withdrawn: 0,
            isBonus: isBonus,
            isActive: true
        });

        emit StreamCreated(
            streamId,
            projectId,
            token,
            recipient,
            totalAmount,
            startTime,
            endTime,
            isBonus
        );
    }

    /**
     * @notice Calcula cuánto puede retirar el empleado en este momento.
     * @param streamId ID del stream.
     * @return El monto acumulado pendiente de retirar.
     */
    function balanceOf(uint256 streamId) public view returns (uint256) {
        Stream memory s = streams[streamId];
        if (!s.isActive || block.timestamp < s.startTime) {
            return 0;
        }

        // Calculamos el tiempo transcurrido
        uint256 elapsed = block.timestamp < s.endTime
            ? block.timestamp - s.startTime
            : s.endTime - s.startTime;

        uint256 duration = s.endTime - s.startTime;
        // Tasa de acumulación por segundo
        uint256 ratePerSec = s.totalAmount / duration;
        // Cuánto se ha generado hasta ahora
        uint256 earnedSoFar = elapsed * ratePerSec;

        // Si, por alguna razón, lo ya retirado es mayor (unlikely), retornamos 0
        if (earnedSoFar <= s.withdrawn) {
            return 0;
        }
        return earnedSoFar - s.withdrawn;
    }

    /**
     * @notice El empleado retira los fondos que ha acumulado hasta el momento.
     * @param streamId ID del stream del que se desea retirar.
     */
    function withdraw(uint256 streamId) external onlyRecipient(streamId) {
        uint256 amount = balanceOf(streamId);
        if (amount == 0) {
            revert NothingToWithdraw(streamId);
        }

        // Actualizamos la cantidad retirada
        streams[streamId].withdrawn += amount;

        // Obtenemos la info para retirar los fondos de la Tesorería
        uint256 projectId = streams[streamId].projectId;
        (uint256 companyId, , , ) = registry.getProjectInfo(projectId);

        treasury.withdrawFunds(companyId, streams[streamId].token, amount, msg.sender);

        emit Withdraw(streamId, msg.sender, amount);
    }

    /**
     * @notice Cancela un stream y devuelve la parte no retirada al tesoro de la empresa.
     *         El caller debe ser el dueño del proyecto correspondiente.
     * @param streamId ID del stream a cancelar.
     */
    function cancelStream(uint256 streamId) external {
        Stream storage s = streams[streamId];
        if (!s.isActive) {
            revert StreamAlreadyInactive(streamId);
        }

        // Verificamos que el proyecto esté activo y el caller sea el dueño
        uint256 projectId = s.projectId;
        (uint256 companyId, , , bool projectActive) = registry.getProjectInfo(projectId);
        if (!projectActive) {
            revert ProjectNotActive(projectId);
        }
        address owner = registry.getCompanyOwner(companyId);
        if (msg.sender != owner) {
            revert NotProjectOwner(msg.sender, projectId);
        }

        // Calculamos cuánto le falta por retirar al empleado
        uint256 currentBalance = balanceOf(streamId);
        // Lo no retirado (totalAmount - withdrawn - currentBalance)
        uint256 unwithdrawn = s.totalAmount - s.withdrawn - currentBalance;

        // Marcamos el stream como inactivo
        s.isActive = false;

        // Se "refunde" la parte no retirada y la parte no reclamada (currentBalance)
        uint256 refund = unwithdrawn + currentBalance;

        // En este diseño no es necesario mover tokens dentro de PaymentStreaming,
        // pues ya estaban "reservados" en la sub-bóveda del Treasury.
        // Queda a criterio de la empresa permitir o no al empleado retirar "currentBalance".
        // Aquí, simplemente, se notifica que esa parte vuelve al control total de la empresa.

        emit StreamCancelled(streamId, refund);
    }
}
