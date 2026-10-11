# Lección 2 — AWS networking: subnets privadas, rutas y costo

**Meta:** poder predecir por dónde viaja un paquete antes de utilizar Terraform. Implementación propuesta: [PR #3](https://github.com/Wlanez/agentops-eks/pull/3); [diseño de red](https://github.com/Wlanez/agentops-eks/blob/feat/terraform-state-bootstrap/docs/superpowers/specs/2026-08-26-dev-network-design.md).

## 1. Pregunta del sistema

Queremos futuros EKS worker nodes en redes privadas, distribuidos en dos zonas, capaces de obtener paquetes y descargar imágenes sin exponer cada nodo a Internet. ¿Qué rutas e identidades necesitamos?

Una VPC proporciona aislamiento lógico de red. Una subnet vive en **una sola Availability Zone**. Una route table decide el siguiente salto para destinos de red. Un security group filtra tráfico a nivel de interfaz y una NACL filtra por subnet. Ninguno reemplaza a IAM.

~~~mermaid
flowchart TB
  INTERNET[Internet] <--> IGW[Internet Gateway]
  IGW <--> PUBLIC[Subnets públicas /20 - AZ A y B]
  PUBLIC --> NAT[NAT Gateway único de laboratorio]
  PRIVATE[Subnets privadas /19 - AZ A y B] -->|0.0.0.0/0 para egreso| NAT
  PRIVATE -->|rutas locales de VPC| VPC[Red VPC 10.20.0.0/16]
  PRIVATE -->|prefijo S3 vía route table| S3EP[S3 Gateway endpoint]
  S3EP --> S3[S3]
~~~

**Precisión clave:** los nodos privados no se vuelven públicos por poder salir vía NAT. NAT aporta conectividad saliente IPv4, no una ruta de entrada iniciada desde Internet. La arquitectura real debe verificar rutas, IP públicas, grupos de seguridad y endpoint EKS cuando llegue ese workstream.

## 2. Topología elegida en la rama

- VPC: `10.20.0.0/16`.
- Exactamente **2 Availability Zones** seleccionadas de forma determinista.
- **2 subnets públicas /20** y **2 subnets privadas /19**.
- **1 NAT Gateway y 1 Elastic IP** para reducir costo de un laboratorio que puede destruirse.
- **1 S3 Gateway endpoint**, asociado a las tablas de ruta privadas.
- Sin EKS, EC2, balanceadores ni security groups prematuros en este workstream.

La descripción del PR exige un plan de **19 recursos AWS a crear**, sin cambios/destrucciones inesperados. Esta cifra es un **contrato propuesto para su verificador pendiente**, no evidencia de que ya se haya aplicado infraestructura.

## 3. Entender los tradeoffs

| Decisión | Beneficio | Costo / límite |
|---|---|---|
| Nodos en privadas | Evitar IP pública por nodo | Requiere rutas o endpoints para dependencias |
| 2 AZ | Aislamiento entre zonas para la futura carga | No garantiza HA si hay un NAT único |
| 1 NAT Gateway | Menor costo fijo que NAT por AZ | Punto único de fallo de egreso y potencial tráfico entre AZ |
| S3 Gateway endpoint | Tráfico S3 por endpoint sin NAT para rutas asociadas | No resuelve llamadas a otras APIs como ECR, STS |
| EKS aún fuera de alcance | Alcance auditable y pruebas focalizadas | No se puede afirmar que nodos EKS ya están Ready |

**Nota de costos:** NAT Gateway suele generar cargos por hora y por datos procesados; EKS y nodos implicarán cargos independientes. Un presupuesto no detiene los cargos. Antes de crear NAT debe existir autorización consciente de costo y teardown.

## 4. Práctica RED → GREEN y sin cargos

1. Dibuja la ruta de un pod privado hacia S3 y hacia ECR. ¿Cuál utiliza el endpoint S3 y cuál sigue requiriendo otro camino?
2. Predice qué falla si una subnet privada recibe `map_public_ip_on_launch = true`.
3. Predice qué falla si la ruta `0.0.0.0/0` de las privadas apunta a Internet Gateway.
4. Lee `terraform/environments/dev/tests/network.tftest.hcl` del PR y determina qué invariantes prueba.
5. Ejecuta `terraform test` con mocks en un checkout confiable, inicializado según la documentación de la rama; compara el resultado con tus predicciones.
6. Revisa que el plan esperado sea solo de creación, con exactamente los recursos permitidos. **No ejecutar apply:** faltan el verificador estricto y readback sanitizado definidos en el PR.

## 5. Preguntas de arquitectura que debes responder

**¿Por qué una subnet se considera pública?** Porque su tabla de rutas permite alcanzar Internet Gateway y los recursos necesitan IP pública/ruta/permisos apropiados; el nombre 'public' no crea conectividad por sí mismo.

**¿Una subnet privada puede acceder a ECR?** Sí, a través de una ruta de egreso/servicios y permisos correctos. Para un diseño sin NAT pueden necesitarse VPC interface endpoints para los servicios necesarios y un Gateway endpoint de S3 para las capas; hay que diseñarlo y medir costo antes de elegir.

**¿Por qué dos AZ no bastan para alta disponibilidad?** Porque disponibilidad extremo a extremo depende también de NAT, nodos, dependencias, balanceadores, capacidad y recovery.

**¿Cómo lo comprobarías en producción?** Terraform plan revisado, readback de subnets y rutas en AWS, pruebas de conectividad y políticas desde un workload no privilegiado y una evaluación de failure domains.

## 6. Respuesta de entrevista en inglés (40–60 segundos)

> I designed a two-AZ VPC with public and private subnets. Worker nodes belong in private subnets, while a NAT Gateway supports outbound connections. For the lab, one NAT saves money but introduces a single point of failure. I would use separate NAT gateways or endpoint-based alternatives depending on availability and cost requirements. I verify this with Terraform tests, a reviewed plan, and AWS readback before calling it deployed.

No decir `I deployed` hasta que exista evidencia de apply/readback reales. Puedes decir `I designed and locally tested` mientras el PR siga sin merge.

## 7. Conexión con agentes

La red es el primer límite de movimiento para agentes. Si un agente necesita usar herramientas externas, especifica salidas permitidas y dependencias antes de darle Internet general. La política de herramientas e IAM **complementan** la red: el NAT no es una política de acceso a APIs.

## Terminado cuando

- Puedes dibujar rutas de Internet, NAT, tráfico local y S3.
- Explicas el costo/disponibilidad del NAT único y una alternativa.
- Diferencias plan con mocks, contrato de recursos, apply y comprobación real en AWS.
- Puedes describir el diseño en inglés sin confundir *designed* y *deployed*.
