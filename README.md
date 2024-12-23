# Dripio: Payment Streaming Ecosystem

Este proyecto consiste en tres contratos principales escritos en Solidity (versión 0.8.28) que conforman un sistema de **Payment Streaming** para empresas, proyectos y empleados. El objetivo es permitir que cada empresa gestione presupuestos, proyectos y empleados, ofreciendo pagos continuos (streams) de forma segura y transparente, con la posibilidad de administrar bonus y cancelar flujos de pago según las reglas configuradas.

---

## Estructura de Contratos

1. **Treasury.sol**  
   - Se encarga de **custodiar los fondos** de cada empresa en sub-bóvedas diferenciadas.  
   - Soporta múltiples tokens (USDC, USDT, DAI) y Ether (usando `address(0)` como identificador).  
   - Solo los **contratos autorizados** pueden retirar fondos (por ejemplo, el contrato `PaymentStreaming`).  
   - Emite eventos `Deposit`, `Withdraw` y `AuthorizedContract`.

2. **CompanyRegistry.sol**  
   - Registra **empresas**, **proyectos** y **empleados**.  
   - Controla la **propiedad** de cada empresa.  
   - Permite a los dueños de empresa crear proyectos, añadir empleados y dar de baja a los empleados.  
   - Emite eventos `CompanyCreated`, `ProjectCreated`, `EmployeeAdded` y `EmployeeRemoved`.

3. **PaymentStreaming.sol**  
   - **Recibe** los fondos reservados en la `Treasury` para cada empresa y crea **streams** de pago para los empleados.  
   - Maneja la lógica de **salarios** y **bonus** (o “isBonus”), calculando cuánto pueden retirar los empleados en cada momento.  
   - Permite **cancelar** un stream y devolver fondos no retirados al tesoro de la empresa.  
   - Emite eventos `StreamCreated`, `Withdraw` y `StreamCancelled`.

---

## Resumen del Funcionamiento

1. **Creación de Empresa**  
   - Usar `CompanyRegistry.createCompany(companyId)` para registrar una nueva empresa.  
   - Solo un `companyId` que no exista puede ser creado.

2. **Creación de Proyecto**  
   - El dueño de la empresa llama a `CompanyRegistry.createProject(projectId, companyId, startDate, endDate)`.  
   - Se define el **rango temporal** del proyecto.  
   - Registra el proyecto como activo.

3. **Añadir Empleados**  
   - El dueño del proyecto (dueño de la empresa asociada) añade empleados vía `CompanyRegistry.addEmployee(projectId, wallet, hasBonus)`.

4. **Depositar Fondos**  
   - La empresa deposita fondos en su **sub-bóveda** usando `Treasury.depositFunds(companyId, token, amount)` o enviando Ether si `token == address(0)`.

5. **Crear Streams de Pago**  
   - En `PaymentStreaming.createStream(...)`, se define el `totalAmount`, `startTime`, `endTime` y si es un **bonus**.  
   - El contrato `PaymentStreaming` debe estar **autorizado** en `Treasury` para poder luego retirar fondos a favor del empleado.

6. **Retirar Fondos (Empleado)**  
   - El empleado llama a `PaymentStreaming.withdraw(streamId)`.  
   - Se calcula el saldo acumulado (`balanceOf(streamId)`) y se transfiere desde la `Treasury` hasta la cuenta del empleado.

7. **Cancelar Stream**  
   - El dueño del proyecto puede llamar a `PaymentStreaming.cancelStream(streamId)`.  
   - Cualquier saldo no retirado se considera devuelto al tesoro de la empresa (lógica conceptual, no hay transferencia on-chain si nunca se liberó).

---

## Despliegue Rápido

1. **Instalación**  
   - Asegúrate de tener [Node.js](https://nodejs.org/) y un entorno de desarrollo para Solidity (por ejemplo, [Hardhat](https://hardhat.org/)) o [Truffle](https://trufflesuite.com/).

2. **Compilación**  
   - Ubica los archivos `Treasury.sol`, `CompanyRegistry.sol` y `PaymentStreaming.sol` en tu carpeta de contratos.  
   - Ejecuta el comando en Hardhat o Truffle para compilar:  
     ```bash
     npx hardhat compile
     ```
     o  
     ```bash
     truffle compile
     ```

3. **Despliegue**  
   - Despliega `Treasury.sol` primero.  
   - Despliega `CompanyRegistry.sol`.  
   - Despliega `PaymentStreaming.sol`, pasando como argumentos del constructor la dirección del `Treasury` y de `CompanyRegistry`.  
     ```bash
     npx hardhat run scripts/deploy.js --network <networkName>
     ```

4. **Configuración**  
   - Autoriza `PaymentStreaming` en la `Treasury`:
     ```solidity
     // Llamada a setAuthorizedContract en el contrato Treasury
     treasury.setAuthorizedContract(paymentStreamingAddress, true);
     ```

5. **Tests**  
   - Implementa pruebas unitarias (por ejemplo, en [Hardhat](https://hardhat.org/guides/testing.html)) para verificar la lógica de depósitos, retiros, creación de empresas y flujos de pago.

---

## Consideraciones de Seguridad

- **Access Control**:  
  Actualmente, la autorización se maneja de manera básica (e.g. `onlyProjectOwner`). Para un entorno de producción, revisa añadir [OpenZeppelin AccessControl](https://docs.openzeppelin.com/contracts/4.x/access-control) o `Ownable` a cada contrato que requiera mayor granularidad de roles.

- **Pruebas y Auditoría**:  
  Siempre es recomendable realizar pruebas extensivas (unitarias e integradas) y, de ser posible, una auditoría externa antes de emplear estos contratos en entornos con activos reales.

- **Cancelación de Streams**:  
  Al cancelar, el contrato asume que los fondos no retirados son devueltos a la empresa. Si deseas un enfoque distinto (por ejemplo, un porcentaje de indemnización para el empleado), ajusta la lógica en `cancelStream`.

- **Overflows / Underflows**:  
  Solidity 0.8.x incluye cheques de overflow automáticos, por lo que ya no se utiliza `SafeMath`.  
  Aún así, revisa cuidadosamente cualquier cálculo de tasas y duraciones.

---

## Licencia

Este proyecto está disponible bajo la licencia [MIT](https://opensource.org/licenses/MIT).

---

¡Gracias por usar **Dripio**! Si tienes dudas o deseas contribuir, no dudes en abrir un _issue_ o un _pull request_ en este repositorio.  
