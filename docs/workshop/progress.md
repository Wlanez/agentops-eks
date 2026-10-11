# Estado del taller — 2026-10-11

> Fuente de verdad para el estado: rama `main`, [PR #3](https://github.com/Wlanez/agentops-eks/pull/3), los issues y archivos de evidencia. Los tests ejecutados fuera de GitHub no se vuelven a afirmar como ejecutados aquí.

## Confirmado en main

- El proyecto está estructurado en v0.1–v0.5 con criterios de salida definidos.
- [Bootstrap AWS documentado como completado](../evidence/v0.1/aws-account-bootstrap.md): miembro de AWS Organizations, acceso SSO temporal con MFA, cuenta de laboratorio, separación del management account, alertas USD 10/20/30 y anomalías USD 5.
- **Main aún no contiene Terraform ni despliegue EKS.** El trabajo de implementación no se considera mergeado.

## Confirmado en PR #3 (draft; no mergeado)

- Terraform backend S3 con versión, cifrado, bloqueo nativo `use_lockfile` y separación de claves bootstrap/dev. El PR añade [evidencia sanitizada](https://github.com/Wlanez/agentops-eks/blob/feat/terraform-state-bootstrap/docs/evidence/v0.1/terraform-state-bootstrap.md) de verificaciones reales del backend.
- Terraform VPC `10.20.0.0/16` con dos AZ, dos subnets públicas /20, dos privadas /19, un NAT Gateway y endpoint Gateway de S3.
- Según la descripción del PR: `terraform fmt`, `validate`, pruebas de red y pruebas del root dev pasan **localmente**. No consta `apply` real de la VPC.
- **No ejecutar apply todavía.** El PR identifica pendientes: output `network_contract`, actualizar README de dev, verificador de plan limitado a 19 recursos, lectura AWS sanitizada con mocks, tests de invariantes de routing y normalización final.

## Siguiente checkpoint (sesión actual)

1. Leer [lección 1: Terraform state](01-terraform-state.md) y comprobar que se explica sin memorizar comandos.
2. Leer [lección 2: networking](02-vpc-networking.md); predecir 19 recursos y contrastar CIDR, rutas públicas/privadas y endpoint S3.
3. Trabajar en **PR #3**, no repetir archivos ya implementados ni ejecutar apply sin completar todas las guardas pendientes.
4. Registrar en el PR tests, diff sin errores y aprobación explícita del cambio de costo antes de aplicar.
5. Tras un readback real y revisión de evidencia, actualizar este estado. Solo después fusionar y pasar a EKS.

## Evidencia exigida por checkpoint

| Checkpoint | Evidencia mínima | Afirmación permitida |
|---|---|---|
| AWS account bootstrap | Documento sanitizado con controles reales | Bootstrap AWS completado |
| Backend remoto | Evidencia en PR de state/readback/drift y branch merged | Backend verificado, merge pendiente o completo según corresponda |
| Red local | `fmt`, `validate`, `terraform test`, pruebas de guardas | Contrato local validado |
| Red AWS | Plan con recuento controlado, apply explícitamente autorizado, readback en AWS | Red desplegada y comprobada |
| EKS | Nodes Ready, addon status y prueba de kubeconfig | EKS operable |
| v0.1 | Imagen ECR trazable, Helm, OIDC Actions, smoke test, teardown | Foundation terminada |

## No confundir estado y diseño

Un README que describe arquitectura objetivo **no demuestra** un despliegue. La existencia de tests mock **no demuestra** conectividad real. Una revisión de PR **no autoriza** un `apply` costoso. Al reportar avance, separar explícitamente diseño, test, despliegue y evidencia.
