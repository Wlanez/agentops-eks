# Taller guiado: Terraform + AWS + EKS + AgentOps

**Objetivo:** aprender a diseñar, explicar, implementar, comprobar y operar una plataforma real. No es un curso de copiar comandos ni un reemplazo de la implementación de referencia.

**Ruta:** AWS identity → Terraform state → VPC/routing → EKS → ECR/Helm/CI-CD → observabilidad → agentes de solo lectura → acciones aprobadas → controles de producción.

## Reglas del taller

1. **Problema primero:** explicar qué falla o qué necesidad existe antes de mencionar un servicio de AWS.
2. **Modelo mental:** describir los componentes, límites de confianza, flujo de datos y dependencias.
3. **Comparar alternativas:** al menos una decisión de arquitectura con costo, seguridad y disponibilidad.
4. **Terraform con intención:** predecir el plan y revisar sus efectos antes de ejecutar cambios.
5. **Evidencia:** demostrar con pruebas, estados observables y resultados sanitizados, no solo capturas de consola.
6. **Fallo intencional:** provocar un error seguro o un test RED y explicar por qué ocurre.
7. **IA como copiloto verificado:** dejar que proponga opciones; no delegarle privilegios, aprobación de planes ni conclusiones sin evidencia.
8. **Explicación de entrevista:** resumir la decisión en español y en inglés simple con estructura *Context → Decision → Tradeoff → Verification*.

El orden concreto se adapta al estado real del repositorio. No se crea una cuenta ni se provisiona EKS hasta revisar permisos, costos, contrato del plan y guardas de seguridad.

## Estado real del proyecto

Consulta [Estado y siguiente sesión](progress.md) antes de comenzar. La evidencia de la cuenta AWS ya está en [AWS account bootstrap](../evidence/v0.1/aws-account-bootstrap.md). El trabajo de backend remoto y VPC está en [PR #3 (borrador)](https://github.com/Wlanez/agentops-eks/pull/3), todavía no fusionado en main.

No confundir:
- **Diseñado:** se escribió una especificación o plan.
- **Probado localmente:** pasaron validaciones/test con mocks o sin cambios AWS.
- **Verificado en AWS:** se ejecutaron readbacks o comprobaciones reales documentadas.
- **Mergeado:** el código está en main.
- **Milestone terminado:** el Definition of Done completo tiene evidencia.

## Laboratorios actuales

| Orden | Lección | Resultado | Estado |
|---|---|---|---|
| 0 | Identidad y límites de cuenta | SSO, perfiles, privilegios, presupuestos | Evidencia completada |
| 1 | [Terraform state y seguridad](01-terraform-state.md) | Explicar backend remoto, locks y drift | Implementado/verificado según evidencia del PR; pendiente merge |
| 2 | [Networking de AWS desde primeros principios](02-vpc-networking.md) | Explicar y probar VPC, routing y egreso | Implementación local en PR; pendientes guardas y AWS readback |
| 3 | EKS, identidades y nodos privados | Cluster y nodos Ready | Por implementar |
| 4 | ECR, FastAPI, Helm y CI/CD | Commit → imagen → despliegue verificado | Por implementar |
| 5 | Observabilidad y SRE | Diagnóstico basado en métricas/logs/traces | v0.2, después de v0.1 |
| 6 | Agent reliability, seguridad y FinOps | Agentes limitados, evaluados y auditables | v0.3–v0.5 |

## Una sesión de 45–60 minutos

- **10 min — explicar:** qué problema resolvemos y qué componentes intervienen.
- **15 min — predecir:** dibujar dependencias, plan esperado y riesgos.
- **15–20 min — ejecutar pruebas:** validaciones deterministas, test RED/GREEN o lectura segura.
- **10 min — explicar el fallo:** por qué una opción incorrecta rompe la arquitectura.
- **5 min — evidencia + entrevista:** registrar resultados sin identificadores sensibles y grabar una explicación breve en inglés.

## Aprendizajes transferibles a AI Platform

- Terraform enseña **cambio controlado, estado, detección de drift e idempotencia**; lo mismo aplica a ejecutores de agentes.
- VPC + IAM enseñan **límites y mínimo privilegio**; los agentes necesitan los mismos controles y límites de acción.
- EKS/Helm enseñan **releases, health y rollback**; en AgentOps los cambios también deben ser reversibles y verificables.
- Observabilidad enseña **evidencia antes de inferencia**. No introducir agentes de diagnóstico hasta que un humano pueda diagnosticar el caso base.
- FinOps enseña **costos marginales y tradeoffs**: infraestructura fija, egreso, herramientas, llamadas de modelo y reintentos.

## Seguridad y costo

No publicar account IDs, ARNs, nombre de bucket, endpoints privados, IP públicas asignadas, estado Terraform ni tokens. Evitar pegar salidas completas de plan/apply. Nunca ejecutar `terraform apply` solo porque el código pasó lint/tests: en el PR actual faltan verificaciones y existe un NAT Gateway con costo recurrente. El presupuesto de AWS es una alerta, **no un interruptor que detiene cargos**.

## Referencias internas

- [Roadmap y Definition of Done](../../ROADMAP.md)
- [v0.1 Foundation](../milestones/v0.1-foundation.md)
- [Guía docente v0.1](../instructor/v0.1-teaching-guide.md)
- [AI Platform from First Principles](../instructor/first-principles.md)

**Criterio de éxito:** poder explicar la arquitectura sin tener los archivos Terraform delante, anticipar al menos dos fallos y verificar las decisiones con evidencia repetible.
